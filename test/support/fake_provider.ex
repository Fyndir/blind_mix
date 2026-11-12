defmodule BlindMix.FakeProvider do
  @moduledoc "Service musical de test : 5 titres fixes, extraits toujours disponibles."
  @behaviour BlindMix.Provider

  @tracks [
    %{id: "f1", title: "Harder Better", artist: "Daft Punk"},
    %{id: "f2", title: "Thunderstruck", artist: "AC/DC"},
    %{id: "f3", title: "Bohemian Rhapsody", artist: "Queen"},
    %{id: "f4", title: "Halo", artist: "Beyonce"},
    %{id: "f5", title: "Respect", artist: "Aretha Franklin"}
  ]

  def tracks,
    do: Enum.map(@tracks, &Map.put(&1, :preview_url, "https://example.test/#{&1.id}.mp3"))

  @impl true
  def configured?, do: true

  @impl true
  def authorize_url(state), do: "/auth/fake/callback?state=#{state}&code=fake"

  @impl true
  def fetch_token("fake"), do: {:ok, "fake-token"}
  def fetch_token(_), do: {:error, :invalid_code}

  @impl true
  def liked_tracks(_token), do: {:ok, tracks()}

  @impl true
  def refresh_preview(_token, track), do: {:ok, track}
end
