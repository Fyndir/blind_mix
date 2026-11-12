defmodule BlindMixWeb.PageController do
  use BlindMixWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
