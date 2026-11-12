defmodule BlindMixWeb.UserLive.NoMailModeTest do
  # Le mode « sans service mail » est un réglage global : pas de tests en parallèle.
  use BlindMixWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import BlindMix.AccountsFixtures

  alias BlindMix.Accounts

  setup do
    previous = Application.get_env(:blind_mix, :mail_enabled)
    Application.put_env(:blind_mix, :mail_enabled, false)
    on_exit(fn -> Application.put_env(:blind_mix, :mail_enabled, previous) end)
    :ok
  end

  describe "inscription" do
    test "demande un mot de passe au lieu d'envoyer un e-mail", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      assert has_element?(lv, "#registration_form input[name='user[password]']")
      assert has_element?(lv, "#registration_form input[name='user[password_confirmation]']")
    end

    test "crée un compte confirmé puis connecte le joueur", %{conn: conn} do
      email = unique_user_email()
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      form =
        form(lv, "#registration_form",
          user: %{
            email: email,
            password: valid_user_password(),
            password_confirmation: valid_user_password()
          }
        )

      render_submit(form)
      conn = follow_trigger_action(form, conn)

      assert redirected_to(conn) == ~p"/"
      assert get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Profil créé"

      user = Accounts.get_user_by_email(email)
      assert user.confirmed_at
      assert Accounts.get_user_by_email_and_password(email, valid_user_password())
    end

    test "affiche les erreurs (mot de passe trop court, confirmation)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      result =
        lv
        |> form("#registration_form",
          user: %{email: unique_user_email(), password: "court", password_confirmation: "autre"}
        )
        |> render_submit()

      assert result =~ "doit faire au moins 12 caractères"
      assert result =~ "ne correspond pas au mot de passe"
    end
  end

  test "la connexion ne propose que le mot de passe", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/users/log-in")

    refute has_element?(lv, "#login_form_magic")
    refute has_element?(lv, "#local-mailbox-note")
    assert has_element?(lv, "#login_form_password")
  end

  test "les réglages masquent le changement d'adresse", %{conn: conn} do
    {:ok, lv, _html} = conn |> log_in_user(user_fixture()) |> live(~p"/users/settings")

    refute has_element?(lv, "#email_form")
    assert has_element?(lv, "#password_form")
  end
end
