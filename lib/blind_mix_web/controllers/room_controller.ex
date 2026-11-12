defmodule BlindMixWeb.RoomController do
  @moduledoc """
  Entrée dans les rooms multijoueur : création, recherche par code et choix du pseudo.
  Le jeu lui-même se passe dans `BlindMixWeb.RoomLive`.
  """
  use BlindMixWeb, :controller

  import Phoenix.Component, only: [to_form: 2]

  alias BlindMix.Rooms

  @max_name 24

  # POST /rooms : nouvelle room, son créateur en devient l'hôte en y entrant.
  def create(conn, _params) do
    case Rooms.create_room() do
      {:ok, code} ->
        redirect(conn, to: ~p"/rooms/#{code}")

      {:error, _} ->
        conn |> put_flash(:error, "Impossible de créer la room.") |> redirect(to: ~p"/")
    end
  end

  # GET /rooms/join?code=K7RX2 : formulaire « Rejoindre » de l'accueil.
  def find(conn, params) do
    code = Rooms.normalize_code(params["code"])

    if code && Rooms.exists?(code) do
      redirect(conn, to: ~p"/rooms/#{code}")
    else
      conn
      |> put_flash(:error, "Aucune room avec ce code. Vérifie-le auprès de tes amis.")
      |> redirect(to: ~p"/")
    end
  end

  # GET /rooms/:code/join : choix du pseudo.
  def join_form(conn, %{"code" => code}) do
    with_room(conn, code, fn code ->
      name = get_session(conn, :player_name) || default_name(conn)
      render(conn, :join, code: code, form: to_form(%{"name" => name}, as: :player))
    end)
  end

  # POST /rooms/:code/join : le pseudo est gardé en session pour les prochaines rooms.
  def join(conn, %{"code" => code} = params) do
    with_room(conn, code, fn code ->
      name = params |> get_in(["player", "name"]) |> to_string() |> String.trim()

      if name == "" or String.length(name) > @max_name do
        form =
          to_form(%{"name" => name},
            as: :player,
            errors: [name: {"doit faire entre 1 et #{@max_name} caractères", []}],
            action: :validate
          )

        conn |> put_status(:unprocessable_entity) |> render(:join, code: code, form: form)
      else
        conn
        |> put_session(:player_name, name)
        |> ensure_player_id()
        |> redirect(to: ~p"/rooms/#{code}")
      end
    end)
  end

  defp with_room(conn, code, fun) do
    code = Rooms.normalize_code(code)

    if code && Rooms.exists?(code) do
      fun.(code)
    else
      conn
      |> put_flash(:error, "Cette room n'existe pas (ou plus).")
      |> redirect(to: ~p"/")
    end
  end

  defp ensure_player_id(conn) do
    if get_session(conn, :player_id) do
      conn
    else
      put_session(
        conn,
        :player_id,
        12 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
      )
    end
  end

  defp default_name(%{assigns: %{current_scope: %{user: %{email: email}}}}),
    do: email |> String.split("@") |> hd() |> String.slice(0, @max_name)

  defp default_name(_conn), do: ""
end
