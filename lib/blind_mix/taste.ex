defmodule BlindMix.Taste do
  @moduledoc """
  Profil de goûts d'un joueur, calculé à partir de son historique (pur, sans base).

  Il sert à tirer les titres d'une manche parmi les likes, avec un poids par titre :

    * **artistes reconnus** : chaque fois que le joueur a trouvé un artiste (titre ou
      nom), ses titres reviennent plus souvent (jusqu'à ×3) ;
    * **artistes jamais reconnus** : après 3 essais ratés sans aucune réussite,
      leurs titres sortent moins souvent (×0.6) ;
    * **titres trouvés récemment** : mis de côté quelques jours pour éviter les
      répétitions (×0.15 pendant 3 jours, ×0.6 jusqu'à 14 jours) ;
    * **titres ratés** : une revanche est proposée plus souvent après 24 h (×1.6).

  Le tirage reste aléatoire : un poids élevé rend un titre plus probable, jamais certain.
  """

  alias BlindMix.Matcher

  @affinity_step 0.35
  @affinity_cap 2.0
  @unknown_after 3
  @unknown_weight 0.6

  defstruct artists: %{}, tracks: %{}

  @type artist_stats :: %{played: non_neg_integer(), found: non_neg_integer()}
  @type track_stats :: %{last_at: DateTime.t(), last_result: :title | :artist | :missed}
  @type t :: %__MODULE__{
          artists: %{String.t() => artist_stats()},
          tracks: %{String.t() => track_stats()}
        }

  @doc "Profil vide (joueur invité ou nouveau joueur) : tous les titres ont le même poids."
  def empty, do: %__MODULE__{}

  @doc "Clé d'artiste insensible aux accents, à la casse, à la ponctuation et aux espaces."
  def artist_key(artist) when is_binary(artist) do
    artist |> Matcher.normalize() |> String.replace(" ", "")
  end

  @doc "Poids d'un titre (1.0 = neutre)."
  def weight(%__MODULE__{} = taste, track, now \\ DateTime.utc_now()) do
    affinity(taste, track) * recency(taste, track, now)
  end

  defp affinity(taste, track) do
    case Map.get(taste.artists, artist_key(track.artist)) do
      %{found: found} when found > 0 -> 1 + min(found * @affinity_step, @affinity_cap)
      %{played: played} when played >= @unknown_after -> @unknown_weight
      _ -> 1.0
    end
  end

  defp recency(taste, track, now) do
    case Map.get(taste.tracks, track.id) do
      nil ->
        1.0

      %{last_result: :missed, last_at: at} ->
        if hours_since(at, now) < 24, do: 0.5, else: 1.6

      %{last_at: at} ->
        hours = hours_since(at, now)

        cond do
          hours < 3 * 24 -> 0.15
          hours < 14 * 24 -> 0.6
          true -> 1.0
        end
    end
  end

  defp hours_since(at, now), do: DateTime.diff(now, at, :hour)

  @doc """
  Tire `n` titres distincts, au hasard pondéré par `weight/3` (Efraimidis–Spirakis).

  Les titres sont rendus du plus prioritaire au moins prioritaire : si certains
  n'ont pas d'extrait audio, on prend simplement les suivants.

  Options : `:now` (DateTime) et `:random` (fonction 0-arité renvoyant un float dans
  [0, 1[ — utile pour des tests déterministes).
  """
  def pick(tracks, n, %__MODULE__{} = taste, opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    random = Keyword.get(opts, :random, &:rand.uniform/0)

    tracks
    |> Enum.map(fn track -> {:math.pow(random.(), 1 / weight(taste, track, now)), track} end)
    |> Enum.sort_by(&elem(&1, 0), :desc)
    |> Enum.take(n)
    |> Enum.map(&elem(&1, 1))
  end
end
