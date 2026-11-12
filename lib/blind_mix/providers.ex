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

  @doc "`{:ok, module}` seulement si le service existe ET a ses clés OAuth renseignées."
  def fetch_available(name) do
    with {:ok, provider} <- fetch(name),
         true <- provider.configured?() do
      {:ok, provider}
    else
      _ -> :error
    end
  end

  @doc "Vrai si le service peut être proposé au joueur."
  def available?(name), do: match?({:ok, _}, fetch_available(name))

  @doc "Vrai si toutes les `keys` de la config sont renseignées (ni absentes ni vides)."
  def present?(conf, keys) do
    Enum.all?(keys, fn key -> conf |> Keyword.get(key) |> filled?() end)
  end

  defp filled?(value) when is_binary(value), do: String.trim(value) != ""
  defp filled?(value), do: not is_nil(value)

  defp all, do: Map.merge(@providers, Application.get_env(:blind_mix, :extra_providers, %{}))
end
