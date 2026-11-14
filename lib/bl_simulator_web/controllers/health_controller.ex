defmodule BlSimulatorWeb.HealthController do
  use BlSimulatorWeb, :controller

  def check(conn, _params) do
    version =
      case Application.spec(:bl_simulator, :vsn) do
        vsn when is_list(vsn) -> to_string(vsn)
        vsn when is_binary(vsn) -> vsn
        _ -> "unknown"
      end

    json(conn, %{
      "status" => "healthy",
      "service" => "bl_simulator",
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "version" => version
    })
  end
end
