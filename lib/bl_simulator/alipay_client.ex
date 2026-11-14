defmodule BlSimulator.AlipayClient do
  @moduledoc """
  Tesla HTTP client for calling Alipay+ APIs
  """
  use Tesla

  plug Tesla.Middleware.BaseUrl, Application.get_env(:bl_simulator, :alipay_base_url)
  plug Tesla.Middleware.JSON
  plug Tesla.Middleware.Headers, [{"content-type", "application/json"}]
  plug Tesla.Middleware.Timeout, timeout: 30_000

  @doc """
  Initiates user-initiated pay (QR decode) call to Alipay+.
  """
  @spec user_initiated_pay(map()) :: {:ok, map()} | {:error, integer() | :network_error, any()}
  def user_initiated_pay(payload) do
    post("/payments/userInitiatedPay", payload)
    |> handle_response()
  end

  @doc """
  Initiates push payment call to Alipay+.
  """
  @spec push_payment(map()) :: {:ok, map()} | {:error, integer() | :network_error, any()}
  def push_payment(payload) do
    post("/pushPayments/pay", payload)
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
