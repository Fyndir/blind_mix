defmodule BlindMixWeb.GameLiveTest do
  use BlindMixWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias BlindMix.{FakeProvider, History}

  defp with_fake_service(conn) do
    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:provider, "fake")
    |> Plug.Conn.put_session(:access_token, "fake-token")
  end

  # Lance une manche et trouve les 5 titres : la manche se termine aussitôt.
  defp play_full_round(view) do
    render_async(view)
    view |> element("#start-round") |> render_click()
    render_async(view)

    for track <- FakeProvider.tracks() do
      view |> form("#guess-form", %{"guess" => track.title}) |> render_submit()
    end

    render(view)
  end

  test "sans service musical connecté, renvoie à l'accueil", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/play")
  end

  test "un invité peut jouer, sans historique", %{conn: conn} do
    {:ok, view, _html} = live(with_fake_service(conn), ~p"/play")
    render_async(view)

    assert has_element?(view, "#guest-hint")
    play_full_round(view)

    assert has_element?(view, ".bm-banner")
    refute has_element?(view, "#round-saved")
  end

  describe "joueur connecté" do
    setup :register_and_log_in_user

    test "la manche terminée est enregistrée dans son historique", %{conn: conn, scope: scope} do
      {:ok, view, _html} = live(with_fake_service(conn), ~p"/play")
      render_async(view)
      refute has_element?(view, "#guest-hint")

      play_full_round(view)
      assert has_element?(view, "#round-saved")

      assert [round] = History.list_rounds(scope)
      assert round.provider == "fake"
      assert round.found_count == 5
      assert Enum.all?(round.plays, &(&1.result == :title))
    end

    test "la manche n'est enregistrée qu'une fois", %{conn: conn, scope: scope} do
      {:ok, view, _html} = live(with_fake_service(conn), ~p"/play")
      play_full_round(view)

      # Des messages tardifs (chrono, saisie) ne doivent pas créer de doublon.
      send(view.pid, {:tick, 1})
      render(view)

      assert length(History.list_rounds(scope)) == 1
    end
  end
end
