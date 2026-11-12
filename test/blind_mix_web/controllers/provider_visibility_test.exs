defmodule BlindMixWeb.ProviderVisibilityTest do
  # La config Deezer / Spotify est globale : ces tests ne tournent pas en parallèle.
  use BlindMixWeb.ConnCase, async: false

  alias BlindMix.ProviderConfig

  test "sans clés, Deezer et Spotify sont masqués et le mode démo devient le bouton principal",
       %{conn: conn} do
    ProviderConfig.unconfigure_all()
    html = conn |> get(~p"/") |> html_response(200)

    refute html =~ ~s(id="home-spotify")
    refute html =~ ~s(id="home-deezer")
    refute html =~ "/auth/spotify"
    refute html =~ "/auth/deezer"
    assert html =~ ~s(id="home-demo")
    assert html =~ "titres du moment"
  end

  test "seul le service configuré est proposé", %{conn: conn} do
    ProviderConfig.unconfigure_all()
    ProviderConfig.put(:deezer, app_id: "dz_id", secret: "dz_secret", redirect_uri: "http://x")
    html = conn |> get(~p"/") |> html_response(200)

    assert html =~ ~s(id="home-deezer")
    refute html =~ ~s(id="home-spotify")
    assert html =~ "Pas de compte Deezer ?"
    assert html =~ ~s(id="home-demo")
  end

  test "avec toutes les clés, les deux services sont proposés", %{conn: conn} do
    ProviderConfig.configure_all()
    html = conn |> get(~p"/") |> html_response(200)

    assert html =~ ~s(id="home-spotify")
    assert html =~ ~s(id="home-deezer")
    assert html =~ "de tes titres likés"
  end

  test "un lien direct vers un service sans clés renvoie à l'accueil", %{conn: conn} do
    ProviderConfig.unconfigure_all()
    conn = get(conn, ~p"/auth/spotify")

    assert redirected_to(conn) == ~p"/"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "pas disponible"
    refute get_session(conn, :oauth_state)
  end

  test "un service configuré redirige bien vers sa page d'autorisation", %{conn: conn} do
    ProviderConfig.configure_all()
    conn = get(conn, ~p"/auth/deezer")

    assert redirected_to(conn) =~ "connect.deezer.com"
  end

  test "le mode démo marche sans aucune clé", %{conn: conn} do
    ProviderConfig.unconfigure_all()
    conn = get(conn, ~p"/auth/demo")

    assert redirected_to(conn) =~ "/auth/demo/callback"
  end
end
