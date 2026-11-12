defmodule BlindMix.Rooms.PickerTest do
  use ExUnit.Case, async: true

  alias BlindMix.Rooms.Picker
  alias BlindMix.Taste

  defp t(id, title, artist), do: %{id: id, title: title, artist: artist, preview_url: nil}
  defp player(id, likes, taste \\ Taste.empty()), do: %{id: id, likes: likes, taste: taste}
  defp ids(tracks), do: Enum.map(tracks, & &1.id)

  @hits for i <- 1..10,
            do: %{id: "h#{i}", title: "Tube #{i}", artist: "Star #{i}", preview_url: nil}

  test "key/1 reconnaît le même morceau entre services" do
    deezer = t("123", "Get Lucky (Radio Edit)", "Daft Punk")
    spotify = t("4uLU", "Get Lucky", "daft punk")
    assert Picker.key(deezer) == Picker.key(spotify)
    refute Picker.key(deezer) == Picker.key(t("9", "One More Time", "Daft Punk"))
  end

  test "les morceaux en commun passent en premier, puis les likes, puis les tubes" do
    alice = player("alice", [t("d1", "Get Lucky", "Daft Punk"), t("d2", "Solo Alice", "A")])
    bob = player("bob", [t("s1", "Get Lucky", "Daft Punk"), t("s2", "Solo Bob", "B")])

    picked = Picker.candidates([alice, bob], @hits, 6)

    assert [%{origin: :common, owners: ["alice", "bob"]} | rest] = picked
    assert rest |> Enum.take(2) |> Enum.map(& &1.origin) == [:likes, :likes]
    assert rest |> Enum.drop(2) |> Enum.all?(&(&1.origin == :hits))
    assert length(picked) == 6
  end

  test "un morceau commun à trois joueurs passe avant un commun à deux" do
    shared3 = t("x", "Tous", "Groupe")
    shared2 = t("y", "Deux", "Duo")

    players = [
      player("a", [shared3, shared2]),
      player("b", [shared3, shared2]),
      player("c", [shared3])
    ]

    # Hasard fixe : seul le poids départage (3² = 9 contre 2² = 4).
    assert ["x", "y" | _] = players |> Picker.candidates(@hits, 5, random: fn -> 0.5 end) |> ids()
  end

  test "les likes de chacun sortent à tour de rôle" do
    alice = player("alice", for(i <- 1..3, do: t("a#{i}", "Alice #{i}", "AA#{i}")))
    bob = player("bob", for(i <- 1..3, do: t("b#{i}", "Bob #{i}", "BB#{i}")))

    owners = [alice, bob] |> Picker.candidates([], 6) |> Enum.map(&hd(&1.owners))
    assert owners == ["alice", "bob", "alice", "bob", "alice", "bob"]
  end

  test "sans likes, la room joue des tubes pondérés par les goûts de la room" do
    fan = Taste.record(Taste.empty(), [{hd(@hits), :title}, {hd(@hits), :title}])
    anonymous = player("anon", nil, fan)

    picked = Picker.candidates([anonymous], @hits, 5, random: fn -> 0.5 end)
    assert Enum.all?(picked, &(&1.origin == :hits))
    # À hasard égal, l'artiste reconnu passe devant… sauf que ce titre précis vient
    # d'être trouvé : il se repose. Un autre titre du même artiste passerait devant.
    refute hd(picked).id == "h1"
  end

  test "un artiste reconnu par la room fait remonter ses autres titres" do
    star_song = %{id: "h1", title: "Tube 1", artist: "Star 1", preview_url: nil}
    fan = Taste.record(Taste.empty(), [{star_song, :title}, {star_song, :title}])
    other_song = %{id: "new", title: "Nouveau tube", artist: "Star 1", preview_url: nil}

    picked =
      Picker.candidates([player("anon", nil, fan)], @hits ++ [other_song], 3,
        random: fn -> 0.5 end
      )

    assert hd(picked).id == "new"
  end

  test "les titres déjà joués passent après les autres" do
    alice = player("alice", [t("a1", "Déjà joué", "X"), t("a2", "Nouveau", "Y")])
    played = MapSet.new([Picker.key(t("a1", "Déjà joué", "X"))])

    assert ["a2", "h" <> _ | _] =
             [alice] |> Picker.candidates(@hits, 4, played: played) |> ids()

    # Faute de mieux, un titre déjà joué peut revenir.
    assert "a1" in ids(Picker.candidates([alice], [], 4, played: played))
  end

  test "common_count/1 compte les morceaux partagés" do
    alice = player("alice", [t("1", "A", "X"), t("2", "B", "Y")])
    bob = player("bob", [t("3", "A", "X"), t("4", "C", "Z")])
    anon = player("anon", nil)

    assert Picker.common_count([alice, bob, anon]) == 1
    assert Picker.common_count([alice]) == 0
  end

  test "interleave/1 alterne entre des listes de tailles différentes" do
    assert Picker.interleave([[1, 2, 3], [:a], [], [:x, :y]]) == [1, :a, :x, 2, :y, 3]
  end
end
