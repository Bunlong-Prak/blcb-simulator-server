defmodule BlSimulator.UpiClient do
  @moduledoc """
  Tesla HTTP client for calling real Alipay+ APIs
  """
  use Tesla

  plug Tesla.Middleware.BaseUrl, Application.get_env(:bl_simulator, :upi_base_url)
  plug Tesla.Middleware.JSON
  plug Tesla.Middleware.Headers, [{"content-type", "application/json"}]
  plug Tesla.Middleware.Timeout, timeout: 30_000

  def upi_incoming_khqr_txn(payload) do
    post("/temp/upiIncomingKhqrTxn", payload)
    |> handle_response()
  end

  defp handle_response({:ok, %Tesla.Env{status: status, body: body}}) when status in 200..299 do
    {:ok, body}
  end

  defp handle_response({:ok, %Tesla.Env{status: status, body: body}}) do
    {:error, status, body}
  end

  defp handle_response({:error, reason}) do
    {:error, :network_error, reason}
  end
end
