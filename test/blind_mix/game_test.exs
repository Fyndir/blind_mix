defmodule BlindMix.GameTest do
  use ExUnit.Case, async: true

  alias BlindMix.Game

  @tracks [
    %{id: "1", title: "Bohemian Rhapsody", artist: "Queen", preview_url: "http://x/1.mp3"},
    %{id: "2", title: "Halo", artist: "Beyoncé", preview_url: "http://x/2.mp3"}
  ]

  test "trouver l'artiste rapporte 2 points et retire la piste" do
    {game, hits} = @tracks |> Game.new() |> Game.guess("queen")

    assert [{:artist, %{id: "1"}, 2}] = hits
    assert game.score == 2
    assert game.found == %{"1" => :artist}
    assert game.status == :playing
    assert Enum.map(Game.remaining(game), & &1.id) == ["2"]
  end

  test "trouver le titre rapporte 5 points" do
    {game, hits} = @tracks |> Game.new() |> Game.guess("halo")

    assert [{:title, %{id: "2"}, 5}] = hits
    assert game.score == 5
    assert game.found == %{"2" => :title}
  end

  test "une saisie fausse ne change rien" do
    game = Game.new(@tracks)
    assert {^game, []} = Game.guess(game, "zzzzz")
  end

  test "la manche se termine quand toutes les pistes sont trouvées" do
    {game, _} = @tracks |> Game.new() |> Game.guess("bohemian rhapsody")
    {game, _} = Game.guess(game, "beyonce")

    assert game.status == :finished
    assert game.score == 7
    assert {^game, []} = Game.guess(game, "queen")
  end

  test "le chrono termine la manche" do
    game = %{Game.new(@tracks) | time_left: 2}
    game = Game.tick(game)
    assert game.status == :playing and game.time_left == 1
    assert Game.tick(game).status == :finished
  end

  test "finish termine la manche sans changer le score" do
    {game, _} = @tracks |> Game.new() |> Game.guess("queen")
    finished = Game.finish(game)

    assert finished.status == :finished
    assert finished.score == game.score
    assert Enum.map(Game.remaining(finished), & &1.id) == ["2"]
  end

  test "le score est reporté d'une manche à l'autre" do
    assert Game.new(@tracks, 12).score == 12
  end
end
