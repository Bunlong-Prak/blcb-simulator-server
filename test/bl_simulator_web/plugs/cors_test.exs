defmodule BlSimulatorWeb.Plugs.CORSTest do
  use BlSimulatorWeb.ConnCase, async: true

  describe "CORS Plug" do
    test "handles OPTIONS preflight requests", %{conn: conn} do
      conn =
        conn
        |> put_req_header("access-control-request-method", "POST")
        |> options(~p"/api/health")

      assert conn.status == 200
      assert get_resp_header(conn, "access-control-allow-origin") == ["*"]
      assert get_resp_header(conn, "access-control-allow-methods") == ["GET, POST, PUT, DELETE, OPTIONS"]
      assert get_resp_header(conn, "access-control-allow-headers") == ["Content-Type, Authorization, X-Requested-With"]
      assert get_resp_header(conn, "access-control-max-age") == ["3600"]
      assert conn.halted
    end

    test "injects CORS headers into API responses", %{conn: conn} do
      conn = get(conn, ~p"/api/health")

      assert conn.status == 200
      assert get_resp_header(conn, "access-control-allow-origin") == ["*"]
      assert get_resp_header(conn, "access-control-allow-methods") == ["GET, POST, PUT, DELETE, OPTIONS"]
    end
  end
end
