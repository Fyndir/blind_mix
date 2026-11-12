defmodule BlindMixWeb.AuthController do
  use BlindMixWeb, :controller

  alias BlindMix.Providers

  # GET /auth/:provider  ("deezer" ou "spotify") : redirige vers la page d'autorisation OAuth 2.
  # `return_to` (facultatif) : page où revenir après la connexion, ex. une room.
  def login(conn, %{"provider" => name} = params) do
    case Providers.fetch_available(name) do
      {:ok, provider} ->
        state = 16 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

        conn
        |> put_session(:oauth_state, state)
        |> put_session(:oauth_return_to, safe_return_to(params["return_to"]))
        |> redirect(external: provider.authorize_url(state))

      :error ->
        # Service inconnu ou sans clés OAuth : on ne le propose pas.
        conn
        |> put_flash(:error, "Ce service musical n'est pas disponible.")
        |> redirect(to: ~p"/")
    end
  end

  # GET /auth/:provider/callback : vérifie le `state` anti-CSRF puis échange le `code` contre un jeton.
  def callback(conn, %{"provider" => name, "code" => code, "state" => state}) do
    expected = get_session(conn, :oauth_state)

    with {:ok, provider} <- Providers.fetch_available(name),
         true <-
           is_binary(expected) and is_binary(state) and
             Plug.Crypto.secure_compare(state, expected),
         {:ok, token} <- provider.fetch_token(code) do
      return_to = get_session(conn, :oauth_return_to) || ~p"/play"

      conn
      |> delete_session(:oauth_state)
      |> delete_session(:oauth_return_to)
      |> configure_session(renew: true)
      |> put_session(:provider, name)
      |> put_session(:access_token, token)
      |> redirect(to: return_to)
    else
      _ -> failure(conn)
    end
  end

  def callback(conn, _params), do: failure(conn)

  # Quitte seulement le service musical : le compte Blind Mix reste connecté.
  def logout(conn, _params) do
    conn
    |> delete_session(:provider)
    |> delete_session(:access_token)
    |> redirect(to: ~p"/")
  end

  # Seules les pages de room sont acceptées : pas de redirection vers un site externe.
  defp safe_return_to("/rooms/" <> code = path) do
    if BlindMix.Rooms.normalize_code(code) == code, do: path
  end

  defp safe_return_to(_path), do: nil

  defp failure(conn) do
    conn
    |> put_flash(:error, "Connexion impossible, réessaie.")
    |> redirect(to: ~p"/")
  end
end
