defmodule BlindMix.Rooms.DeezerMusic do
  @moduledoc """
  Musique des rooms via l'API publique de Deezer (aucun jeton nécessaire).

  L'élargissement prend, pour chaque artiste trouvé, ses titres les plus écoutés et
  ceux de quelques artistes similaires : le choix de tubes se rapproche ainsi des
  goûts de la room au fil des manches.
  """
  @behaviour BlindMix.Rooms.Music

  alias BlindMix.Deezer

  @top_per_artist 8
  @related_per_artist 3
  @top_per_related 4

  @impl true
  def hits, do: Deezer.chart_tracks()

  @impl true
  def expand(artist_ids) do
    artist_ids
    |> Task.async_stream(&around_artist/1,
      max_concurrency: 4,
      timeout: 15_000,
      on_timeout: :kill_task
    )
    |> Enum.flat_map(fn
      {:ok, tracks} -> tracks
      _ -> []
    end)
  end

  defp around_artist(artist_id) do
    related =
      case Deezer.related_artists(artist_id, @related_per_artist) do
        {:ok, ids} -> ids
        _ -> []
      end

    top(artist_id, @top_per_artist) ++ Enum.flat_map(related, &top(&1, @top_per_related))
  end

  defp top(artist_id, limit) do
    case Deezer.artist_top(artist_id, limit) do
      {:ok, tracks} -> tracks
      _ -> []
    end
  end

  # Les titres Spotify n'ont pas d'extrait : on le retrouve chez Deezer (ISRC, puis
  # recherche). Les titres Deezer ont un extrait signé qui expire : on le redemande.
  @impl true
  def resolve(%{source: "spotify"} = track), do: Deezer.find_preview(track)
  def resolve(track), do: Deezer.refresh_preview(nil, track)
end
