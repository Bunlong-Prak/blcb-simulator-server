defmodule BlSimulatorWeb.ResponseFormatter do
  @moduledoc """
  Simple response formatter that passes through API responses without modification.
  Only adds error formatting for network/connection issues.
  """

  import Plug.Conn
  import Phoenix.Controller

  def success_response(conn, data) do
    # Pass through the actual API response without wrapping
    json(conn, data)
  end

  def error_response(conn, http_status, error_code, message) do
    response = %{
      "status" => %{
        "code" => error_code,
        "message" => message
      }
    }

    conn
    |> put_status(http_status)
    |> json(response)
  end
end
