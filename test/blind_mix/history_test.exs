defmodule BlindMix.HistoryTest do
  use BlindMix.DataCase, async: true

  import BlindMix.AccountsFixtures

  alias BlindMix.{Game, History}
  alias BlindMix.Accounts.Scope

  defp track(id, artist, title \\ nil),
    do: %{id: id, title: title || "Titre #{id}", artist: artist, preview_url: "https://x/#{id}"}

  # Une manche terminée : t1 titre trouvé, t2 artiste trouvé, t3 raté.
  defp finished_game do
    game =
      Game.new([track("t1", "Daft Punk"), track("t2", "AC/DC"), track("t3", "Inconnu")], 40)

    {game, _} = Game.force(game, "t1", :title)
    {game, _} = Game.force(game, "t2", :artist)
    Game.finish(game)
  end

  setup do
    %{scope: Scope.for_user(user_fixture())}
  end

  test "record_round/3 enregistre la manche et chaque piste", %{scope: scope} do
    assert {:ok, round} = History.record_round(scope, "deezer", finished_game())

    # Le score de la manche ne compte que ses propres points (pas le total reporté).
    assert round.score == Game.title_points() + Game.artist_points()
    assert round.found_count == 2
    assert round.track_count == 3

    [listed] = History.list_rounds(scope)

    assert Enum.map(listed.plays, &{&1.track_id, &1.result}) ==
             [{"t1", :title}, {"t2", :artist}, {"t3", :missed}]
  end

  test "stats/1 et top_artists/1 résument l'historique", %{scope: scope} do
    {:ok, _} = History.record_round(scope, "deezer", finished_game())
    {:ok, _} = History.record_round(scope, "deezer", finished_game())

    stats = History.stats(scope)
    assert stats.rounds == 2
    assert stats.plays == 6
    assert stats.found == 4
    assert stats.titles == 2
    assert stats.best_score == Game.title_points() + Game.artist_points()

    artists = History.top_artists(scope)
    assert Enum.map(artists, & &1.artist) == ["AC/DC", "Daft Punk"]
    assert Enum.all?(artists, &(&1.found == 2 and &1.played == 2))
  end

  test "taste/2 alimente le profil de goûts", %{scope: scope} do
    {:ok, _} = History.record_round(scope, "deezer", finished_game())
    taste = History.taste(scope, "deezer")

    assert taste.artists["daftpunk"] == %{played: 1, found: 1}
    assert taste.artists["inconnu"] == %{played: 1, found: 0}
    assert %{last_result: :missed} = taste.tracks["t3"]

    # Les titres d'un autre service ne se mélangent pas, les artistes si.
    other = History.taste(scope, "spotify")
    assert other.tracks == %{}
    assert other.artists == taste.artists
  end

  test "chaque joueur ne voit que ses propres données", %{scope: scope} do
    {:ok, _} = History.record_round(scope, "deezer", finished_game())
    other = Scope.for_user(user_fixture())

    assert History.list_rounds(other) == []
    assert History.stats(other).rounds == 0
    assert History.top_artists(other) == []
    assert History.taste(other, "deezer").artists == %{}
  end

  test "list_rounds/2 pagine avec :before", %{scope: scope} do
    ids =
      for _ <- 1..3 do
        {:ok, round} = History.record_round(scope, "demo", finished_game())
        round.id
      end

    [newest, middle, oldest] = Enum.reverse(ids)
    assert Enum.map(History.list_rounds(scope, limit: 2), & &1.id) == [newest, middle]
    assert Enum.map(History.list_rounds(scope, limit: 2, before: middle), & &1.id) == [oldest]
  end
end
