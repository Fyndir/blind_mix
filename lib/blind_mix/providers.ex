defmodule BlindMix.Providers do
  @moduledoc "Registre des services de connexion OAuth 2 disponibles."

  @providers %{
    "deezer" => BlindMix.Deezer,
    "spotify" => BlindMix.Spotify,
    "demo" => BlindMix.Demo
  }

  @doc "`{:ok, module}` ou `:error` pour un nom inconnu."
  def fetch(name) when is_binary(name), do: Map.fetch(@providers, name)
  def fetch(_), do: :error

  def names, do: Map.keys(@providers)
end
