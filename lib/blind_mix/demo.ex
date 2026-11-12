defmodule BlindMix.Demo do
  @moduledoc """
  Mode démo : aucun compte ni application OAuth. Les titres viennent du classement
  public de Deezer.

  Il passe par le même circuit que les vrais fournisseurs : `authorize_url/1` renvoie
  directement vers notre propre callback, qui vérifie le `state` comme d'habitude.
  Aucun changement de routes n'est donc nécessaire.
  """
  @behaviour BlindMix.Provider

  alias BlindMix.Deezer

  # Aucun compte nécessaire : toujours disponible.
  @impl true
  def configured?, do: true

  @impl true
  def authorize_url(state) do
    "/auth/demo/callback?" <> URI.encode_query(%{code: "demo", state: state})
  end

  @impl true
  def fetch_token("demo"), do: {:ok, "demo"}
  def fetch_token(_), do: {:error, :invalid_code}

  @impl true
  def liked_tracks(_token), do: Deezer.chart_tracks()

  # Les extraits Deezer sont publics : pas de jeton nécessaire.
  @impl true
  def refresh_preview(_token, track), do: Deezer.refresh_preview(nil, track)
end
