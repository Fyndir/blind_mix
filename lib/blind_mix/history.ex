defmodule BlindMix.History do
  @moduledoc """
  Historique des manches d'un joueur connecté, et profil de goûts qui en découle.

  Toutes les fonctions prennent le `BlindMix.Accounts.Scope` du joueur en premier argument
  et ne lisent ou n'écrivent que ses propres données.
  """

  import Ecto.Query

  alias BlindMix.Accounts.Scope
  alias BlindMix.{Game, Repo, Taste}
  alias BlindMix.History.{Play, Round}

  @doc """
  Enregistre une manche terminée : une ligne `rounds` et une ligne `plays` par piste.
  `provider` est le nom du service (« deezer », « spotify », « demo »).
  """
  def record_round(%Scope{user: user}, provider, %Game{status: :finished} = game)
      when is_binary(provider) do
    now = DateTime.utc_now(:second)

    plays =
      for track <- game.tracks do
        result = Map.get(game.found, track.id, :missed)

        %{
          user_id: user.id,
          provider: provider,
          track_id: track.id,
          title: track.title,
          artist: track.artist,
          artist_key: Taste.artist_key(track.artist),
          result: result,
          points: points(result),
          inserted_at: now
        }
      end

    Repo.transact(fn ->
      round =
        Repo.insert!(%Round{
          user_id: user.id,
          provider: provider,
          score: plays |> Enum.map(& &1.points) |> Enum.sum(),
          found_count: Enum.count(plays, &(&1.result != :missed)),
          track_count: length(plays),
          inserted_at: now
        })

      {_, _} = Repo.insert_all(Play, Enum.map(plays, &Map.put(&1, :round_id, round.id)))
      {:ok, round}
    end)
  end

  defp points(:title), do: Game.title_points()
  defp points(:artist), do: Game.artist_points()
  defp points(:missed), do: 0

  @doc """
  Profil de goûts du joueur pour un service : stats par artiste (tous services
  confondus, l'artiste est le même partout) et dernière écoute de chaque titre du service.
  """
  def taste(%Scope{user: user}, provider) when is_binary(provider) do
    artists =
      from(p in Play,
        where: p.user_id == ^user.id,
        group_by: p.artist_key,
        select:
          {p.artist_key,
           %{
             played: count(p.id),
             found: filter(count(p.id), p.result != :missed)
           }}
      )
      |> Repo.all()
      |> Map.new()

    tracks =
      from(p in Play,
        where: p.user_id == ^user.id and p.provider == ^provider,
        distinct: p.track_id,
        order_by: [asc: p.track_id, desc: p.inserted_at, desc: p.id],
        select: {p.track_id, %{last_at: p.inserted_at, last_result: p.result}}
      )
      |> Repo.all()
      |> Map.new()

    %Taste{artists: artists, tracks: tracks}
  end

  @doc "Totaux du profil : manches, meilleur score, pistes jouées et trouvées."
  def stats(%Scope{user: user}) do
    rounds =
      from(r in Round,
        where: r.user_id == ^user.id,
        select: %{
          rounds: count(r.id),
          best_score: coalesce(max(r.score), 0),
          total_score: coalesce(sum(r.score), 0),
          plays: coalesce(sum(r.track_count), 0),
          found: coalesce(sum(r.found_count), 0)
        }
      )
      |> Repo.one()

    titles =
      Repo.aggregate(
        from(p in Play, where: p.user_id == ^user.id and p.result == :title),
        :count
      )

    Map.put(rounds, :titles, titles)
  end

  @doc """
  Artistes que le joueur reconnaît le mieux : ceux qu'il a trouvés le plus souvent.
  Chaque entrée : `%{artist, found, played}` (nom tel qu'affiché la dernière fois).
  """
  def top_artists(%Scope{user: user}, limit \\ 8) do
    from(p in Play,
      where: p.user_id == ^user.id,
      group_by: p.artist_key,
      having: filter(count(p.id), p.result != :missed) > 0,
      order_by: [
        desc: filter(count(p.id), p.result != :missed),
        desc: count(p.id),
        asc: p.artist_key
      ],
      limit: ^limit,
      select: %{
        artist: max(p.artist),
        found: filter(count(p.id), p.result != :missed),
        played: count(p.id)
      }
    )
    |> Repo.all()
  end

  @doc """
  Dernières manches, pistes incluses, de la plus récente à la plus ancienne.
  `:before` (id de manche) permet de charger la page suivante.
  """
  def list_rounds(%Scope{user: user}, opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)

    query =
      from(r in Round,
        where: r.user_id == ^user.id,
        order_by: [desc: r.id],
        limit: ^limit,
        preload: :plays
      )

    query =
      case Keyword.get(opts, :before) do
        nil -> query
        id -> where(query, [r], r.id < ^id)
      end

    Repo.all(query)
  end
end
