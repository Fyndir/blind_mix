defmodule BlindMix.FakeMusic do
  @moduledoc """
  Musique de test pour les rooms, sans réseau : 8 tubes fixes, un élargissement
  prévisible, et des extraits toujours disponibles (sauf titre « Sans extrait »).
  """
  @behaviour BlindMix.Rooms.Music

  @hits for i <- 1..8,
            do: %{
              id: "hit#{i}",
              title: "Tube #{i}",
              artist: "Star #{i}",
              artist_id: "a#{i}",
              preview_url: nil
            }

  def hit_list, do: @hits

  @impl true
  def hits, do: {:ok, @hits}

  @impl true
  def expand(artist_ids) do
    for id <- artist_ids, i <- 1..2 do
      %{
        id: "#{id}-more#{i}",
        title: "Autre #{id} #{i}",
        artist: "Proche de #{id}",
        artist_id: "#{id}x",
        preview_url: nil
      }
    end
  end

  @impl true
  def resolve(%{title: "Sans extrait"}), do: {:error, :no_preview}

  def resolve(track),
    do: {:ok, Map.put(track, :preview_url, "https://example.test/#{track.id}.mp3")}
end
