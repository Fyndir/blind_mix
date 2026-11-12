defmodule BlindMix.TasteTest do
  use ExUnit.Case, async: true

  alias BlindMix.Taste

  @now ~U[2026-11-12 12:00:00Z]

  defp track(id, artist), do: %{id: id, title: "Titre #{id}", artist: artist, preview_url: nil}
  defp hours_ago(h), do: DateTime.add(@now, -h, :hour)

  test "artist_key regroupe les écritures d'un même artiste" do
    assert Taste.artist_key("AC/DC") == Taste.artist_key("ac dc")
    assert Taste.artist_key("Beyoncé") == Taste.artist_key("BEYONCE")
    assert Taste.artist_key("The Beatles") == Taste.artist_key("Beatles")
  end

  test "un profil vide donne le même poids à tous les titres" do
    assert Taste.weight(Taste.empty(), track("1", "Daft Punk"), @now) == 1.0
  end

  test "un artiste reconnu pèse plus, avec un plafond" do
    t = track("1", "Daft Punk")
    once = %Taste{artists: %{"daftpunk" => %{played: 1, found: 1}}}
    often = %Taste{artists: %{"daftpunk" => %{played: 40, found: 40}}}

    assert Taste.weight(once, t, @now) > 1.0
    assert Taste.weight(often, t, @now) == 3.0
  end

  test "un artiste jamais reconnu après plusieurs essais pèse moins" do
    t = track("1", "Inconnu")
    taste = %Taste{artists: %{"inconnu" => %{played: 3, found: 0}}}
    assert Taste.weight(taste, t, @now) < 1.0

    # Deux essais ne suffisent pas à le juger.
    taste = %Taste{artists: %{"inconnu" => %{played: 2, found: 0}}}
    assert Taste.weight(taste, t, @now) == 1.0
  end

  test "un titre trouvé récemment est mis de côté puis revient progressivement" do
    t = track("1", "X")
    at = fn h -> %Taste{tracks: %{"1" => %{last_at: hours_ago(h), last_result: :title}}} end

    assert Taste.weight(at.(1), t, @now) < Taste.weight(at.(24 * 5), t, @now)
    assert Taste.weight(at.(24 * 5), t, @now) < Taste.weight(at.(24 * 30), t, @now)
    assert Taste.weight(at.(24 * 30), t, @now) == 1.0
  end

  test "un titre raté revient en revanche, mais pas tout de suite" do
    t = track("1", "X")
    at = fn h -> %Taste{tracks: %{"1" => %{last_at: hours_ago(h), last_result: :missed}}} end

    assert Taste.weight(at.(2), t, @now) < 1.0
    assert Taste.weight(at.(48), t, @now) > 1.0
  end

  describe "pick/4" do
    test "rend n titres distincts" do
      tracks = for i <- 1..20, do: track("#{i}", "Artiste #{i}")
      picked = Taste.pick(tracks, 12, Taste.empty())

      assert length(picked) == 12
      assert picked == Enum.uniq(picked)
      assert Enum.all?(picked, &(&1 in tracks))
    end

    test "rend tout si la liste est plus courte que n" do
      tracks = [track("1", "A"), track("2", "B")]
      assert length(Taste.pick(tracks, 12, Taste.empty())) == 2
    end

    test "à hasard égal, les titres les plus lourds passent en premier" do
      favorite = track("fav", "Daft Punk")
      recent = track("recent", "X")
      neutral = track("neutral", "Y")

      taste = %Taste{
        artists: %{"daftpunk" => %{played: 5, found: 5}},
        tracks: %{"recent" => %{last_at: hours_ago(1), last_result: :title}}
      }

      picked = Taste.pick([recent, neutral, favorite], 3, taste, now: @now, random: fn -> 0.5 end)
      assert Enum.map(picked, & &1.id) == ["fav", "neutral", "recent"]
    end

    test "sur beaucoup de tirages, un artiste reconnu sort nettement plus souvent" do
      favorite = track("fav", "Daft Punk")
      others = for i <- 1..9, do: track("o#{i}", "Autre #{i}")
      taste = %Taste{artists: %{"daftpunk" => %{played: 10, found: 10}}}

      hits =
        Enum.count(1..2000, fn _ -> favorite in Taste.pick([favorite | others], 1, taste) end)

      # Poids 3 contre 9 × 1 : environ 25 % des tirages (10 % sans profil).
      assert hits > 2000 * 0.18
    end
  end

  describe "record/3 et merge/1 (profils en mémoire des rooms)" do
    test "record/3 ajoute les résultats d'une manche" do
      taste =
        Taste.record(
          Taste.empty(),
          [{track("1", "Daft Punk"), :title}, {track("2", "Daft Punk"), :missed}],
          @now
        )

      assert taste.artists["daftpunk"] == %{played: 2, found: 1}
      assert taste.tracks["1"] == %{last_at: @now, last_result: :title}
      assert taste.tracks["2"].last_result == :missed
    end

    test "merge/1 additionne les artistes et garde la dernière écoute de chaque titre" do
      older = Taste.record(Taste.empty(), [{track("1", "Queen"), :title}], hours_ago(48))
      newer = Taste.record(Taste.empty(), [{track("1", "Queen"), :missed}], hours_ago(1))

      merged = Taste.merge([older, newer])
      assert merged.artists["queen"] == %{played: 2, found: 1}
      assert merged.tracks["1"].last_result == :missed
      assert Taste.merge([]) == Taste.empty()
    end
  end
end
