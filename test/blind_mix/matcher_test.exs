defmodule BlindMix.MatcherTest do
  use ExUnit.Case, async: true

  alias BlindMix.Matcher

  test "ignore accents, casse et ponctuation" do
    assert Matcher.match?("beyonce", "Beyoncé")
    assert Matcher.match?("ac dc", "AC/DC")
    assert Matcher.match?("the beatles", "The Beatles")
    assert Matcher.match?("beatles", "The Beatles")
  end

  test "accepte la version courte d'un titre" do
    assert Matcher.match?("bohemian rhapsody", "Bohemian Rhapsody - Remastered 2011")
    assert Matcher.match?("shape of you", "Shape of You (feat. Someone)")
  end

  test "accepte la version complète quand le titre commence par une parenthèse" do
    assert Matcher.match?("sittin on the dock of the bay", "(Sittin' On) The Dock of the Bay")
  end

  test "tolère une petite faute de frappe sur les cibles longues" do
    assert Matcher.match?("bohemian rapsody", "Bohemian Rhapsody")
  end

  test "refuse les saisies fausses, vides ou partielles" do
    refute Matcher.match?("abba", "Queen")
    refute Matcher.match?("", "Queen")
    refute Matcher.match?("pink", "Pink Floyd")
  end

  test "pas de tolérance aux fautes sur les cibles très courtes" do
    refute Matcher.match?("abb", "ABBA")
    assert Matcher.match?("abba", "ABBA")
  end
end
