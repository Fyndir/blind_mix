defmodule BlindMix.ProviderConfig do
  @moduledoc """
  Aide de test : change la config Deezer / Spotify et la restaure à la fin du test.
  À utiliser seulement dans des tests `async: false` (la config est globale).
  """
  import ExUnit.Callbacks, only: [on_exit: 1]

  @keys [:deezer, :spotify]

  def put(service, conf) when service in @keys do
    previous = Application.get_env(:blind_mix, service)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:blind_mix, service, previous),
        else: Application.delete_env(:blind_mix, service)
    end)

    Application.put_env(:blind_mix, service, conf)
  end

  def configure_all do
    put(:deezer, app_id: "dz_id", secret: "dz_secret", redirect_uri: "http://x/deezer")

    put(:spotify,
      client_id: "sp_id",
      client_secret: "sp_secret",
      redirect_uri: "http://x/spotify"
    )
  end

  def unconfigure_all do
    put(:deezer, app_id: nil, secret: "")
    put(:spotify, client_id: nil, client_secret: nil)
  end
end
