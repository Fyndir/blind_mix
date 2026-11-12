defmodule BlindMixWeb.AdminLiveTest do
  use BlindMixWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import BlindMix.AccountsFixtures

  alias BlindMix.Rooms

  setup do
    previous = Application.get_env(:blind_mix, :admin_emails)
    Application.put_env(:blind_mix, :admin_emails, ["chef@example.com"])
    on_exit(fn -> Application.put_env(:blind_mix, :admin_emails, previous) end)
    :ok
  end

  defp log_in_admin(%{conn: conn}) do
    admin = user_fixture(%{email: "chef@example.com"})
    %{conn: log_in_user(conn, admin), admin: admin}
  end

  describe "accès" do
    test "un visiteur non connecté est envoyé vers la connexion", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/admin")
      assert redirected_to(get(conn, ~p"/admin/dashboard")) == ~p"/users/log-in"
    end

    test "un joueur qui n'est pas admin est renvoyé à l'accueil", %{conn: conn} do
      conn = log_in_user(conn, user_fixture())

      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/admin")
      assert redirected_to(get(conn, ~p"/admin/dashboard")) == ~p"/"
      refute get(conn, ~p"/") |> html_response(200) =~ ~s(id="nav-admin")
    end

    test "un admin voit la page, le lien de navigation et la supervision", %{conn: conn} do
      %{conn: conn} = log_in_admin(%{conn: conn})

      {:ok, view, _html} = live(conn, ~p"/admin")
      assert has_element?(view, "#admin-stats")
      assert has_element?(view, "#admin-dashboard-link")
      assert has_element?(view, "#nav-admin")

      assert {:ok, _dashboard, html} = live(conn, ~p"/admin/dashboard/home")
      assert html =~ "Phoenix LiveDashboard" or html =~ "System information"
    end
  end

  describe "comptes" do
    setup :log_in_admin

    test "recherche puis suppression d'un compte", %{conn: conn, admin: admin} do
      user = user_fixture(%{email: "fan@example.com"})
      {:ok, view, _html} = live(conn, ~p"/admin")

      assert has_element?(view, "#users-#{user.id}")
      refute has_element?(view, "#delete-user-#{admin.id}")

      view |> form("#admin-search", %{"q" => "chef"}) |> render_change()
      refute has_element?(view, "#users-#{user.id}")

      view |> form("#admin-search", %{"q" => ""}) |> render_change()
      view |> element("#delete-user-#{user.id}") |> render_click()

      refute has_element?(view, "#users-#{user.id}")
      refute BlindMix.Repo.get(BlindMix.Accounts.User, user.id)
    end
  end

  describe "rooms" do
    setup :log_in_admin

    test "fermer une room renvoie ses joueurs à l'accueil", %{conn: conn} do
      {:ok, code} = Rooms.create_room()

      player_conn =
        build_conn()
        |> init_test_session(%{"player_id" => "p1", "player_name" => "Alice"})

      {:ok, room_view, _html} = live(player_conn, ~p"/rooms/#{code}")

      {:ok, view, _html} = live(conn, ~p"/admin")
      assert has_element?(view, "#rooms-#{code}")

      view |> element("#close-room-#{code}") |> render_click()
      refute has_element?(view, "#rooms-#{code}")

      assert_redirect(room_view, ~p"/")
    end
  end
end
