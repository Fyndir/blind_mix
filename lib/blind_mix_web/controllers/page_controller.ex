defmodule BlindMixWeb.PageController do
  use BlindMixWeb, :controller

  alias BlindMix.Providers

  def home(conn, _params) do
    render(conn, :home,
      provider: get_session(conn, :provider),
      # Seuls les services dont les clés OAuth sont renseignées sont proposés.
      spotify?: Providers.available?("spotify"),
      deezer?: Providers.available?("deezer")
    )
  end
end
