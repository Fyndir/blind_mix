defmodule BlindMixWeb.AdminLive do
  @moduledoc """
  Administration : statistiques, rooms ouvertes (fermeture possible) et comptes
  (recherche, suppression). Réservée aux comptes de `ADMIN_EMAILS` (voir `BlindMix.Admin`).
  La supervision technique est déléguée à Phoenix LiveDashboard (/admin/dashboard).
  """
  use BlindMixWeb, :live_view

  alias BlindMix.Admin
  alias BlindMixWeb.UserAuth

  @refresh_ms 5_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: :timer.send_interval(@refresh_ms, :refresh)

    {:ok,
     socket
     |> assign(
       page_title: "Administration",
       admin_emails: Admin.admin_emails(),
       search: "",
       search_form: to_form(%{"q" => ""})
     )
     |> load_stats()
     |> load_rooms()
     |> load_users()}
  end

  # --- Données -------------------------------------------------------------------

  defp load_stats(socket), do: assign(socket, stats: Admin.stats())

  defp load_rooms(socket) do
    rooms = Admin.list_rooms() |> Enum.map(&Map.put(&1, :id, &1.code))

    socket
    |> assign(rooms_count: length(rooms))
    |> stream(:rooms, rooms, reset: true)
  end

  defp load_users(socket) do
    users = Admin.list_users(socket.assigns.search)

    socket
    |> assign(users_count: length(users))
    |> stream(:users, users, reset: true)
  end

  # --- Événements ----------------------------------------------------------------

  @impl true
  def handle_event("search", %{"q" => q}, socket) do
    {:noreply,
     socket
     |> assign(search: q, search_form: to_form(%{"q" => q}))
     |> load_users()}
  end

  def handle_event("delete_user", %{"id" => id}, socket) do
    admin = socket.assigns.current_scope.user

    case Admin.delete_user(admin, String.to_integer(id)) do
      {:ok, tokens} ->
        # Coupe les pages ouvertes par ce compte (LiveView déconnectées).
        UserAuth.disconnect_sessions(tokens)

        {:noreply,
         socket
         |> put_flash(:info, "Compte supprimé.")
         |> load_stats()
         |> load_users()}

      {:error, :self} ->
        {:noreply, put_flash(socket, :error, "Tu ne peux pas supprimer ton propre compte ici.")}

      {:error, _reason} ->
        {:noreply, socket |> put_flash(:error, "Compte introuvable.") |> load_users()}
    end
  end

  def handle_event("close_room", %{"code" => code}, socket) do
    case Admin.close_room(socket.assigns.current_scope.user, code) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, "Room #{code} fermée.")
         |> stream_delete_by_dom_id(:rooms, "rooms-#{code}")
         |> update(:rooms_count, &max(&1 - 1, 0))}

      {:error, _reason} ->
        {:noreply, socket |> put_flash(:error, "Cette room n'existe plus.") |> load_rooms()}
    end
  end

  @impl true
  def handle_info(:refresh, socket), do: {:noreply, socket |> load_stats() |> load_rooms()}

  # --- Affichage -----------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section class="bm-admin-head" id="admin-header">
        <div>
          <h1 class="bm-title">Administration</h1>
          <p class="bm-muted">Mise à jour automatique toutes les 5 secondes.</p>
        </div>
        <.link href={~p"/admin/dashboard"} class="bm-btn bm-btn--sm" id="admin-dashboard-link">
          <.icon name="hero-chart-bar-mini" class="size-4" /> Supervision
        </.link>
      </section>

      <section class="bm-tiles" id="admin-stats" aria-label="Statistiques">
        <div class="bm-tile" style="--t: var(--bm-yellow)" id="admin-stat-users">
          <span class="bm-tile-num">{@stats.users}</span>
          <span class="bm-tile-label">Comptes · +{@stats.users_week} en 7 j</span>
        </div>
        <div class="bm-tile" style="--t: var(--bm-pink)" id="admin-stat-rounds">
          <span class="bm-tile-num">{@stats.rounds}</span>
          <span class="bm-tile-label">Manches · {@stats.rounds_day} en 24 h</span>
        </div>
        <div class="bm-tile" style="--t: var(--bm-cyan)" id="admin-stat-plays">
          <span class="bm-tile-num">{@stats.plays}</span>
          <span class="bm-tile-label">Pistes jouées</span>
        </div>
        <div class="bm-tile" style="--t: var(--bm-green)" id="admin-stat-rooms">
          <span class="bm-tile-num">{@stats.rooms}</span>
          <span class="bm-tile-label">Rooms ouvertes</span>
        </div>
      </section>

      <section class="bm-card" id="admin-rooms">
        <h2 class="bm-h2">Rooms ouvertes</h2>

        <ul id="rooms" phx-update="stream" class="bm-admin-list">
          <li class="hidden only:block bm-muted" id="rooms-empty">Aucune room ouverte.</li>
          <li :for={{dom_id, room} <- @streams.rooms} id={dom_id} class="bm-admin-row">
            <div class="bm-admin-main">
              <.link href={~p"/rooms/#{room.code}"} class="bm-code bm-admin-code">{room.code}</.link>
              <span class="bm-admin-meta">
                {room_status(room)} · {players_label(room)}
              </span>
            </div>
            <button
              type="button"
              class="bm-admin-danger"
              phx-click="close_room"
              phx-value-code={room.code}
              data-confirm={"Fermer la room #{room.code} ? Les joueurs seront renvoyés à l'accueil."}
              id={"close-room-#{room.code}"}
            >
              Fermer
            </button>
          </li>
        </ul>
      </section>

      <section class="bm-card" id="admin-users">
        <div class="bm-admin-head">
          <h2 class="bm-h2">Comptes</h2>
          <.form for={@search_form} id="admin-search" phx-change="search" phx-submit="search">
            <input
              type="search"
              name={@search_form[:q].name}
              value={@search_form[:q].value}
              placeholder="Rechercher un e-mail"
              class="bm-admin-search"
              phx-debounce="300"
              autocomplete="off"
              id="admin-search-q"
            />
          </.form>
        </div>

        <p class="bm-muted" id="admin-users-count">
          {users_label(@users_count, @search)}
        </p>

        <ul id="users" phx-update="stream" class="bm-admin-list">
          <li class="hidden only:block bm-muted" id="users-empty">Aucun compte.</li>
          <li :for={{dom_id, user} <- @streams.users} id={dom_id} class="bm-admin-row">
            <div class="bm-admin-main">
              <span class="bm-admin-email">
                {user.email}
                <span :if={user.email in @admin_emails} class="bm-chip bm-admin-chip">admin</span>
              </span>
              <span class="bm-admin-meta">
                n°{user.id} · inscrit le {date(user.inserted_at)} · {rounds_label(user)}
              </span>
            </div>
            <button
              :if={user.id != @current_scope.user.id}
              type="button"
              class="bm-admin-danger"
              phx-click="delete_user"
              phx-value-id={user.id}
              data-confirm={"Supprimer le compte #{user.email} et tout son historique ? C'est définitif."}
              id={"delete-user-#{user.id}"}
            >
              Supprimer
            </button>
          </li>
        </ul>
      </section>
    </Layouts.app>
    """
  end

  defp room_status(%{status: :lobby}), do: "salle d'attente"
  defp room_status(%{status: :preparing, round_id: n}), do: "préparation de la manche #{n + 1}"
  defp room_status(%{status: :playing, round_id: n}), do: "manche #{n} en cours"
  defp room_status(%{status: :finished, round_id: n}), do: "manche #{n} terminée"

  defp players_label(%{players: []}), do: "aucun joueur connecté"
  defp players_label(%{players: names}), do: Enum.join(names, ", ")

  defp users_label(count, search) do
    base = if count >= 50, do: "Les 50 derniers comptes", else: "#{count} compte(s)"
    if String.trim(search) == "", do: base, else: base <> " pour « #{search} »"
  end

  defp rounds_label(%{rounds: 0}), do: "aucune manche"

  defp rounds_label(%{rounds: n, last_round_at: last}),
    do: "#{n} manche(s), dernière le #{date(last)}"

  defp date(nil), do: "—"
  defp date(datetime), do: Calendar.strftime(datetime, "%d/%m/%Y")
end
