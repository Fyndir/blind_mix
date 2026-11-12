defmodule BlindMix.Provider do
  @moduledoc """
  Contrat commun aux services de connexion OAuth 2 (Deezer, Spotify).

  Chaque fournisseur sait : construire l'URL d'autorisation, échanger le `code`
  contre un jeton, lister les titres likés, et trouver un extrait audio jouable.
  Spotify ne fournit plus d'extraits : il délègue à Deezer (voir `BlindMix.Deezer.find_preview/1`).
  """

  @type track :: %{
          required(:id) => String.t(),
          required(:title) => String.t(),
          required(:artist) => String.t(),
          required(:preview_url) => String.t() | nil,
          optional(:isrc) => String.t() | nil
        }

  @callback authorize_url(state :: String.t()) :: String.t()
  @callback fetch_token(code :: String.t()) :: {:ok, String.t()} | {:error, term()}
  @callback liked_tracks(token :: String.t()) :: {:ok, [track()]} | {:error, term()}
  @callback refresh_preview(token :: String.t(), track()) :: {:ok, track()} | {:error, term()}
end
