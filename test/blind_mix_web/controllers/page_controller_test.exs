defmodule BlindMixWeb.PageControllerTest do
  use BlindMixWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Blind test multi-pistes"
  end
end
