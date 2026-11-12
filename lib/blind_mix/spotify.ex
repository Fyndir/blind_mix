defmodule BlindMix.Spotify do
  @moduledoc """
  OAuth 2 (Authorization Code) Spotify + lecture des titres likés.

  Spotify ne renvoie plus de `preview_url` : l'extrait audio est retrouvé chez Deezer,
  par code ISRC puis par recherche artiste + titre.
  """
  @behaviour BlindMix.Provider

  alias BlindMix.Deezer

  @auth_url "https://accounts.spotify.com/authorize"
  @token_url "https://accounts.spotify.com/api/token"
  @api "https://api.spotify.com/v1"
  @scope "user-library-read"
  @page_size 50
  @max_pages 40

  defp conf, do: Application.fetch_env!(:blind_mix, :spotify)

  @impl true
  def authorize_url(state) do
    c = conf()

    @auth_url <>
      "?" <>
      URI.encode_query(%{
        response_type: "code",
        client_id: c[:client_id],
        scope: @scope,
        redirect_uri: c[:redirect_uri],
        state: state
      })
  end

  @impl true
  def fetch_token(code) do
    c = conf()

    response =
      Req.post(@token_url,
        auth: {:basic, "#{c[:client_id]}:#{c[:client_secret]}"},
        form: [grant_type: "authorization_code", code: code, redirect_uri: c[:redirect_uri]]
      )

    case response do
      {:ok, %{status: 200, body: %{"access_token" => token}}} -> {:ok, token}
      {:ok, %{body: body}} -> {:error, {:token, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  # Première page pour connaître le total, puis les autres en parallèle (4 à la fois).
  @impl true
  def liked_tracks(token) do
    with {:ok, first} <- page(token, 0) do
      total = first["total"] || 0

      offsets =
        if total > @page_size,
          do: Enum.take(Enum.to_list(@page_size..(total - 1)//@page_size), @max_pages - 1),
          else: []

      rest =
        offsets
        |> Task.async_stream(&page(token, &1),
          max_concurrency: 4,
          timeout: 15_000,
          on_timeout: :kill_task
        )
        |> Enum.flat_map(fn
          {:ok, {:ok, body}} -> [body]
          _ -> []
        end)

      {:ok, Enum.flat_map([first | rest], &to_tracks/1)}
    end
  end

  # Le jeton Spotify n'est pas nécessaire : l'extrait vient de l'API publique de Deezer.
  @impl true
  def refresh_preview(_token, track), do: Deezer.find_preview(track)

  defp page(token, offset) do
    case Req.get(@api <> "/me/tracks",
           auth: {:bearer, token},
           params: [limit: @page_size, offset: offset]
         ) do
      {:ok, %{status: 200, body: %{"items" => _} = body}} -> {:ok, body}
      {:ok, %{status: status, body: body}} -> {:error, {:spotify, status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  # Les fichiers locaux n'ont pas d'id : on les ignore.
  defp to_tracks(%{"items" => items}) do
    for %{"track" => %{"id" => id, "name" => name} = t} <- items,
        is_binary(id),
        is_binary(name),
        artist = get_in(t, ["artists", Access.at(0), "name"]),
        is_binary(artist) do
      %{
        id: id,
        title: name,
        artist: artist,
        isrc: get_in(t, ["external_ids", "isrc"]),
        preview_url: nil
      }
    end
  end
end
