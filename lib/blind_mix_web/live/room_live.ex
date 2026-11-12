defmodule BlindMixWeb.RoomLive do
  @moduledoc """
  Une room multijoueur vue par un joueur.

  L'état de la room vient du processus `BlindMix.Rooms.Server` (PubSub) ; cette vue
  le compare à l'état précédent pour déclencher le son et les effets : début de
  manche, piste trouvée par quelqu'un, fin de manche.
  """
  use BlindMixWeb, :live_view

  require Logger

  alias BlindMix.{Game, Providers, Rooms}

  @colors ~w(#ff4d8d #ffd23f #2de2e6 #a66cff #ff8a3d #5cff9d)

  @impl true
  def mount(%{"code" => raw_code}, session, socket) do
    code = Rooms.normalize_code(raw_code)
    identity = identity(socket.assigns.current_scope, session)

    cond do
      is_nil(code) or not Rooms.exists?(code) ->
        {:ok,
         socket
         |> put_flash(:error, "Cette room n'existe pas (ou plus).")
         |> redirect(to: ~p"/")}

      is_nil(identity) ->
        {:ok, redirect(socket, to: ~p"/rooms/#{code}/join")}

      true ->
        {:ok, setup(socket, code, identity, session)}
    end
  end

  defp setup(socket, code, identity, session) do
    socket =
      assign(socket,
        page_title: "Room #{code}",
        code: code,
        me: identity.id,
        room: nil,
        me_player: nil,
        feedback: nil,
        fb_seq: 0,
        share_url: url(~p"/rooms/#{code}"),
        dev_tools: BlindMix.DevTools.enabled?(),
        spotify?: Providers.available?("spotify"),
        deezer?: Providers.available?("deezer"),
        form: to_form(%{"guess" => ""})
      )

    if connected?(socket) do
      Rooms.subscribe(code)

      case Rooms.join(code, identity) do
        {:ok, room} ->
          socket
          |> apply_room(room)
          |> maybe_load_likes(room, session)

        {:error, _} ->
          socket |> put_flash(:error, "Cette room vient de fermer.") |> redirect(to: ~p"/")
      end
    else
      socket
    end
  end

  # Joueur connecté à son profil : identité stable (« u-<id> »), pseudo de session ou
  # début de l'e-mail. Anonyme : identité et pseudo choisis sur /rooms/:code/join.
  defp identity(%{user: %{} = user}, session) do
    name =
      session["player_name"] || user.email |> String.split("@") |> hd() |> String.slice(0, 24)

    %{id: "u-#{user.id}", name: name, user: user}
  end

  defp identity(_scope, %{"player_id" => id, "player_name" => name})
       when is_binary(id) and is_binary(name),
       do: %{id: id, name: name, user: nil}

  defp identity(_scope, _session), do: nil

  # Likes du service musical connecté (Deezer, Spotify), chargés une fois par room.
  defp maybe_load_likes(socket, room, session) do
    name = session["provider"]
    me = find_me(room, socket.assigns.me)

    # Le mode démo n'a pas de likes personnels : ses titres sont déjà les tubes de la room.
    with true <- is_binary(name) and name != "demo",
         {:ok, provider} <- Providers.fetch_available(name),
         true <- me && me.likes_status in [:none, :error],
         token when is_binary(token) <- session["access_token"] do
      Rooms.set_likes(socket.assigns.code, socket.assigns.me, :loading)
      start_async(socket, :likes, fn -> {name, provider.liked_tracks(token)} end)
    else
      _ -> socket
    end
  end

  @impl true
  def handle_async(:likes, {:ok, {name, {:ok, likes}}}, socket) do
    Rooms.set_likes(socket.assigns.code, socket.assigns.me, {:ready, likes, name})
    {:noreply, socket}
  end

  def handle_async(:likes, failure, socket) do
    Logger.error(
      "[room #{socket.assigns.code}] likes impossibles à charger : #{inspect(failure, limit: 20)}"
    )

    Rooms.set_likes(socket.assigns.code, socket.assigns.me, :error)
    {:noreply, socket}
  end

  # --- État de la room -------------------------------------------------------------

  @impl true
  def handle_info({:room, room}, socket), do: {:noreply, apply_room(socket, room)}

  # Room fermée depuis l'administration.
  def handle_info({:room_closed, _code}, socket) do
    {:noreply,
     socket
     |> push_event("mix:stop_all", %{})
     |> put_flash(:error, "Cette room a été fermée.")
     |> push_navigate(to: ~p"/")}
  end

  # Compare l'ancien et le nouvel état pour piloter le son et les effets.
  defp apply_room(socket, new) do
    old = socket.assigns.room

    socket
    |> maybe_start_mix(old, new)
    |> push_found(old, new)
    |> maybe_end(old, new)
    |> assign(room: new, me_player: find_me(new, socket.assigns.me))
  end

  defp maybe_start_mix(socket, old, %{status: :playing} = new) do
    if is_nil(old) or old.status != :playing or old.round_id != new.round_id do
      socket
      |> assign(feedback: nil, form: to_form(%{"guess" => ""}))
      |> push_event("mix:start", %{tracks: new.audio})
    else
      socket
    end
  end

  defp maybe_start_mix(socket, _old, _new), do: socket

  defp push_found(socket, %{round_id: round_id, slots: old_slots}, %{round_id: round_id} = new) do
    before = Map.new(old_slots, &{&1.id, &1.state})

    Enum.reduce(new.slots, socket, fn slot, acc ->
      if before[slot.id] == :playing and slot.state in [:title, :artist] do
        acc
        |> push_event("mix:stop", %{id: slot.id})
        |> push_event("fx:found", %{id: slot.id, kind: Atom.to_string(slot.state)})
      else
        acc
      end
    end)
  end

  defp push_found(socket, _old, _new), do: socket

  defp maybe_end(socket, %{status: :playing}, %{status: :finished}) do
    socket |> push_event("mix:stop_all", %{}) |> push_event("fx:end", %{})
  end

  defp maybe_end(socket, _old, _new), do: socket

  # --- Actions des joueurs ------------------------------------------------------------

  @impl true
  def handle_event("guess", %{"guess" => text}, socket) do
    text = String.trim(text)

    if text == "" do
      {:noreply, socket}
    else
      socket =
        case Rooms.guess(socket.assigns.code, socket.assigns.me, text) do
          {:ok, []} ->
            socket
            |> assign(feedback: "Raté : « #{text} »")
            |> push_event("fx:miss", %{})

          {:ok, hits} ->
            assign(socket, feedback: hits_text(hits))

          {:error, _} ->
            socket
        end

      {:noreply,
       assign(socket, fb_seq: socket.assigns.fb_seq + 1, form: to_form(%{"guess" => ""}))}
    end
  end

  def handle_event("ready", _params, socket) do
    me = find_me(socket.assigns.room, socket.assigns.me)
    Rooms.set_ready(socket.assigns.code, socket.assigns.me, not (me && me.ready?))
    {:noreply, socket}
  end

  # Activer le son pendant une manche : le clic (data-unlock) suffit côté navigateur.
  def handle_event("unmute", _params, socket) do
    Rooms.set_ready(socket.assigns.code, socket.assigns.me, true)
    {:noreply, socket}
  end

  # Outils de développement (revérifiés par le processus de la room).
  def handle_event(
        "dev_found",
        %{"id" => id, "kind" => kind},
        %{assigns: %{dev_tools: true}} = socket
      )
      when kind in ["title", "artist"] do
    Rooms.dev_found(socket.assigns.code, socket.assigns.me, id, String.to_existing_atom(kind))
    {:noreply, socket}
  end

  def handle_event("dev_finish", _params, %{assigns: %{dev_tools: true}} = socket) do
    Rooms.dev_finish(socket.assigns.code)
    {:noreply, socket}
  end

  def handle_event(event, _params, socket) when event in ["dev_found", "dev_finish"],
    do: {:noreply, socket}

  def handle_event("start", _params, socket) do
    Rooms.start_round(socket.assigns.code, socket.assigns.me)
    {:noreply, socket}
  end

  # --- Affichage ---------------------------------------------------------------------

  defp find_me(nil, _id), do: nil
  defp find_me(room, id), do: Enum.find(room.players, &(&1.id == id))

  defp host_name(room), do: Enum.find_value(room.players, &(&1.host? && &1.name))

  defp hits_text(hits) do
    hits
    |> Enum.map(fn
      {:title, t, pts} -> "🎯 Bien joué : #{t.title} – #{t.artist} (+#{pts})"
      {:artist, t, pts} -> "🎤 Artiste trouvé : #{t.artist} (+#{pts})"
    end)
    |> Enum.join(" · ")
  end

  defp mode_text(%{common_count: n}) when n > 0,
    do:
      "💞 #{n} morceau#{if n > 1, do: "x"} en commun entre vous : ils passent en priorité, puis vos likes et les tubes."

  defp mode_text(%{likes_players: n}) when n > 0,
    do:
      "🎵 Pas encore de morceau en commun : vos likes passent à tour de rôle, puis les tubes du moment."

  defp mode_text(_room),
    do:
      "🔥 Tubes du moment : la sélection s'affine au fil des manches selon ce que la room reconnaît."

  defp likes_text(%{likes_status: :ready, likes_count: n, likes_source: source}),
    do: "🎵 #{n} likes #{source_label(source)}"

  defp likes_text(%{likes_status: :loading}), do: "⏳ likes…"
  defp likes_text(%{logged_in?: true}), do: "profil"
  defp likes_text(_player), do: "anonyme"

  defp source_label("spotify"), do: "Spotify"
  defp source_label("deezer"), do: "Deezer"
  defp source_label(_), do: ""

  defp color(id), do: Enum.at(@colors, :erlang.phash2(id, length(@colors)))
  defp slot_color(index), do: Enum.at(@colors, rem(index - 1, length(@colors)))
  defp initial(name), do: name |> String.first() |> to_string() |> String.upcase()

  defp time_pct(room), do: div((room.time_left || 0) * 100, room.round_seconds)

  defp ready_count(room), do: Enum.count(room.players, &(&1.connected? and &1.ready?))
  defp connected_count(room), do: Enum.count(room.players, & &1.connected?)

  defp round_ranking(room) do
    room.players
    |> Enum.filter(&(&1.round_points > 0))
    |> Enum.sort_by(& &1.round_points, :desc)
  end

  defp origin_label(%{origin: :common, owners: owners}),
    do: "💞 en commun : #{Enum.join(owners, ", ")}"

  defp origin_label(%{origin: :likes, owners: [owner | _]}), do: "🎵 liké par #{owner}"
  defp origin_label(%{origin: :hits}), do: "🔥 tube"
  defp origin_label(_slot), do: nil

  defp slot_label(:title), do: "🎯"
  defp slot_label(:artist), do: "🎤"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="room" phx-hook="AudioMix" class="bm-stack">
        <header class="bm-room-head">
          <div>
            <p class="bm-kicker">Room multijoueur</p>
            <h1 class="bm-title bm-code" id="room-code">{@code}</h1>
          </div>
          <button
            type="button"
            id="copy-link"
            class="bm-pill"
            phx-hook=".CopyLink"
            phx-update="ignore"
            data-url={@share_url}
          >
            🔗 Copier le lien
          </button>
        </header>

        <p :if={is_nil(@room)} class="bm-lead" id="room-connecting">Connexion à la room…</p>

        <%= if @room do %>
          <p class="bm-note" id="room-mode">
            <span>{mode_text(@room)}</span>
          </p>

          <section class="bm-players" id="room-players" aria-label="Joueurs">
            <div
              :for={p <- @room.players}
              id={"player-#{p.id}"}
              class={[
                "bm-player",
                !p.connected? && "bm-player--away",
                p.id == @me && "bm-player--me"
              ]}
            >
              <span class="bm-player-avatar" style={"--c: #{color(p.id)}"}>{initial(p.name)}</span>
              <span class="bm-player-text">
                <span class="bm-player-name">
                  {p.name}<span :if={p.id == @me} class="bm-player-you"> (toi)</span>
                  <span :if={p.host?} title="Hôte de la room">👑</span>
                </span>
                <span class="bm-player-meta">
                  {likes_text(p)}<span :if={p.ready?}> · 🔊 prêt</span><span :if={!p.connected?}> · parti</span>
                </span>
              </span>
              <span class="bm-player-score">
                <span
                  :if={@room.status in [:playing, :finished] and p.round_points > 0}
                  class="bm-player-delta"
                >
                  +{p.round_points}
                </span>
                {p.score}
              </span>
            </div>
          </section>

          <div
            :if={
              (@me_player && @me_player.likes_status in [:none, :error]) and (@spotify? or @deezer?) and
                @room.status != :playing
            }
            class="bm-card"
            id="room-add-likes"
          >
            <p class="bm-muted">
              {if @me_player.likes_status == :error,
                do: "Tes likes n'ont pas pu être chargés. Reconnecte ton service :",
                else: "Ajoute tes likes pour jouer vos morceaux en commun :"}
            </p>
            <div class="bm-row" style="justify-content:flex-start">
              <a
                :if={@spotify?}
                href={~p"/auth/spotify?#{[return_to: "/rooms/#{@code}"]}"}
                class="bm-btn bm-btn--spotify bm-btn--sm"
              >
                Spotify
              </a>
              <a
                :if={@deezer?}
                href={~p"/auth/deezer?#{[return_to: "/rooms/#{@code}"]}"}
                class="bm-btn bm-btn--deezer bm-btn--sm"
              >
                Deezer
              </a>
            </div>
          </div>

          <p :if={@room.error} class="bm-error" id="room-error">{@room.error}</p>

          <%!-- Entre deux manches --%>
          <div :if={@room.status in [:lobby, :preparing]} class="bm-card" id="room-lobby">
            <p class="bm-lead">
              5 pistes jouent en même temps chez tout le monde. <strong>Le premier</strong>
              qui tape l'artiste ({Game.artist_points()} pts) ou le titre ({Game.title_points()} pts)
              marque les points et retire la piste du mix pour tous !
            </p>
            <.ready_button me={@me_player} />
            <.start_controls room={@room} me={@me} />
          </div>

          <%!-- Manche en cours ou terminée --%>
          <div :if={@room.status in [:playing, :finished]} class="bm-stack" style="gap:1.1rem">
            <div :if={@room.status == :playing} class="bm-hud">
              <span class="bm-score">Manche {@room.round_id}</span>
              <span class={["bm-timer", @room.time_left <= 15 && "bm-timer--low"]}>
                ⏱ {@room.time_left} s
              </span>
            </div>

            <div :if={@room.status == :playing} class="bm-bar">
              <div
                class={["bm-bar-fill", @room.time_left <= 15 && "bm-bar-fill--low"]}
                style={"width: #{time_pct(@room)}%"}
              >
              </div>
            </div>

            <button
              :if={(@room.status == :playing and @me_player) && !@me_player.ready?}
              type="button"
              phx-click="unmute"
              data-unlock
              class="bm-btn bm-btn--ghost bm-btn--block"
              id="room-unmute"
            >
              🔇 Pas de son ? Clique ici pour l'activer
            </button>

            <div :if={@room.status == :finished} class="bm-banner" id="room-round-end">
              🏁 Manche {@room.round_id} terminée
              <span :for={{p, i} <- Enum.with_index(round_ranking(@room))} class="bm-rank">
                {if i == 0, do: "🥇", else: "·"} {p.name} +{p.round_points}
              </span>
            </div>

            <div class="bm-slots" id="room-slots">
              <div
                :for={s <- @room.slots}
                id={"slot-#{s.id}"}
                class={["bm-slot", "bm-slot--#{s.state}"]}
                style={"--c: #{slot_color(s.index)}"}
              >
                <span class="bm-num">{s.index}</span>
                <div class="bm-body">
                  <%= if s.state == :playing do %>
                    <div class="bm-mystery">Piste mystère</div>
                    <div class="bm-sub">Artiste ? Titre ?</div>
                  <% else %>
                    <div class="bm-name">{s.title}</div>
                    <div class="bm-sub">{s.artist}</div>
                    <div :if={origin_label(s)} class="bm-origin">{origin_label(s)}</div>
                  <% end %>
                </div>
                <div :if={s.state == :playing} class="bm-eq" aria-hidden="true">
                  <i></i><i></i><i></i><i></i><i></i>
                </div>
                <span :if={s.state in [:title, :artist]} class="bm-chip">
                  {slot_label(s.state)} {s.finder} +{s.points}
                </span>
                <span :if={s.state == :missed} class="bm-chip bm-chip--miss">Personne</span>

                <div :if={@dev_tools and s.state == :playing} class="bm-dev">
                  <button
                    type="button"
                    phx-click="dev_found"
                    phx-value-id={s.id}
                    phx-value-kind="artist"
                    id={"dev-artist-#{s.id}"}
                  >
                    🛠 Artiste trouvé
                  </button>
                  <button
                    type="button"
                    phx-click="dev_found"
                    phx-value-id={s.id}
                    phx-value-kind="title"
                    id={"dev-title-#{s.id}"}
                  >
                    🛠 Titre trouvé
                  </button>
                </div>
              </div>
            </div>

            <.form
              :if={@room.status == :playing}
              for={@form}
              id="room-guess-form"
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

            <div :if={@dev_tools and @room.status == :playing}>
              <button type="button" phx-click="dev_finish" class="bm-devbtn" id="dev-finish">
                🛠 Terminer la manche (dev)
              </button>
            </div>

            <div :if={@room.status == :finished} class="bm-stack" style="gap:.8rem">
              <.ready_button me={@me_player} />
              <.start_controls room={@room} me={@me} next />
            </div>
          </div>

          <section class="bm-card" id="room-feed" aria-label="Fil de la partie">
            <h2 class="bm-h2">Fil de la partie</h2>
            <ul class="bm-feed">
              <li :for={e <- @room.feed} id={"feed-#{e.id}"}>{e.text}</li>
            </ul>
          </section>
        <% end %>
      </div>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".CopyLink">
        export default {
          mounted() {
            const label = this.el.textContent.trim();
            this.el.addEventListener("click", async () => {
              const url = this.el.dataset.url;
              try {
                await navigator.clipboard.writeText(url);
                this.el.textContent = "✓ Lien copié !";
              } catch (_) {
                window.prompt("Copie ce lien et envoie-le à tes amis :", url);
              }
              setTimeout(() => (this.el.textContent = label), 2000);
            });
          }
        }
      </script>
    </Layouts.app>
    """
  end

  attr :me, :map, default: nil

  defp ready_button(assigns) do
    ~H"""
    <button
      :if={@me}
      type="button"
      phx-click="ready"
      data-unlock
      id="room-ready"
      class={["bm-btn bm-btn--block", if(@me.ready?, do: "bm-btn--ghost", else: "bm-btn--spotify")]}
    >
      {if @me.ready?, do: "✓ Prêt, son activé (cliquer pour annuler)", else: "🔊 Je suis prêt"}
    </button>
    """
  end

  attr :room, :map, required: true
  attr :me, :string, required: true
  attr :next, :boolean, default: false

  defp start_controls(assigns) do
    ~H"""
    <%= cond do %>
      <% @room.status == :preparing -> %>
        <p class="bm-muted bm-center" id="room-preparing">⏳ Préparation de la manche…</p>
      <% @room.host_id == @me -> %>
        <button phx-click="start" data-unlock class="bm-btn bm-btn--block" id="start-round">
          {if @next, do: "▶ Manche suivante", else: "▶ Lancer la manche"}
        </button>
        <p class="bm-muted bm-center">
          {ready_count(@room)}/{connected_count(@room)} joueur(s) prêt(s). Envoie le lien de la room à tes amis !
        </p>
      <% true -> %>
        <p class="bm-muted bm-center" id="room-waiting">
          ⏳ En attente de {host_name(@room)} pour lancer la manche.
        </p>
    <% end %>
    """
  end
end
