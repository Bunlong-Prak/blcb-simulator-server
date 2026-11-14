defmodule BlSimulator.BakongClient do
  @moduledoc """
  Tesla HTTP client for calling Bakong KHQR verification & decode APIs
  """
  use Tesla

  plug Tesla.Middleware.BaseUrl, Application.get_env(:bl_simulator, :bakong_base_url)
  plug Tesla.Middleware.JSON
  plug Tesla.Middleware.Headers, [{"content-type", "application/json"}]
  plug Tesla.Middleware.Timeout, timeout: 30_000

  @doc """
  Verifies and decodes a Bakong KHQR string.
  """
  @spec verify_merchant_khqr_acceptance(map()) :: {:ok, map()} | {:error, integer() | :network_error, any()}
  def verify_merchant_khqr_acceptance(payload) do
    post("/bakong-khqr/verify-and-decode", payload)
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
