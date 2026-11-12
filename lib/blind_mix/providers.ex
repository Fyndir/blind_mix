defmodule BlindMix.Providers do
  @moduledoc """
  Registre des services de connexion OAuth 2 disponibles.

  `config :blind_mix, :extra_providers, %{"nom" => Module}` en ajoute d'autres
  (utilisé par les tests pour un faux service sans réseau).
  """

  @providers %{
    "deezer" => BlindMix.Deezer,
    "spotify" => BlindMix.Spotify,
    "demo" => BlindMix.Demo
  }

  @doc "`{:ok, module}` ou `:error` pour un nom inconnu."
  def fetch(name) when is_binary(name), do: Map.fetch(all(), name)
  def fetch(_), do: :error

  def names, do: Map.keys(all())

  defp all, do: Map.merge(@providers, Application.get_env(:blind_mix, :extra_providers, %{}))
end
