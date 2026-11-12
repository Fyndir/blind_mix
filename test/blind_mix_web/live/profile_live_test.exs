defmodule BlindMixWeb.ProfileLiveTest do
  use BlindMixWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias BlindMix.{Game, History}

  defp finished_game do
    tracks = [
      %{id: "t1", title: "One More Time", artist: "Daft Punk", preview_url: "u"},
      %{id: "t2", title: "Back in Black", artist: "AC/DC", preview_url: "u"}
    ]

    {game, _} = Game.force(Game.new(tracks), "t1", :title)
    Game.finish(game)
  end

  test "réservé aux joueurs connectés", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/profile")
  end

  describe "joueur connecté" do
    setup :register_and_log_in_user

    test "profil vide : invite à jouer", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/profile")

      assert has_element?(view, "#profile-stats")
      assert has_element?(view, "#taste-empty")
      assert has_element?(view, "#rounds-empty")
      refute has_element?(view, "#rounds-more")
    end

    test "affiche statistiques, goûts et historique", %{conn: conn, scope: scope} do
      {:ok, _} = History.record_round(scope, "deezer", finished_game())
      {:ok, view, _html} = live(conn, ~p"/profile")

      assert has_element?(view, "#stat-rounds", "1")
      assert has_element?(view, "#taste-artist-0", "Daft Punk")
      refute has_element?(view, "#taste-empty")
      assert has_element?(view, "#rounds article", "One More Time")
      assert has_element?(view, "#rounds article", "Back in Black")
    end

    test "charge les manches précédentes à la demande", %{conn: conn, scope: scope} do
      for _ <- 1..11, do: {:ok, _} = History.record_round(scope, "demo", finished_game())
      {:ok, view, _html} = live(conn, ~p"/profile")

      assert view
             |> render()
             |> LazyHTML.from_fragment()
             |> LazyHTML.query("#rounds article")
             |> Enum.count() == 10

      view |> element("#rounds-more") |> render_click()

      assert view
             |> render()
             |> LazyHTML.from_fragment()
             |> LazyHTML.query("#rounds article")
             |> Enum.count() == 11

      refute has_element?(view, "#rounds-more")
    end
  end
end
