defmodule BlSimulatorWeb.HealthControllerTest do
  use BlSimulatorWeb.ConnCase, async: true

  describe "GET /api/health" do
    test "returns healthy status and service info", %{conn: conn} do
      conn = get(conn, ~p"/api/health")

      assert json_response(conn, 200) =~ "healthy"
      body = json_response(conn, 200)

      assert body["status"] == "healthy"
      assert body["service"] == "bl_simulator"
      assert is_binary(body["timestamp"])
      assert is_binary(body["version"])
    end
  end
end
