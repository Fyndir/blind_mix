defmodule BlindMix.Game do
  @moduledoc """
  État pur d'une manche (aucun processus, facile à tester).

  Règles :
    * trouver le titre d'une chanson : 5 points, la piste est retirée du mix
    * trouver seulement l'artiste     : 2 points, la piste est retirée du mix
    * une saisie qui correspond à un titre l'emporte sur l'artiste
    * un artiste commun à plusieurs pistes restantes les retire toutes (points pour chacune)
  """

  alias BlindMix.Matcher

  @title_points 5
  @artist_points 2
  @round_seconds 90
  @round_size 5

  defstruct tracks: [], found: %{}, score: 0, status: :playing, time_left: @round_seconds

  def round_size, do: @round_size
  def title_points, do: @title_points
  def artist_points, do: @artist_points

  @doc "Nouvelle manche. `score` permet de reporter le total d'une manche à l'autre."
  def new(tracks, score \\ 0), do: %__MODULE__{tracks: tracks, score: score}

  def remaining(%__MODULE__{tracks: tracks, found: found}) do
    Enum.reject(tracks, &Map.has_key?(found, &1.id))
  end

  @doc "Retourne `{game, hits}` où hits = [{:title | :artist, track, points}]."
  def guess(%__MODULE__{status: :playing} = game, text) do
    remaining = remaining(game)

    case Enum.find(remaining, &Matcher.match?(text, &1.title)) do
      nil ->
        hits = Enum.filter(remaining, &Matcher.match?(text, &1.artist))
        apply_hits(game, hits, :artist, @artist_points)

      track ->
        apply_hits(game, [track], :title, @title_points)
    end
  end

  def guess(game, _text), do: {game, []}

  @doc "Décompte d'une seconde."
  def tick(%__MODULE__{status: :playing, time_left: t} = game) when t <= 1,
    do: %{game | time_left: 0, status: :finished}

  def tick(%__MODULE__{status: :playing} = game), do: %{game | time_left: game.time_left - 1}
  def tick(game), do: game

  @doc "Termine la manche immédiatement (outil de développement)."
  def finish(%__MODULE__{} = game), do: %{game | status: :finished}

  defp apply_hits(game, [], _kind, _points), do: {game, []}

  defp apply_hits(game, hits, kind, points) do
    found = Enum.reduce(hits, game.found, &Map.put(&2, &1.id, kind))
    game = %{game | found: found, score: game.score + points * length(hits)}
    game = if remaining(game) == [], do: %{game | status: :finished}, else: game
    {game, Enum.map(hits, &{kind, &1, points})}
  end
end
