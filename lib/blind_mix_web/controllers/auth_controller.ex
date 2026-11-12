defmodule BlindMixWeb.AuthController do
  use BlindMixWeb, :controller

  alias BlindMix.Providers

  # GET /auth/:provider  ("deezer" ou "spotify") : redirige vers la page d'autorisation OAuth 2.
  def login(conn, %{"provider" => name}) do
    case Providers.fetch(name) do
      {:ok, provider} ->
        state = 16 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

        conn
        |> put_session(:oauth_state, state)
        |> redirect(external: provider.authorize_url(state))

      :error ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(404, "Fournisseur inconnu")
    end
  end

  # GET /auth/:provider/callback : vérifie le `state` anti-CSRF puis échange le `code` contre un jeton.
  def callback(conn, %{"provider" => name, "code" => code, "state" => state}) do
    expected = get_session(conn, :oauth_state)

    with {:ok, provider} <- Providers.fetch(name),
         true <-
           is_binary(expected) and is_binary(state) and
             Plug.Crypto.secure_compare(state, expected),
         {:ok, token} <- provider.fetch_token(code) do
      conn
      |> delete_session(:oauth_state)
      |> configure_session(renew: true)
      |> put_session(:provider, name)
      |> put_session(:access_token, token)
      |> redirect(to: ~p"/play")
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

  defp failure(conn) do
    conn
    |> put_flash(:error, "Connexion impossible, réessaie.")
    |> redirect(to: ~p"/")
  end
end
