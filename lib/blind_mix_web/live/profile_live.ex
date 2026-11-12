defmodule BlindMixWeb.ProfileLive do
  @moduledoc "Profil du joueur : statistiques, goûts musicaux et historique des manches."
  use BlindMixWeb, :live_view

  alias BlindMix.History

  @page_size 10

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    stats = History.stats(scope)
    artists = History.top_artists(scope)

    {:ok,
     socket
     |> assign(
       page_title: "Mon profil",
       stats: stats,
       artists: artists,
       max_found: artists |> Enum.map(& &1.found) |> Enum.max(fn -> 1 end),
       now: DateTime.utc_now()
     )
     |> load_rounds(nil)}
  end

  @impl true
  def handle_event("more", _params, %{assigns: %{oldest_id: id}} = socket) when is_integer(id) do
    {:noreply, load_rounds(socket, id)}
  end

  def handle_event("more", _params, socket), do: {:noreply, socket}

  # Charge une page de manches. On en demande une de plus pour savoir s'il en reste.
  defp load_rounds(socket, before) do
    rounds =
      History.list_rounds(socket.assigns.current_scope, limit: @page_size + 1, before: before)

    {page, rest} = Enum.split(rounds, @page_size)

    socket
    |> stream(:rounds, page)
    |> assign(
      has_more?: rest != [],
      oldest_id: if(page == [], do: socket.assigns[:oldest_id], else: List.last(page).id)
    )
  end

  # --- Helpers d'affichage ---------------------------------------------------

  defp initial(email), do: email |> String.first() |> String.upcase()

  defp recognition(%{plays: 0}), do: "–"
  defp recognition(%{plays: plays, found: found}), do: "#{round(found * 100 / plays)} %"

  defp bar_pct(found, max_found), do: max(round(found * 100 / max_found), 4)

  defp found_label(%{found: found, played: played}) do
    "trouvé #{found} fois sur #{played}"
  end

  # Pas de base de fuseaux horaires : on affiche une durée relative, puis la date.
  defp ago(at, now) do
    minutes = DateTime.diff(now, at, :minute)

    cond do
      minutes < 1 -> "À l'instant"
      minutes < 60 -> "Il y a #{minutes} min"
      minutes < 24 * 60 -> "Il y a #{div(minutes, 60)} h"
      minutes < 7 * 24 * 60 -> "Il y a #{div(minutes, 24 * 60)} j"
      true -> date(at)
    end
  end

  @months ~w(janv. févr. mars avr. mai juin juil. août sept. oct. nov. déc.)
  defp date(at), do: "#{at.day} #{Enum.at(@months, at.month - 1)} #{at.year}"

  defp member_since(user), do: date(user.inserted_at)

  defp provider_label("deezer"), do: "Deezer"
  defp provider_label("spotify"), do: "Spotify"
  defp provider_label(_), do: "Démo"

  defp result_icon(:title), do: "🎯"
  defp result_icon(:artist), do: "🎤"
  defp result_icon(:missed), do: "✗"

  defp result_label(:title), do: "Titre trouvé"
  defp result_label(:artist), do: "Artiste trouvé"
  defp result_label(:missed), do: "Raté"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section class="bm-profile" id="profile-header">
        <div class="bm-avatar" aria-hidden="true">{initial(@current_scope.user.email)}</div>
        <div style="min-width:0">
          <h1 class="bm-title">Mon profil</h1>
          <p class="bm-profile-name">{@current_scope.user.email}</p>
          <p class="bm-muted">Membre depuis le {member_since(@current_scope.user)}</p>
        </div>
      </section>

      <section class="bm-tiles" id="profile-stats" aria-label="Statistiques">
        <div class="bm-tile" style="--t: var(--bm-yellow)" id="stat-rounds">
          <span class="bm-tile-num">{@stats.rounds}</span>
          <span class="bm-tile-label">Manches</span>
        </div>
        <div class="bm-tile" style="--t: var(--bm-pink)" id="stat-best">
          <span class="bm-tile-num">{@stats.best_score}</span>
          <span class="bm-tile-label">Meilleure manche</span>
        </div>
        <div class="bm-tile" style="--t: var(--bm-cyan)" id="stat-recognition">
          <span class="bm-tile-num">{recognition(@stats)}</span>
          <span class="bm-tile-label">Pistes reconnues</span>
        </div>
        <div class="bm-tile" style="--t: var(--bm-green)" id="stat-titles">
          <span class="bm-tile-num">{@stats.titles}</span>
          <span class="bm-tile-label">Titres trouvés</span>
        </div>
      </section>

      <section class="bm-card" id="profile-taste">
        <div>
          <h2 class="bm-h2">Tes goûts</h2>
          <p class="bm-muted">
            Les artistes que tu reconnais le mieux. Leurs titres reviennent plus souvent dans tes manches,
            ceux que tu viens de trouver se reposent quelques jours, et ceux que tu as ratés reviennent pour une revanche.
          </p>
        </div>

        <ul :if={@artists != []} class="bm-artists" id="taste-artists">
          <li :for={{a, i} <- Enum.with_index(@artists)} class="bm-artist" id={"taste-artist-#{i}"}>
            <span class="bm-artist-name">{a.artist}</span>
            <span class="bm-artist-count">{found_label(a)}</span>
            <span class="bm-artist-bar" aria-hidden="true">
              <i style={"width: #{bar_pct(a.found, @max_found)}%; animation-delay: #{i * 60}ms"}></i>
            </span>
          </li>
        </ul>

        <div :if={@artists == []} class="bm-empty" id="taste-empty">
          <span>Joue quelques manches : ton profil se construit au fil des artistes que tu reconnais.</span>
          <.link navigate={~p"/"} class="bm-btn bm-btn--sm">▶ Jouer</.link>
        </div>
      </section>

      <section class="bm-stack" id="profile-history">
        <h2 class="bm-h2">Historique</h2>

        <div id="rounds" phx-update="stream" class="bm-rounds">
          <div class="hidden only:block" id="rounds-empty">
            <div class="bm-empty">Aucune manche pour l'instant. Tes parties apparaîtront ici.</div>
          </div>

          <article :for={{dom_id, round} <- @streams.rounds} id={dom_id} class="bm-round">
            <header class="bm-round-head">
              <span class="bm-round-when">{ago(round.inserted_at, @now)}</span>
              <span class="bm-round-meta">
                <span class={["bm-badge", "bm-badge--#{round.provider}"]}>
                  {provider_label(round.provider)}
                </span>
                <span class="bm-round-score">+{round.score} pts</span>
                <span class="bm-muted">{round.found_count}/{round.track_count}</span>
              </span>
            </header>

            <ul class="bm-plays">
              <li :for={play <- round.plays} class={["bm-play", "bm-play--#{play.result}"]}>
                <span class="bm-play-dot" title={result_label(play.result)}>
                  {result_icon(play.result)}
                </span>
                <span class="bm-play-text">
                  <span class="bm-play-title" style="display:block">{play.title}</span>
                  <span class="bm-play-artist" style="display:block">{play.artist}</span>
                </span>
                <span class="bm-play-pts">
                  {if play.result == :missed, do: "Raté", else: "+#{play.points}"}
                </span>
              </li>
            </ul>
          </article>
        </div>

        <button
          :if={@has_more?}
          type="button"
          phx-click="more"
          class="bm-btn bm-btn--ghost bm-btn--block"
          id="rounds-more"
        >
          Voir les manches précédentes
        </button>
      </section>
    </Layouts.app>
    """
  end
end
