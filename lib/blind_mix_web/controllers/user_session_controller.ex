defmodule BlindMixWeb.UserSessionController do
  use BlindMixWeb, :controller

  alias BlindMix.Accounts
  alias BlindMixWeb.UserAuth

  def create(conn, %{"_action" => "confirmed"} = params) do
    create(conn, params, "Compte confirmé, bienvenue !")
  end

  # Inscription avec mot de passe (sans service mail) : connexion juste après la création.
  def create(conn, %{"_action" => "registered"} = params) do
    create(conn, params, "Profil créé, bienvenue !")
  end

  def create(conn, params) do
    create(conn, params, "Content de te revoir !")
  end

  # magic link login
  defp create(conn, %{"user" => %{"token" => token} = user_params}, info) do
    case Accounts.login_user_by_magic_link(token) do
      {:ok, {user, tokens_to_disconnect}} ->
        UserAuth.disconnect_sessions(tokens_to_disconnect)

        conn
        |> put_flash(:info, info)
        |> UserAuth.log_in_user(user, user_params)

      _ ->
        conn
        |> put_flash(:error, "Ce lien n'est pas valide ou a expiré.")
        |> redirect(to: ~p"/users/log-in")
    end
  end

  # email + password login
  defp create(conn, %{"user" => user_params}, info) do
    %{"email" => email, "password" => password} = user_params

    if user = Accounts.get_user_by_email_and_password(email, password) do
      conn
      |> put_flash(:info, info)
      |> UserAuth.log_in_user(user, user_params)
    else
      # In order to prevent user enumeration attacks, don't disclose whether the email is registered.
      conn
      |> put_flash(:error, "E-mail ou mot de passe incorrect")
      |> put_flash(:email, String.slice(email, 0, 160))
      |> redirect(to: ~p"/users/log-in")
    end
  end

  def update_password(conn, %{"user" => user_params} = params) do
    user = conn.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)
    {:ok, {_user, expired_tokens}} = Accounts.update_user_password(user, user_params)

    # disconnect all existing LiveViews with old sessions
    UserAuth.disconnect_sessions(expired_tokens)

    conn
    |> put_session(:user_return_to, ~p"/users/settings")
    |> create(params, "Mot de passe mis à jour !")
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Déconnexion réussie. À bientôt !")
    |> UserAuth.log_out_user()
  end
end
