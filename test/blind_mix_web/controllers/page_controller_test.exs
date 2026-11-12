defmodule BlindMixWeb.PageControllerTest do
  use BlindMixWeb.ConnCase, async: true

  test "un invité est invité à créer son profil", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)

    assert html =~ "Blind test multi-pistes"
    assert html =~ ~s(id="home-guest-note")
    assert html =~ ~s(id="home-providers")
  end

  test "un joueur connecté retrouve son profil et sa partie en cours", %{conn: conn} do
    %{conn: conn} = register_and_log_in_user(%{conn: conn})

    html =
      conn
      |> Plug.Conn.put_session(:provider, "demo")
      |> get(~p"/")
      |> html_response(200)

    assert html =~ ~s(id="home-profile-note")
    assert html =~ ~s(id="home-resume")
    refute html =~ ~s(id="home-providers")
  end

  test "changer de service garde le compte connecté", %{conn: conn} do
    %{conn: conn} = register_and_log_in_user(%{conn: conn})

    conn =
      conn
      |> Plug.Conn.put_session(:provider, "demo")
      |> Plug.Conn.put_session(:access_token, "demo")
      |> delete(~p"/auth/logout")

    assert redirected_to(conn) == ~p"/"
    refute get_session(conn, :provider)
    assert get_session(conn, :user_token)
  end
end
