defmodule BlindMix.Deezer do
  @moduledoc """
  OAuth Deezer + lecture des titres likés + extraits audio de 30 s.

  `find_preview/1` utilise l'API publique de Deezer (sans jeton) pour retrouver
  l'extrait d'un titre venant d'un autre service (Spotify).
  Nécessite `{:req, "~> 0.5"}` dans les dépendances.
  """
  @behaviour BlindMix.Provider

  alias BlindMix.Matcher

  @auth_url "https://connect.deezer.com/oauth/auth.php"
  @token_url "https://connect.deezer.com/oauth/access_token.php"
  @api "https://api.deezer.com"
  @page_size 100
  @max_pages 20

  defp conf, do: Application.fetch_env!(:blind_mix, :deezer)

  @impl true
  def authorize_url(state) do
    c = conf()

    @auth_url <>
      "?" <>
      URI.encode_query(%{
        app_id: c[:app_id],
        redirect_uri: c[:redirect_uri],
        perms: "basic_access",
        state: state
      })
  end

  @impl true
  def fetch_token(code) do
    c = conf()
    params = [app_id: c[:app_id], secret: c[:secret], code: code, output: "json"]

    case Req.get(@token_url, params: params, decode_body: false) do
      {:ok, %{status: 200, body: body}} ->
        case decode(body) do
          %{"access_token" => token} -> {:ok, token}
          other -> {:error, {:token, other}}
        end

      {:ok, %{body: body}} ->
        {:error, {:token, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def liked_tracks(token) do
    with {:ok, tracks} <- collect(token, 0, []) do
      {:ok, Enum.filter(tracks, &(&1.title not in [nil, ""] and &1.artist not in [nil, ""]))}
    end
  end

  defp collect(_token, index, acc) when index >= @page_size * @max_pages, do: {:ok, acc}

  defp collect(token, index, acc) do
    case api_get("/user/me/tracks", token, index: index, limit: @page_size) do
      {:ok, %{"error" => err}} ->
        {:error, err}

      {:ok, %{"data" => data} = body} ->
        acc = acc ++ for(t <- data, t["readable"] != false, do: to_track(t))

        if Map.has_key?(body, "next"),
          do: collect(token, index + @page_size, acc),
          else: {:ok, acc}

      {:ok, other} ->
        {:error, {:unexpected, other}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Les URLs d'extraits sont signées et expirent : on les redemande
  # au moment de lancer une manche plutôt que de se fier à la liste des likes.
  @impl true
  def refresh_preview(token, %{id: id} = track) do
    case api_get("/track/#{id}", token, []) do
      {:ok, %{"preview" => url}} when is_binary(url) and url != "" ->
        {:ok, %{track | preview_url: url}}

      {:ok, _} ->
        {:error, :no_preview}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Classement public Deezer (sans connexion) : sert au mode démo."
  def chart_tracks do
    case api_get("/chart/0/tracks", nil, limit: 100) do
      {:ok, %{"data" => data}} when is_list(data) ->
        tracks =
          for t <- data, t["readable"] != false, do: to_track(t)

        {:ok, Enum.filter(tracks, &(&1.title not in [nil, ""] and &1.artist not in [nil, ""]))}

      {:ok, other} ->
        {:error, {:unexpected, other}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Retrouve un extrait Deezer pour un titre venant d'ailleurs.
  D'abord par ISRC (fiable), puis par recherche artiste + titre (vérifiée sur l'artiste).
  """
  def find_preview(track) do
    isrc = Map.get(track, :isrc)

    with true <- is_binary(isrc) and isrc != "",
         {:ok, %{"preview" => url}} when is_binary(url) and url != "" <-
           api_get("/track/isrc:" <> isrc, nil, []) do
      {:ok, %{track | preview_url: url}}
    else
      _ -> search_preview(track)
    end
  end

  defp search_preview(track) do
    title = Matcher.normalize(track.title, :strict)
    query = ~s(artist:"#{track.artist}" track:"#{title}")

    with {:ok, %{"data" => results}} when is_list(results) <-
           api_get("/search", nil, q: query, limit: 5),
         %{"preview" => url} when is_binary(url) and url != "" <-
           Enum.find(results, &good_result?(&1, track)) do
      {:ok, %{track | preview_url: url}}
    else
      _ -> {:error, :no_preview}
    end
  end

  defp good_result?(%{"preview" => url, "artist" => %{"name" => name}}, track)
       when is_binary(url) and url != "",
       do: Matcher.match?(name, track.artist)

  defp good_result?(_, _), do: false

  defp api_get(path, token, params) do
    params = if token, do: Keyword.put(params, :access_token, token), else: params

    case Req.get(@api <> path, params: params, decode_body: false) do
      {:ok, %{body: body}} -> {:ok, decode(body)}
      {:error, reason} -> {:error, reason}
    end
  end

  # Deezer renvoie parfois du JSON avec un content-type inhabituel : on décode à la main.
  defp decode(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, json} -> json
      {:error, _} -> %{"raw" => body}
    end
  end

  defp decode(body), do: body

  defp to_track(t) do
    %{
      id: to_string(t["id"]),
      title: t["title_short"] || t["title"],
      artist: get_in(t, ["artist", "name"]),
      preview_url: t["preview"]
    }
  end
end
