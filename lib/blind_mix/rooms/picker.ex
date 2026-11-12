defmodule BlindMix.Rooms.Picker do
  @moduledoc """
  Choix des titres d'une manche multijoueur (pur, sans réseau ni base).

  Les candidats sont rendus par ordre de priorité ; la room garde les premiers qui ont
  un extrait audio :

    1. **morceaux en commun** : likés par au moins deux joueurs, d'autant plus
       prioritaires qu'ils sont partagés (poids = nombre de joueurs²) ;
    2. **likes de chacun**, à tour de rôle entre les joueurs pour que personne ne
       soit oublié, pondérés par le profil de goûts de leur propriétaire ;
    3. **tubes** (classement Deezer, élargi au fil des manches), pondérés par le
       profil de toute la room : c'est ce qui affine la recherche pour les anonymes.

  Les titres déjà joués dans la room passent après tous les autres.

  Deux titres sont « le même morceau » s'ils ont le même artiste et le même titre
  court, même venant de services différents (Deezer, Spotify) : voir `key/1`.
  """

  alias BlindMix.{Matcher, Taste}

  @type player :: %{id: String.t(), likes: [map()] | nil, taste: Taste.t()}

  @doc "Clé d'un morceau, indépendante du service : artiste + titre court normalisés."
  def key(track) do
    title = track.title |> Matcher.normalize(:strict) |> String.replace(" ", "")
    Taste.artist_key(track.artist) <> "|" <> title
  end

  @doc """
  Index des likes : `%{clé => %{track: track, owners: [id de joueur]}}`.
  Le premier titre rencontré sert de représentant.
  """
  def index(players) do
    for %{id: id, likes: likes} <- players, is_list(likes), track <- likes, reduce: %{} do
      acc ->
        Map.update(acc, key(track), %{track: track, owners: [id]}, fn entry ->
          if id in entry.owners, do: entry, else: %{entry | owners: entry.owners ++ [id]}
        end)
    end
  end

  @doc "Nombre de morceaux likés par au moins deux joueurs."
  def common_count(players) do
    players |> index() |> Enum.count(fn {_key, entry} -> length(entry.owners) >= 2 end)
  end

  @doc """
  Liste ordonnée d'au plus `n` candidats. Chaque titre rendu porte `:owners` (joueurs
  qui l'ont liké, vide pour un tube) et `:origin` (`:common`, `:likes` ou `:hits`).

  Options : `:played` (MapSet de clés déjà jouées), `:now`, `:random` (tests).
  """
  def candidates(players, hits, n, opts \\ []) do
    played = Keyword.get(opts, :played, MapSet.new())
    tastes = Map.new(players, &{&1.id, &1.taste})
    index = index(players)

    {fresh, replay} =
      Enum.split_with(index, fn {key, _entry} -> not MapSet.member?(played, key) end)

    ordered =
      common(fresh, tastes, opts) ++
        likes_in_turn(fresh, players, opts) ++
        hits(hits, played, players, opts) ++
        common(replay, tastes, opts) ++
        likes_in_turn(replay, players, opts) ++
        replay_hits(hits, played)

    ordered
    |> Enum.uniq_by(&key/1)
    |> Enum.take(n)
  end

  defp common(entries, tastes, opts) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    entries
    |> Enum.filter(fn {_key, entry} -> length(entry.owners) >= 2 end)
    |> Enum.map(fn {_key, entry} -> tag(entry.track, entry.owners, :common) end)
    |> Taste.weighted_pick(:infinity, &common_weight(&1, tastes, now), opts)
  end

  defp common_weight(track, tastes, now) do
    owners = track.owners
    taste = owners |> Enum.map(&Map.get(tastes, &1, Taste.empty())) |> Taste.merge()
    length(owners) * length(owners) * Taste.weight(taste, track, now)
  end

  # Likes d'un seul joueur : chaque joueur propose ses titres à tour de rôle.
  defp likes_in_turn(entries, players, opts) do
    by_owner =
      entries
      |> Enum.filter(fn {_key, entry} -> length(entry.owners) == 1 end)
      |> Enum.group_by(fn {_key, entry} -> hd(entry.owners) end, fn {_key, entry} ->
        tag(entry.track, entry.owners, :likes)
      end)

    players
    |> Enum.map(fn player ->
      by_owner |> Map.get(player.id, []) |> Taste.pick(:infinity, player.taste, opts)
    end)
    |> interleave()
  end

  defp hits(hits, played, players, opts) do
    taste = players |> Enum.map(& &1.taste) |> Taste.merge()

    hits
    |> Enum.reject(&MapSet.member?(played, key(&1)))
    |> Enum.map(&tag(&1, [], :hits))
    |> Taste.pick(:infinity, taste, opts)
  end

  defp replay_hits(hits, played) do
    hits
    |> Enum.filter(&MapSet.member?(played, key(&1)))
    |> Enum.shuffle()
    |> Enum.map(&tag(&1, [], :hits))
  end

  defp tag(track, owners, origin), do: Map.merge(track, %{owners: owners, origin: origin})

  @doc false
  def interleave(lists) do
    lists
    |> Enum.reject(&(&1 == []))
    |> Stream.unfold(fn
      [] -> nil
      lists -> {Enum.map(lists, &hd/1), lists |> Enum.map(&tl/1) |> Enum.reject(&(&1 == []))}
    end)
    |> Enum.concat()
  end
end
