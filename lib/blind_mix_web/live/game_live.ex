defmodule BlindMixWeb.GameLive do
  use BlindMixWeb, :live_view

  alias BlindMix.{Game, Providers}

  # On tire plus de candidats que nécessaire : certains n'ont pas d'extrait disponible.
  @candidates 12

  @impl true
  def mount(_params, %{"access_token" => token, "provider" => name}, socket) do
    case Providers.fetch(name) do
      {:ok, provider} -> {:ok, setup(socket, provider, token)}
      :error -> {:ok, redirect(socket, to: ~p"/")}
    end
  end

  def mount(_params, _session, socket), do: {:ok, redirect(socket, to: ~p"/")}

  defp setup(socket, provider, token) do
    socket =
      assign(socket,
        provider: provider,
        token: token,
        dev_tools: dev_tools?(),
        likes: nil,
        game: nil,
        preparing: false,
        feedback: nil,
        error: nil,
        round_id: 0,
        played: MapSet.new(),
        form: to_form(%{"guess" => ""})
      )

    if connected?(socket) do
      start_async(socket, :likes, fn -> provider.liked_tracks(token) end)
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
    require Logger
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

  @impl true
  def handle_event("start", _params, %{assigns: %{likes: likes, preparing: false}} = socket)
      when is_list(likes) do
    %{provider: provider, token: token, played: played} = socket.assigns

    {:noreply,
     socket
     |> assign(preparing: true, feedback: nil, error: nil)
     |> start_async(:round, fn -> build_round(provider, token, likes, played) end)}
  end

  def handle_event("start", _params, socket), do: {:noreply, socket}

  # --- Saisie ---------------------------------------------------------------

  def handle_event("guess", %{"guess" => text}, %{assigns: %{game: %Game{status: :playing} = game}} = socket) do
    if String.trim(text) == "" do
      {:noreply, socket}
    else
      {game, hits} = Game.guess(game, text)

      socket =
        Enum.reduce(hits, socket, fn {_kind, track, _points}, acc ->
          push_event(acc, "mix:stop", %{id: track.id})
        end)

      socket =
        if game.status == :finished, do: push_event(socket, "mix:stop_all", %{}), else: socket

      {:noreply,
       assign(socket,
         game: game,
         feedback: feedback(hits, text),
         form: to_form(%{"guess" => ""})
       )}
    end
  end

  def handle_event("guess", _params, socket), do: {:noreply, socket}

  # Outil de développement : revérifié côté serveur, un événement forgé ne passe pas en production.
  def handle_event(
        "finish",
        _params,
        %{assigns: %{dev_tools: true, game: %Game{status: :playing} = game}} = socket
      ) do
    {:noreply,
     socket
     |> assign(game: Game.finish(game), feedback: nil)
     |> push_event("mix:stop_all", %{})}
  end

  def handle_event("finish", _params, socket), do: {:noreply, socket}

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
      {:noreply, socket |> assign(game: game) |> push_event("mix:stop_all", %{})}
    end
  end

  # Tick d'une manche déjà terminée ou remplacée : on l'ignore.
  def handle_info(_msg, socket), do: {:noreply, socket}

  # --- Helpers --------------------------------------------------------------

  # Actif en développement (`dev_routes` de dev.exs) ou avec DEV_TOOLS=true (ex. Docker en local).
  defp dev_tools? do
    Application.get_env(:blind_mix, :dev_routes, false) == true or
      System.get_env("DEV_TOOLS") == "true"
  end

  defp build_round(provider, token, likes, played) do
    fresh = Enum.reject(likes, &MapSet.member?(played, &1.id))
    pool = if length(fresh) >= @candidates, do: fresh, else: likes

    tracks =
      pool
      |> Enum.take_random(@candidates)
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

    if length(tracks) == Game.round_size(), do: {:ok, tracks}, else: {:error, :not_enough_previews}
  end

  defp feedback([], text), do: "Raté : « #{text} »"

  defp feedback(hits, _text) do
    hits
    |> Enum.map(fn
      {:title, t, pts} -> "🎯 #{t.title} – #{t.artist} (+#{pts})"
      {:artist, t, pts} -> "🎤 Artiste trouvé : #{t.artist} (+#{pts})"
    end)
    |> Enum.join(" · ")
  end

  defp slot_state(game, track) do
    case Map.get(game.found, track.id) do
      nil -> if game.status == :finished, do: :missed, else: :playing
      kind -> kind
    end
  end

  defp slot_class(:playing), do: "border-zinc-300 bg-zinc-50"
  defp slot_class(:title), do: "border-green-500 bg-green-50"
  defp slot_class(:artist), do: "border-blue-500 bg-blue-50"
  defp slot_class(:missed), do: "border-red-400 bg-red-50"

  defp slot_label(:title), do: "Titre trouvé +#{Game.title_points()}"
  defp slot_label(:artist), do: "Artiste trouvé +#{Game.artist_points()}"
  defp slot_label(:missed), do: "Raté"
  defp slot_label(:playing), do: ""

  # --- Rendu ----------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <div id="mixer" phx-hook="AudioMix" class="mx-auto max-w-2xl space-y-6 p-6">
      <header class="flex items-center justify-between">
        <h1 class="text-2xl font-bold">Blind test multi-pistes</h1>
        <.link href={~p"/auth/logout"} method="delete" class="text-sm underline">Déconnexion</.link>
      </header>

      <p :if={@error} class="rounded-lg border border-red-400 bg-red-50 p-3 text-red-800">
        <%= @error %>
      </p>

      <p :if={is_nil(@likes) and is_nil(@error)}>Chargement de tes titres likés…</p>

      <div :if={@likes && is_nil(@game)} class="space-y-4">
        <p>
          5 de tes titres likés vont se jouer en même temps.
          Tape un artiste (<%= Game.artist_points() %> pts) ou un titre (<%= Game.title_points() %> pts)
          pour retirer une piste du mix.
        </p>
        <button
          phx-click="start"
          data-unlock
          disabled={@preparing}
          class="rounded-lg bg-black px-5 py-3 text-white disabled:opacity-50"
        >
          <%= if @preparing, do: "Préparation…", else: "Lancer la manche" %>
        </button>
      </div>

      <div :if={@game} class="space-y-4">
        <div class="flex justify-between text-lg font-semibold">
          <span>Score : <%= @game.score %></span>
          <span :if={@game.status == :playing}>⏱ <%= @game.time_left %> s</span>
          <span :if={@game.status == :finished}>Manche terminée</span>
        </div>

        <div class="space-y-3">
          <div
            :for={{track, i} <- Enum.with_index(@game.tracks, 1)}
            class={["flex items-center gap-4 rounded-xl border p-4", slot_class(slot_state(@game, track))]}
          >
            <span class="w-6 text-2xl font-bold"><%= i %></span>
            <div :if={slot_state(@game, track) == :playing} class="animate-pulse">♪ ♪ ♪ en cours…</div>
            <div :if={slot_state(@game, track) != :playing}>
              <div class="font-semibold"><%= track.title %></div>
              <div class="opacity-70"><%= track.artist %></div>
            </div>
            <span class="ml-auto text-sm"><%= slot_label(slot_state(@game, track)) %></span>
          </div>
        </div>

        <.form :if={@game.status == :playing} for={@form} phx-submit="guess" class="flex gap-2">
          <input
            type="text"
            name="guess"
            value={@form[:guess].value}
            autocomplete="off"
            autofocus
            placeholder="Artiste ou titre…"
            class="flex-1 rounded-lg border border-zinc-300 p-3"
          />
          <button class="rounded-lg bg-black px-5 text-white">OK</button>
        </.form>

        <p :if={@feedback} class="text-sm"><%= @feedback %></p>

        <button
          :if={@dev_tools and @game.status == :playing}
          phx-click="finish"
          class="rounded-lg border border-dashed border-orange-500 px-3 py-1 text-sm text-orange-700"
        >
          🛠 Terminer la manche (dev)
        </button>

        <button
          :if={@game.status == :finished}
          phx-click="start"
          data-unlock
          disabled={@preparing}
          class="rounded-lg bg-black px-5 py-3 text-white disabled:opacity-50"
        >
          <%= if @preparing, do: "Préparation…", else: "Manche suivante" %>
        </button>
      </div>
    </div>
    """
  end
end
