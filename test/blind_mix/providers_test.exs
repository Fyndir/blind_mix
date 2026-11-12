defmodule BlindMix.ProvidersTest do
  use ExUnit.Case, async: false

  alias BlindMix.Providers

  test "retrouve les fournisseurs connus" do
    assert {:ok, BlindMix.Deezer} = Providers.fetch("deezer")
    assert {:ok, BlindMix.Spotify} = Providers.fetch("spotify")
  end

  test "le mode démo passe par le même circuit OAuth sans compte" do
    assert {:ok, BlindMix.Demo} = Providers.fetch("demo")

    url = BlindMix.Demo.authorize_url("abc")
    assert url =~ "/auth/demo/callback"
    assert url =~ "state=abc"

    assert {:ok, "demo"} = BlindMix.Demo.fetch_token("demo")
    assert {:error, :invalid_code} = BlindMix.Demo.fetch_token("autre")
  end

  test "refuse un fournisseur inconnu" do
    assert :error = Providers.fetch("napster")
    assert :error = Providers.fetch(nil)
  end

  test "les URL d'autorisation contiennent le state et le bon client" do
    Application.put_env(:blind_mix, :spotify,
      client_id: "sp_id",
      client_secret: "sp_secret",
      redirect_uri: "http://127.0.0.1:4000/auth/spotify/callback"
    )

    Application.put_env(:blind_mix, :deezer,
      app_id: "dz_id",
      secret: "dz_secret",
      redirect_uri: "http://127.0.0.1:4000/auth/deezer/callback"
    )

    spotify = BlindMix.Spotify.authorize_url("abc")
    assert spotify =~ "accounts.spotify.com/authorize"
    assert spotify =~ "client_id=sp_id"
    assert spotify =~ "state=abc"
    assert spotify =~ "user-library-read"

    deezer = BlindMix.Deezer.authorize_url("abc")
    assert deezer =~ "connect.deezer.com/oauth/auth.php"
    assert deezer =~ "app_id=dz_id"
    assert deezer =~ "state=abc"
  end
end
