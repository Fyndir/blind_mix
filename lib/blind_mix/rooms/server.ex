defmodule BlindMix.Rooms.Server do
  @moduledoc """
  Processus d'une room multijoueur : il détient les joueurs, la manche en cours et
  les scores, et diffuse à chaque changement un état public sur PubSub
  (`"room:<code>"`, message `{:room, state}`).

  Mode « course » : les 5 mêmes pistes jouent chez tout le monde, le premier qui
  trouve une piste marque les points et la retire du mix pour tous.

  Les titres et artistes ne quittent jamais ce processus avant d'être trouvés :
  l'état public ne contient que des identifiants et des URL d'extraits.
  """
  use GenServer, restart: :temporary

  require Logger

  alias BlindMix.Accounts.Scope
  alias BlindMix.{DevTools, Game, History, Taste}
  alias BlindMix.Rooms.{Music, Picker, Player}

  @candidates 14
  @feed_size 8
  @pool_cap 800
  @expand_per_round 3
  @history_provider "room"

  # --- Démarrage ---------------------------------------------------------------

  def start_link(code), do: GenServer.start_link(__MODULE__, code, name: via(code))

  def via(code), do: {:via, Registry, {BlindMix.Rooms.Registry, code}}

  @impl true
  def init(code) do
    state = %{
      code: code,
      players: %{},
      host_id: nil,
      status: :lobby,
      game: nil,
      round_id: 0,
      found_by: %{},
      pool: [],
      pool_keys: MapSet.new(),
      expanded: MapSet.new(),
      played: MapSet.new(),
      common_count: 0,
      feed: [],
      seq: 0,
      error: nil,
      music: Music.impl(),
      tasks: %{},
      idle_ref: nil
    }

    {:ok, state |> run_task(:hits, fn -> state.music.hits() end) |> schedule_idle()}
  end

  # --- Appels ------------------------------------------------------------------

  @impl true
  def handle_call({:join, info, pid}, _from, state) do
    ref = Process.monitor(pid)
    new? = not Map.has_key?(state.players, info.id)

    player =
      case Map.fetch(state.players, info.id) do
        {:ok, player} ->
          %{player | name: info.name}

        :error ->
          %Player{
            id: info.id,
            name: info.name,
            user: info.user,
            taste: initial_taste(info.user),
            joined_at: state.seq
          }
      end

    player = %{player | pids: Map.put(player.pids, ref, pid)}

    state =
      %{state | players: Map.put(state.players, player.id, player), seq: state.seq + 1}
      |> elect_host()
      |> cancel_idle()
      |> then(&if(new?, do: feed(&1, "👋 #{player.name} a rejoint la room"), else: &1))
      |> refresh_common()
      |> broadcast()

    {:reply, {:ok, public(state)}, state}
  end

  def handle_call({:likes, id, status}, _from, state) do
    case Map.fetch(state.players, id) do
      {:ok, player} ->
        player = put_likes(player, status)

        state =
          %{state | players: Map.put(state.players, id, player)}
          |> likes_feed(player, status)
          |> refresh_common()
          |> broadcast()

        {:reply, :ok, state}

      :error ->
        {:reply, {:error, :unknown_player}, state}
    end
  end

  def handle_call({:ready, id, ready?}, _from, state) do
    state = update_player(state, id, &%{&1 | ready?: ready?}) |> broadcast()
    {:reply, :ok, state}
  end

  def handle_call({:start_round, id}, _from, %{host_id: id, status: status} = state)
      when status in [:lobby, :finished] do
    players = state.players |> Map.values() |> Enum.filter(&Player.connected?/1)
    %{pool: pool, played: played, music: music} = state

    state =
      %{state | status: :preparing, error: nil}
      |> run_task({:round, status}, fn -> build_round(music, players, pool, played) end)
      |> broadcast()

    {:reply, :ok, state}
  end

  def handle_call({:start_round, _id}, _from, state), do: {:reply, {:error, :not_allowed}, state}

  def handle_call({:guess, id, text}, _from, %{status: :playing} = state)
      when is_map_key(state.players, id) do
    {game, hits} = Game.guess(state.game, text)
    state = apply_hits(%{state | game: game}, id, hits)
    state = if game.status == :finished, do: finish_round(state), else: state
    {:reply, {:ok, hits}, broadcast(state)}
  end

  def handle_call({:guess, _id, _text}, _from, state), do: {:reply, {:error, :not_playing}, state}

  # Outils de développement : piste marquée trouvée par ce joueur, sans saisie.
  def handle_call({:dev_found, id, track_id, kind}, _from, %{status: :playing} = state)
      when is_map_key(state.players, id) and kind in [:title, :artist] do
    if DevTools.enabled?() do
      {game, hits} = Game.force(state.game, track_id, kind)
      state = apply_hits(%{state | game: game}, id, hits)
      state = if game.status == :finished, do: finish_round(state), else: state
      {:reply, :ok, broadcast(state)}
    else
      {:reply, {:error, :not_allowed}, state}
    end
  end

  # Outils de développement : fin de manche immédiate (ce qui reste compte comme raté).
  def handle_call(:dev_finish, _from, %{status: :playing} = state) do
    if DevTools.enabled?() do
      {:reply, :ok, state |> finish_round() |> broadcast()}
    else
      {:reply, {:error, :not_allowed}, state}
    end
  end

  def handle_call({:dev_found, _id, _track_id, _kind}, _from, state),
    do: {:reply, {:error, :not_allowed}, state}

  def handle_call(:dev_finish, _from, state), do: {:reply, {:error, :not_allowed}, state}

  def handle_call(:state, _from, state), do: {:reply, public(state), state}

  # --- Messages ------------------------------------------------------------------

  @impl true
  def handle_info({:tick, round_id}, %{status: :playing, round_id: round_id} = state) do
    game = Game.tick(state.game)
    state = %{state | game: game}

    state =
      if game.status == :finished do
        finish_round(state)
      else
        schedule_tick(state)
      end

    {:noreply, broadcast(state)}
  end

  def handle_info({:tick, _old_round}, state), do: {:noreply, state}

  # Résultat d'une tâche de fond (Task.Supervisor.async_nolink).
  def handle_info({ref, result}, state) when is_map_key(state.tasks, ref) do
    Process.demonitor(ref, [:flush])
    {kind, tasks} = Map.pop(state.tasks, ref)
    {:noreply, task_done(%{state | tasks: tasks}, kind, result)}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, state)
      when is_map_key(state.tasks, ref) do
    {kind, tasks} = Map.pop(state.tasks, ref)
    Logger.warning("Room #{state.code} : tâche #{inspect(kind)} interrompue (#{inspect(reason)})")
    {:noreply, task_done(%{state | tasks: tasks}, kind, {:error, reason})}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case Enum.find(state.players, fn {_id, p} -> Map.has_key?(p.pids, ref) end) do
      nil ->
        {:noreply, state}

      {id, player} ->
        player = %{player | pids: Map.delete(player.pids, ref)}
        state = %{state | players: Map.put(state.players, id, player)}

        state =
          if Player.connected?(player) do
            state
          else
            state
            |> feed("🚪 #{player.name} a quitté la room")
            |> elect_host()
            |> refresh_common()
            |> schedule_idle()
          end

        {:noreply, broadcast(state)}
    end
  end

  def handle_info({:idle_check, ref}, %{idle_ref: ref} = state) do
    if Enum.any?(state.players, fn {_id, p} -> Player.connected?(p) end) do
      {:noreply, %{state | idle_ref: nil}}
    else
      {:stop, :normal, state}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # --- Manches -------------------------------------------------------------------

  # Exécuté dans une tâche : choisit les candidats puis garde les 5 premiers jouables.
  defp build_round(music, players, pool, played) do
    {pool, new_hits} =
      if pool == [] do
        case music.hits() do
          {:ok, hits} -> {hits, hits}
          _ -> {[], []}
        end
      else
        {pool, []}
      end

    tracks =
      players
      |> Picker.candidates(pool, @candidates, played: played)
      |> Task.async_stream(&music.resolve/1,
        max_concurrency: 5,
        timeout: 10_000,
        on_timeout: :kill_task
      )
      |> Enum.flat_map(fn
        {:ok, {:ok, track}} -> [track]
        _ -> []
      end)
      |> Enum.take(Game.round_size())

    if length(tracks) == Game.round_size(),
      do: {:ok, tracks, new_hits},
      else: {:error, :not_enough_previews, new_hits}
  end

  defp task_done(state, :hits, {:ok, hits}) when is_list(hits), do: add_to_pool(state, hits)
  defp task_done(state, :hits, _error), do: state

  defp task_done(state, {:round, _previous}, {:ok, tracks, new_hits}) do
    round_id = state.round_id + 1
    game = Game.new(tracks)

    players =
      Map.new(state.players, fn {id, p} -> {id, %{p | round_points: 0}} end)

    %{
      state
      | status: :playing,
        game: game,
        round_id: round_id,
        found_by: %{},
        players: players,
        played: Enum.reduce(tracks, state.played, &MapSet.put(&2, Picker.key(&1)))
    }
    |> add_to_pool(new_hits)
    |> feed("▶ Manche #{round_id} : 5 pistes, #{Game.round_seconds()} secondes !")
    |> schedule_tick()
    |> broadcast()
  end

  defp task_done(state, {:round, previous}, error) do
    hits = if match?({:error, _, hits} when is_list(hits), error), do: elem(error, 2), else: []

    %{
      state
      | status: previous,
        error: "Pas assez d'extraits audio disponibles, relance la manche."
    }
    |> add_to_pool(hits)
    |> broadcast()
  end

  defp task_done(state, :expand, tracks) when is_list(tracks) do
    state |> add_to_pool(tracks) |> broadcast()
  end

  defp task_done(state, :expand, _error), do: state

  defp apply_hits(state, player_id, hits) do
    Enum.reduce(hits, state, fn {kind, track, points}, acc ->
      name = acc.players[player_id].name

      text =
        case kind do
          :title -> "🎯 #{name} a trouvé « #{track.title} » – #{track.artist} (+#{points})"
          :artist -> "🎤 #{name} a reconnu #{track.artist} (+#{points})"
        end

      acc
      |> Map.update!(:found_by, &Map.put(&1, track.id, {player_id, kind}))
      |> update_player(
        player_id,
        &%{&1 | score: &1.score + points, round_points: &1.round_points + points}
      )
      |> feed(text)
    end)
  end

  # Fin de manche : profils de goûts mis à jour pour tous, historique enregistré pour
  # les joueurs connectés à leur profil, et recherche élargie autour des artistes trouvés.
  defp finish_round(state) do
    game = Game.finish(state.game)
    now = DateTime.utc_now(:second)

    players =
      Map.new(state.players, fn {id, player} ->
        results = results_for(game, state.found_by, id)
        if player.user && Player.connected?(player), do: save_history(player, results)
        {id, %{player | taste: Taste.record(player.taste, results, now)}}
      end)

    %{state | game: game, status: :finished, players: players}
    |> feed(winner_text(players))
    |> expand_search()
  end

  defp results_for(game, found_by, player_id) do
    for track <- game.tracks do
      case Map.get(found_by, track.id) do
        {^player_id, kind} -> {track, kind}
        _ -> {track, :missed}
      end
    end
  end

  defp save_history(player, results) do
    History.record_results(Scope.for_user(player.user), @history_provider, results)
  rescue
    error ->
      Logger.error("Room : historique non enregistré pour #{player.id} : #{inspect(error)}")
  end

  defp winner_text(players) do
    case players |> Map.values() |> Enum.max_by(& &1.round_points, fn -> nil end) do
      %{round_points: points, name: name} when points > 0 ->
        "🏁 Manche terminée : #{name} la remporte (+#{points})"

      _ ->
        "🏁 Manche terminée : personne n'a marqué"
    end
  end

  defp expand_search(state) do
    artist_ids =
      for {track_id, _found} <- state.found_by,
          track = Enum.find(state.game.tracks, &(&1.id == track_id)),
          id = Map.get(track, :artist_id),
          is_binary(id),
          not MapSet.member?(state.expanded, id),
          uniq: true,
          do: id

    case Enum.take(artist_ids, @expand_per_round) do
      [] ->
        state

      ids ->
        music = state.music

        %{state | expanded: Enum.reduce(ids, state.expanded, &MapSet.put(&2, &1))}
        |> run_task(:expand, fn -> music.expand(ids) end)
    end
  end

  defp add_to_pool(state, tracks) do
    {pool, keys} =
      Enum.reduce(tracks, {state.pool, state.pool_keys}, fn track, {pool, keys} ->
        key = Picker.key(track)

        if MapSet.member?(keys, key) or length(pool) >= @pool_cap,
          do: {pool, keys},
          else: {[track | pool], MapSet.put(keys, key)}
      end)

    %{state | pool: pool, pool_keys: keys}
  end

  # --- Joueurs -------------------------------------------------------------------

  defp initial_taste(nil), do: Taste.empty()
  defp initial_taste(user), do: History.taste(Scope.for_user(user), @history_provider)

  defp put_likes(player, :loading), do: %{player | likes_status: :loading}
  defp put_likes(player, :error), do: %{player | likes_status: :error}
  defp put_likes(player, :none), do: %{player | likes_status: :none, likes: nil}

  defp put_likes(player, {:ready, likes, source}) do
    likes = Enum.map(likes, &Map.put(&1, :source, source))
    %{player | likes_status: :ready, likes: likes, likes_source: source}
  end

  defp likes_feed(state, player, {:ready, likes, _source}),
    do: feed(state, "🎵 #{player.name} a ajouté #{length(likes)} likes")

  defp likes_feed(state, _player, _status), do: state

  defp update_player(state, id, fun) do
    case Map.fetch(state.players, id) do
      {:ok, player} -> %{state | players: Map.put(state.players, id, fun.(player))}
      :error -> state
    end
  end

  # Si l'hôte est parti, le joueur connecté arrivé le plus tôt prend la main.
  defp elect_host(state) do
    host = state.players[state.host_id]

    if host && Player.connected?(host) do
      state
    else
      next =
        state.players
        |> Map.values()
        |> Enum.filter(&Player.connected?/1)
        |> Enum.min_by(& &1.joined_at, fn -> nil end)

      case next do
        nil -> state
        player when is_nil(state.host_id) -> %{state | host_id: player.id}
        player -> %{state | host_id: player.id} |> feed("👑 #{player.name} devient l'hôte")
      end
    end
  end

  defp refresh_common(state) do
    players = state.players |> Map.values() |> Enum.filter(&Player.connected?/1)
    %{state | common_count: Picker.common_count(players)}
  end

  # --- Outils --------------------------------------------------------------------

  defp run_task(state, kind, fun) do
    task = Task.Supervisor.async_nolink(BlindMix.TaskSupervisor, fun)
    %{state | tasks: Map.put(state.tasks, task.ref, kind)}
  end

  defp schedule_tick(state) do
    Process.send_after(self(), {:tick, state.round_id}, tick_ms())
    state
  end

  defp schedule_idle(state) do
    if Enum.any?(state.players, fn {_id, p} -> Player.connected?(p) end) do
      state
    else
      ref = make_ref()
      Process.send_after(self(), {:idle_check, ref}, idle_ms())
      %{state | idle_ref: ref}
    end
  end

  defp cancel_idle(state), do: %{state | idle_ref: nil}

  defp tick_ms, do: Application.get_env(:blind_mix, :room_tick_ms, 1000)
  defp idle_ms, do: Application.get_env(:blind_mix, :room_idle_ms, :timer.minutes(10))

  defp feed(state, text) do
    entry = %{id: state.seq, text: text}
    %{state | feed: Enum.take([entry | state.feed], @feed_size), seq: state.seq + 1}
  end

  defp broadcast(state) do
    Phoenix.PubSub.broadcast(BlindMix.PubSub, "room:" <> state.code, {:room, public(state)})
    state
  end

  # --- État public ---------------------------------------------------------------

  defp public(state) do
    names = Map.new(state.players, fn {id, p} -> {id, p.name} end)

    %{
      code: state.code,
      status: state.status,
      host_id: state.host_id,
      round_id: state.round_id,
      time_left: state.game && state.game.time_left,
      round_seconds: Game.round_seconds(),
      common_count: state.common_count,
      likes_players: Enum.count(state.players, fn {_id, p} -> p.likes_status == :ready end),
      error: state.error,
      feed: state.feed,
      players: public_players(state),
      slots: public_slots(state, names),
      audio: public_audio(state)
    }
  end

  defp public_players(state) do
    state.players
    |> Map.values()
    |> Enum.sort_by(&{-&1.score, &1.joined_at})
    |> Enum.map(fn p ->
      %{
        id: p.id,
        name: p.name,
        score: p.score,
        round_points: p.round_points,
        connected?: Player.connected?(p),
        ready?: p.ready?,
        host?: p.id == state.host_id,
        logged_in?: not is_nil(p.user),
        likes_status: p.likes_status,
        likes_count: if(p.likes, do: length(p.likes), else: 0),
        likes_source: p.likes_source
      }
    end)
  end

  defp public_slots(%{game: nil}, _names), do: []

  defp public_slots(%{game: game} = state, names) do
    game.tracks
    |> Enum.with_index(1)
    |> Enum.map(fn {track, index} ->
      {slot_state, finder} =
        case Map.get(state.found_by, track.id) do
          {player_id, kind} -> {kind, names[player_id]}
          nil -> {if(game.status == :finished, do: :missed, else: :playing), nil}
        end

      revealed? = slot_state != :playing
      owners = Map.get(track, :owners, [])

      %{
        id: track.id,
        index: index,
        state: slot_state,
        finder: finder,
        points: points(slot_state),
        title: if(revealed?, do: track.title),
        artist: if(revealed?, do: track.artist),
        origin: if(revealed?, do: Map.get(track, :origin)),
        owners:
          if(revealed?, do: owners |> Enum.map(&names[&1]) |> Enum.reject(&is_nil/1), else: [])
      }
    end)
  end

  defp public_audio(%{status: :playing, game: game, found_by: found_by}) do
    for track <- game.tracks, not Map.has_key?(found_by, track.id) do
      %{id: track.id, url: track.preview_url}
    end
  end

  defp public_audio(_state), do: []

  defp points(:title), do: Game.title_points()
  defp points(:artist), do: Game.artist_points()
  defp points(_), do: 0
end
