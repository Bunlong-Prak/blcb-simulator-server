defmodule BlSimulatorWeb.HealthController do
  use BlSimulatorWeb, :controller

  def check(conn, _params) do
    json(conn, %{
      "status" => "healthy",
      "service" => "bl_simulator",
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "version" => Application.spec(:bl_simulator, :vsn) || "unknown"
    })
  end
end
