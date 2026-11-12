defmodule BlindMix.ProvidersTest do
  use ExUnit.Case, async: false

  alias BlindMix.{ProviderConfig, Providers}

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
    ProviderConfig.put(:spotify,
      client_id: "sp_id",
      client_secret: "sp_secret",
      redirect_uri: "http://127.0.0.1:4000/auth/spotify/callback"
    )

    ProviderConfig.put(:deezer,
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

  describe "services sans clés OAuth" do
    test "un service sans clés n'est pas disponible" do
      ProviderConfig.unconfigure_all()

      refute Providers.available?("deezer")
      refute Providers.available?("spotify")
      assert :error = Providers.fetch_available("deezer")
      # Le mode démo n'a besoin d'aucune clé.
      assert Providers.available?("demo")
    end

    test "les deux clés sont nécessaires, une chaîne vide compte comme absente" do
      ProviderConfig.put(:deezer, app_id: "dz_id", secret: "  ")
      refute Providers.available?("deezer")

      ProviderConfig.put(:spotify, client_id: "sp_id", client_secret: "sp_secret")
      assert {:ok, BlindMix.Spotify} = Providers.fetch_available("spotify")
    end

    test "un service inconnu n'est jamais disponible" do
      refute Providers.available?("napster")
      refute Providers.available?(nil)
    end
  end
end
