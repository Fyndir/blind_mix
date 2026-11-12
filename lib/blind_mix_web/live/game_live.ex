defmodule BlindMixWeb.GameLive do
  use BlindMixWeb, :live_view

  require Logger

  alias BlindMix.{Game, History, Providers, Taste}

  # On tire plus de candidats que nécessaire : certains n'ont pas d'extrait disponible.
  @candidates 12
  @colors ~w(#ff4d8d #ffd23f #2de2e6 #a66cff #ff8a3d)

  @impl true
  def mount(_params, %{"access_token" => token, "provider" => name}, socket) do
    case Providers.fetch(name) do
      {:ok, provider} -> {:ok, setup(socket, provider, name, token)}
      :error -> {:ok, redirect(socket, to: ~p"/")}
    end
  end

  def mount(_params, _session, socket), do: {:ok, redirect(socket, to: ~p"/")}

  defp setup(socket, provider, name, token) do
    socket =
      assign(socket,
        provider: provider,
        provider_name: name,
        taste: Taste.empty(),
        recorded_round: nil,
        token: token,
        dev_tools: dev_tools?(),
        likes: nil,
        game: nil,
        preparing: false,
        feedback: nil,
        fb_seq: 0,
        error: nil,
        round_id: 0,
        played: MapSet.new(),
        form: to_form(%{"guess" => ""})
      )

    if connected?(socket) do
      socket
      |> load_taste()
      |> start_async(:likes, fn -> provider.liked_tracks(token) end)
    else
      socket
    end
  end

  # --- Chargement des likes ------------------------------------------------

  @impl true
  def handle_async(:likes, {:ok, {:ok, likes}}, socket) do
    if length(likes) < Game.round_size() do
      {:noreply, assign(socket, error: "Il te faut au moins #{Game.round_size()} titres likés.")}
    else
      {:noreply, assign(socket, likes: likes)}
    end
  end

  def handle_async(:likes, failure, socket) do
    Logger.error("Chargement des titres impossible : #{inspect(failure, limit: 20)}")
    {:noreply, assign(socket, error: "Impossible de lire tes titres likés. Reconnecte-toi.")}
  end

  # --- Lancement d'une manche ----------------------------------------------

  def handle_async(:round, {:ok, {:ok, tracks}}, socket) do
    round_id = socket.assigns.round_id + 1
    previous_score = if socket.assigns.game, do: socket.assigns.game.score, else: 0
    Process.send_after(self(), {:tick, round_id}, 1000)

    {:noreply,
     socket
     |> assign(
       game: Game.new(tracks, previous_score),
       round_id: round_id,
       preparing: false,
       feedback: nil,
       played: MapSet.union(socket.assigns.played, MapSet.new(tracks, & &1.id)),
       form: to_form(%{"guess" => ""})
     )
     # Seuls l'id et l'URL partent au navigateur : titre et artiste restent côté serveur.
     |> push_event("mix:start", %{tracks: Enum.map(tracks, &%{id: &1.id, url: &1.preview_url})})}
  end

  def handle_async(:round, _failure, socket) do
    {:noreply,
     assign(socket,
       preparing: false,
       error: "Pas assez d'extraits audio disponibles, relance une manche."
     )}
  end

  # --- Événements -----------------------------------------------------------

  @impl true
  def handle_event("start", _params, %{assigns: %{likes: likes, preparing: false}} = socket)
      when is_list(likes) do
    %{provider: provider, token: token, played: played, taste: taste} = socket.assigns

    {:noreply,
     socket
     |> assign(preparing: true, feedback: nil, error: nil)
     |> start_async(:round, fn -> build_round(provider, token, likes, played, taste) end)}
  end

  def handle_event("start", _params, socket), do: {:noreply, socket}

  def handle_event(
        "guess",
        %{"guess" => text},
        %{assigns: %{game: %Game{status: :playing} = game}} = socket
      ) do
    if String.trim(text) == "" do
      {:noreply, socket}
    else
      {game, hits} = Game.guess(game, text)
      {:noreply, apply_result(socket, game, hits, feedback(hits, text))}
    end
  end

  def handle_event("guess", _params, socket), do: {:noreply, socket}

  # Outils de développement : revérifiés côté serveur, un événement forgé ne passe pas en production.
  def handle_event(
        "finish",
        _params,
        %{assigns: %{dev_tools: true, game: %Game{status: :playing} = game}} = socket
      ) do
    {:noreply,
     socket
     |> assign(game: Game.finish(game), feedback: nil)
     |> push_event("mix:stop_all", %{})
     |> push_event("fx:end", %{})
     |> record_round()}
  end

  def handle_event(
        "dev_found",
        %{"id" => id, "kind" => kind},
        %{assigns: %{dev_tools: true, game: %Game{status: :playing} = game}} = socket
      )
      when kind in ["title", "artist"] do
    {game, hits} = Game.force(game, id, String.to_existing_atom(kind))
    {:noreply, apply_result(socket, game, hits, feedback(hits, nil))}
  end

  def handle_event(event, _params, socket) when event in ["finish", "dev_found"],
    do: {:noreply, socket}

  # --- Chrono ---------------------------------------------------------------

  @impl true
  def handle_info(
        {:tick, round_id},
        %{assigns: %{round_id: round_id, game: %Game{status: :playing} = game}} = socket
      ) do
    game = Game.tick(game)

    if game.status == :playing do
      Process.send_after(self(), {:tick, round_id}, 1000)
      {:noreply, assign(socket, game: game)}
    else
      {:noreply,
       socket
       |> assign(game: game)
       |> push_event("mix:stop_all", %{})
       |> push_event("fx:end", %{})
       |> record_round()}
    end
  end

  # Tick d'une manche déjà terminée ou remplacée : on l'ignore.
  def handle_info(_msg, socket), do: {:noreply, socket}

  # --- Helpers --------------------------------------------------------------

  # Applique le résultat d'une saisie (ou d'un outil dev) : état, sons, confettis, fin de manche.
  defp apply_result(socket, game, hits, feedback) do
    socket =
      Enum.reduce(hits, socket, fn {kind, track, _points}, acc ->
        acc
        |> push_event("mix:stop", %{id: track.id})
        |> push_event("fx:found", %{id: track.id, kind: Atom.to_string(kind)})
      end)

    socket = if hits == [], do: push_event(socket, "fx:miss", %{}), else: socket

    socket =
      if game.status == :finished do
        socket |> push_event("mix:stop_all", %{}) |> push_event("fx:end", %{})
      else
        socket
      end

    socket
    |> assign(
      game: game,
      feedback: feedback,
      fb_seq: socket.assigns.fb_seq + 1,
      form: to_form(%{"guess" => ""})
    )
    |> record_round()
  end

  # --- Profil ---------------------------------------------------------------

  defp user_scope(%{assigns: %{current_scope: %{user: %{}} = scope}}), do: scope
  defp user_scope(_socket), do: nil

  defp logged_in?(%{user: %{}}), do: true
  defp logged_in?(_scope), do: false

  defp load_taste(socket) do
    case user_scope(socket) do
      nil -> socket
      scope -> assign(socket, taste: History.taste(scope, socket.assigns.provider_name))
    end
  end

  # Enregistre une seule fois chaque manche terminée (joueurs connectés seulement),
  # puis recharge le profil pour que la manche suivante en tienne compte.
  defp record_round(%{assigns: %{game: %Game{status: :finished}, round_id: id}} = socket)
       when socket.assigns.recorded_round != id do
    socket = assign(socket, recorded_round: id)

    with %{} = scope <- user_scope(socket),
         {:ok, _round} <-
           History.record_round(scope, socket.assigns.provider_name, socket.assigns.game) do
      load_taste(socket)
    else
      nil ->
        socket

      {:error, reason} ->
        Logger.error("Enregistrement de la manche impossible : #{inspect(reason)}")
        socket
    end
  end

  defp record_round(socket), do: socket

  # Actif en développement (`dev_routes` de dev.exs) ou avec DEV_TOOLS=true (ex. Docker en local).
  defp dev_tools? do
    Application.get_env(:blind_mix, :dev_routes, false) == true or
      System.get_env("DEV_TOOLS") == "true"
  end

  # Les titres sont tirés selon le profil de goûts (voir `BlindMix.Taste`), du plus
  # prioritaire au moins prioritaire : ceux sans extrait sont remplacés par les suivants.
  defp build_round(provider, token, likes, played, taste) do
    fresh = Enum.reject(likes, &MapSet.member?(played, &1.id))
    pool = if length(fresh) >= @candidates, do: fresh, else: likes

    tracks =
      pool
      |> Taste.pick(@candidates, taste)
      |> Task.async_stream(&provider.refresh_preview(token, &1),
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
      do: {:ok, tracks},
      else: {:error, :not_enough_previews}
  end

  defp feedback([], text) when text in [nil, ""], do: nil
  defp feedback([], text), do: "Raté : « #{text} »"

  defp feedback(hits, _text) do
    hits
    |> Enum.map(fn
      {:title, t, pts} -> "🎯 #{t.title} – #{t.artist} (+#{pts})"
      {:artist, t, pts} -> "🎤 Artiste trouvé : #{t.artist} (+#{pts})"
    end)
    |> Enum.join(" · ")
  end

  defp slots(game) do
    game.tracks
    |> Enum.with_index(1)
    |> Enum.map(fn {track, i} -> %{track: track, i: i, state: slot_state(game, track)} end)
  end

  defp slot_state(game, track) do
    case Map.get(game.found, track.id) do
      nil -> if game.status == :finished, do: :missed, else: :playing
      kind -> kind
    end
  end

  defp color(i), do: Enum.at(@colors, rem(i - 1, length(@colors)))

  defp points(:title), do: Game.title_points()
  defp points(:artist), do: Game.artist_points()

  defp slot_label(:title), do: "🎯 Titre"
  defp slot_label(:artist), do: "🎤 Artiste"

  defp time_pct(game), do: div(game.time_left * 100, Game.round_seconds())

  # --- Rendu ----------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="mixer" phx-hook="AudioMix" class="bm-stack">
        <header class="bm-head">
          <h1 class="bm-title">Blind test multi-pistes</h1>
          <.link href={~p"/auth/logout"} method="delete" class="bm-link" id="switch-provider">
            Changer de service
          </.link>
        </header>

        <p :if={@error} class="bm-error">{@error}</p>

        <p :if={is_nil(@likes) and is_nil(@error)} class="bm-lead">Chargement de tes titres likés…</p>

        <div :if={@likes && is_nil(@game)} class="bm-card">
          <p class="bm-lead">
            5 titres vont se jouer <strong>en même temps</strong>. Tape un artiste
            ({Game.artist_points()} pts) ou un titre ({Game.title_points()} pts)
            pour retirer une piste du mix. Tu as {Game.round_seconds()} secondes !
          </p>
          <p :if={not logged_in?(@current_scope)} class="bm-muted" id="guest-hint">
            Tu joues en invité.
            <.link navigate={~p"/users/register"} class="bm-link">Crée ton profil</.link>
            pour garder tes manches et des titres choisis selon tes goûts.
          </p>
          <button phx-click="start" data-unlock disabled={@preparing} class="bm-btn" id="start-round">
            {if @preparing, do: "Préparation…", else: "▶ Lancer la manche"}
          </button>
        </div>

        <div :if={@game} class="bm-stack" style="gap:1.1rem">
          <div class="bm-hud">
            <span class="bm-score">
              Score <span id={"score-#{@game.score}"} class="bm-score-num">{@game.score}</span>
            </span>
            <span
              :if={@game.status == :playing}
              class={["bm-timer", @game.time_left <= 15 && "bm-timer--low"]}
            >
              ⏱ {@game.time_left} s
            </span>
          </div>

          <div :if={@game.status == :playing} class="bm-bar">
            <div
              class={["bm-bar-fill", @game.time_left <= 15 && "bm-bar-fill--low"]}
              style={"width: #{time_pct(@game)}%"}
            >
            </div>
          </div>

          <div :if={@game.status == :finished} class="bm-banner">
            🏁 Manche terminée : {map_size(@game.found)}/{length(@game.tracks)} pistes trouvées
          </div>

          <p
            :if={
              @game.status == :finished and @recorded_round == @round_id and
                logged_in?(@current_scope)
            }
            class="bm-note"
            id="round-saved"
          >
            <.icon name="hero-check-circle-mini" class="size-5 shrink-0" />
            <span>
              Manche enregistrée : la prochaine tiendra compte de tes goûts.
              <.link navigate={~p"/profile"} class="bm-link">Voir mon profil</.link>
            </span>
          </p>

          <div class="bm-slots">
            <div
              :for={s <- slots(@game)}
              id={"slot-#{s.track.id}"}
              class={["bm-slot", "bm-slot--#{s.state}"]}
              style={"--c: #{color(s.i)}"}
            >
              <span class="bm-num">{s.i}</span>

              <div class="bm-body">
                <%= if s.state == :playing do %>
                  <div class="bm-mystery">Piste mystère</div>
                  <div class="bm-sub">Artiste ? Titre ?</div>
                <% else %>
                  <div class="bm-name">{s.track.title}</div>
                  <div class="bm-sub">{s.track.artist}</div>
                <% end %>
              </div>

              <div :if={s.state == :playing} class="bm-eq" aria-hidden="true">
                <i></i><i></i><i></i><i></i><i></i>
              </div>
              <span :if={s.state in [:title, :artist]} class="bm-chip">
                {slot_label(s.state)} +{points(s.state)}
              </span>
              <span :if={s.state in [:title, :artist]} class="bm-float" aria-hidden="true">
                +{points(s.state)}
              </span>
              <span :if={s.state == :missed} class="bm-chip bm-chip--miss">Raté</span>

              <div :if={@dev_tools and s.state == :playing} class="bm-dev">
                <button
                  type="button"
                  phx-click="dev_found"
                  phx-value-id={s.track.id}
                  phx-value-kind="artist"
                >
                  🛠 Artiste trouvé
                </button>
                <button
                  type="button"
                  phx-click="dev_found"
                  phx-value-id={s.track.id}
                  phx-value-kind="title"
                >
                  🛠 Titre trouvé
                </button>
              </div>
            </div>
          </div>

          <.form
            :if={@game.status == :playing}
            for={@form}
            id="guess-form"
            phx-submit="guess"
            class="bm-form"
          >
            <input
              type="text"
              name="guess"
              value={@form[:guess].value}
              autocomplete="off"
              autofocus
              placeholder="Artiste ou titre…"
              class="bm-input"
            />
            <button class="bm-btn">OK</button>
          </.form>

          <p :if={@feedback} id={"fb-#{@fb_seq}"} class="bm-feedback">{@feedback}</p>

          <div :if={@dev_tools and @game.status == :playing}>
            <button type="button" phx-click="finish" class="bm-devbtn">🛠 Terminer la manche (dev)</button>
          </div>

          <button
            :if={@game.status == :finished}
            phx-click="start"
            data-unlock
            disabled={@preparing}
            class="bm-btn"
          >
            {if @preparing, do: "Préparation…", else: "▶ Manche suivante"}
          </button>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
