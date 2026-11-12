defmodule BlindMixWeb.AuthController do
  use BlindMixWeb, :controller

  require Logger

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

    with {:provider, {:ok, provider}} <- {:provider, Providers.fetch_available(name)},
         {:state, true} <-
           {:state,
            is_binary(expected) and is_binary(state) and
              Plug.Crypto.secure_compare(state, expected)},
         {:token, {:ok, token}} <- {:token, provider.fetch_token(code)} do
      return_to = get_session(conn, :oauth_return_to) || ~p"/play"
      Logger.info("[oauth] #{name} connecté (#{who(conn)})")

      conn
      |> delete_session(:oauth_state)
      |> delete_session(:oauth_return_to)
      |> configure_session(renew: true)
      |> put_session(:provider, name)
      |> put_session(:access_token, token)
      |> redirect(to: return_to)
    else
      {:provider, _} ->
        Logger.warning("[oauth] #{inspect(name)} : service inconnu ou sans clés")
        failure(conn)

      {:state, _} ->
        Logger.warning("[oauth] #{name} : state invalide (session expirée ou requête forgée)")
        failure(conn)

      {:token, error} ->
        Logger.error("[oauth] #{name} : échange du code refusé : #{inspect(error, limit: 10)}")
        failure(conn)
    end
  end

  # Sans `code` : le joueur a refusé l'autorisation (ou le service a renvoyé une erreur).
  def callback(conn, %{"provider" => name} = params) do
    # Valeurs venues de l'URL : inspect/1 les échappe (pas de faux retour à la ligne dans les logs).
    Logger.info(
      "[oauth] #{inspect(name)} : autorisation refusée (#{inspect(params["error"] || "sans code")})"
    )

    failure(conn)
  end

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

  defp who(conn) do
    case conn.assigns[:current_scope] do
      %{user: %{id: id}} -> "compte #{id}"
      _ -> "anonyme"
    end
  end

  defp failure(conn) do
    conn
    |> put_flash(:error, "Connexion impossible, réessaie.")
    |> redirect(to: ~p"/")
  end
end
