defmodule BlSimulatorWeb.UpiController do
  use BlSimulatorWeb, :controller
  require Logger
  alias BlSimulatorWeb.ResponseFormatter

  @doc """
  Step 1: Check if merchant is enabled/authorized to accept KHQR payments (via Bongloy API).
  """
  def check_merchant_status(conn, params) when is_map(params) do
    qr_code = get_qr_code_from_params(params)

    case validate_qr_code(qr_code) do
      :ok ->
        Logger.info("Checking merchant status", qr_code: String.slice(qr_code, 0, 20) <> "...")

        bongloy_payload = %{
          "data" => %{
            "qrCode" => qr_code
          }
        }

        case BlSimulator.BongloyClient.check_merchant_khqr_acceptance(bongloy_payload) do
          {:ok, %{"respCode" => "00000"} = response} ->
            data = response["data"] || %{}

            status_result = %{
              "is_enabled" => true,
              "merchant_status" => data["merchantStatus"] || "unknown",
              "currency" => get_in(data, ["maxPaymentAmount", "currency"]) || "KHR",
              "message" => "Merchant enabled"
            }

            Logger.info("Merchant status checked", enabled: true)
            ResponseFormatter.success_response(conn, status_result)

          {:ok, response} ->
            resp_code = response["respCode"] || "MERCHANT_CHECK_FAILED"
            Logger.warning("Merchant status check failed", resp_code: resp_code)
            error_msg = response["respMsg"] || "Cannot verify merchant status"
            ResponseFormatter.error_response(conn, 400, resp_code, error_msg)

          {:error, status_code, error_body} when is_integer(status_code) ->
            Logger.warning("Merchant status check HTTP error", error: error_body)
            ResponseFormatter.error_response(conn, status_code, "MERCHANT_CHECK_FAILED", "Cannot verify merchant")

          {:error, :network_error, reason} ->
            Logger.error("Merchant status check network error", reason: reason)
            ResponseFormatter.error_response(conn, 500, "NETWORK_ERROR", "Unable to connect to verification service")
        end

      {:error, reason} ->
        Logger.warning("Merchant status check validation failed", error: reason)
        ResponseFormatter.error_response(conn, 400, "VALIDATION_ERROR", reason)
    end
  end

  @doc """
  Step 2: Get QR code details and merchant information (via Bakong KHQR service).
  Determines whether QR is static or dynamic.
  """
  def get_qr_details(conn, params) when is_map(params) do
    qr_code = get_qr_code_from_params(params)

    case validate_qr_code(qr_code) do
      :ok ->
        Logger.info("Getting QR details for UnionPay flow", qr_code: String.slice(qr_code, 0, 20) <> "...")

        case BlSimulator.BakongClient.verify_merchant_khqr_acceptance(%{"qr_code" => qr_code}) do
          {:ok, response} ->
            data = response["data"] || %{}

            merchant_info = %{
              "merchantName" => data["merchantName"] || "Unknown Merchant",
              "destAccountId" => data["bakongAccountID"] || "",
              "amount" => data["transactionAmount"],
              "is_dynamic" => not is_nil(data["transactionAmount"])
            }

            Logger.info("QR details retrieved successfully", merchant: merchant_info["merchantName"])
            ResponseFormatter.success_response(conn, merchant_info)

          {:error, status, error} when is_integer(status) ->
            Logger.warning("Invalid QR code", error: error)
            ResponseFormatter.error_response(conn, status, "INVALID_QR", "QR code is invalid or expired")

          {:error, :network_error, reason} ->
            Logger.error("Bakong decode network error", reason: reason)
            ResponseFormatter.error_response(conn, 500, "NETWORK_ERROR", "Unable to connect to QR service")
        end

      {:error, reason} ->
        Logger.warning("Get QR details validation failed", error: reason)
        ResponseFormatter.error_response(conn, 400, "VALIDATION_ERROR", reason)
    end
  end

  @doc """
  Step 3: Process UnionPay payment for the given KHQR transaction.
  """
  def process_payment(conn, params) when is_map(params) do
    with {:ok, qr_code} <- validate_payment_qr(params),
         {:ok, amount} <- validate_payment_amount(params["amount"]) do
      merchant_name = params["merchantName"] || "Unknown Merchant"
      txn_ref_id = generate_transaction_id()

      Logger.info("Processing UnionPay payment", amount: amount, txn_ref: txn_ref_id)

      upi_payload = %{
        "data" => %{
          "acctIdOUT" => params["account_from"] || "blcbkhppxxx@blcb",
          "txnRefId" => txn_ref_id,
          "assetId" => params["currency"] || "KHR",
          "destAccountId" => params["destAccountId"] || "",
          "note" => params["note"] || "BL Simulator Payment",
          "txnAt" => amount,
          "qrCode" => qr_code
        }
      }

      case BlSimulator.UpiClient.upi_incoming_khqr_txn(upi_payload) do
        {:ok, %{"respCode" => "00000"}} ->
          Logger.info("UnionPay payment successful", txn_ref: txn_ref_id)

          payment_result = %{
            "merchantName" => merchant_name,
            "amount" => amount,
            "fromAccount" => params["account_from"] || "blcbkhppxxx@blcb",
            "paywith" => "bakong khqr",
            "fee" => "0",
            "deducedAmount" => amount,
            "txn.status" => "success",
            "txnRefId" => txn_ref_id,
            "currency" => params["currency"] || "KHR",
            "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
            "message" => "Payment completed successfully"
          }

          ResponseFormatter.success_response(conn, payment_result)

        {:ok, response} ->
          resp_code = extract_error_code(response)
          Logger.warning("UnionPay payment functional failure", resp_code: resp_code)

          error_result = %{
            "status" => "failed",
            "error_code" => resp_code,
            "message" => extract_error_message(response)
          }

          ResponseFormatter.error_response(conn, 400, "PAYMENT_FAILED", error_result)

        {:error, status_code, error_body} when is_integer(status_code) ->
          Logger.warning("UnionPay payment HTTP error", status: status_code, error: error_body)

          error_result = %{
            "status" => "failed",
            "error_code" => extract_error_code(error_body),
            "message" => extract_error_message(error_body)
          }

          ResponseFormatter.error_response(conn, status_code, "PAYMENT_FAILED", error_result)

        {:error, :network_error, reason} ->
          Logger.error("UnionPay payment network error", reason: reason)

          error_result = %{
            "status" => "failed",
            "error_code" => "NETWORK_ERROR",
            "message" => "Unable to connect to payment service"
          }

          ResponseFormatter.error_response(conn, 500, "NETWORK_ERROR", error_result)
      end
    else
      {:error, reason} ->
        Logger.warning("UnionPay payment validation failed", error: reason)
        ResponseFormatter.error_response(conn, 400, "VALIDATION_ERROR", reason)
    end
  end

  # Helper functions

  defp get_qr_code_from_params(params) do
    params["qr_code"] || params["codeValue"] || params["qrcode"] || params["qrCode"] || ""
  end

  defp validate_qr_code(qr_code) when is_binary(qr_code) do
    cond do
      qr_code == "" -> {:error, "QR code is required"}
      String.length(qr_code) < 10 -> {:error, "QR code appears to be invalid"}
      true -> :ok
    end
  end

  defp validate_qr_code(_), do: {:error, "QR code is required"}

  defp validate_payment_qr(params) do
    qr_code = get_qr_code_from_params(params)
    case validate_qr_code(qr_code) do
      :ok -> {:ok, qr_code}
      error -> error
    end
  end

  defp validate_payment_amount(amount) when is_binary(amount) do
    case Integer.parse(amount) do
      {num, ""} when num > 0 -> {:ok, amount}
      _ -> {:error, "Payment amount must be a positive number"}
    end
  end

  defp validate_payment_amount(amount) when is_integer(amount) and amount > 0 do
    {:ok, Integer.to_string(amount)}
  end

  defp validate_payment_amount(_), do: {:error, "Payment amount is required"}

  defp generate_transaction_id do
    timestamp = System.system_time(:millisecond)
    random = :crypto.strong_rand_bytes(4) |> Base.encode16()
    "TXN#{timestamp}#{random}"
  end

  defp extract_error_code(error_body) when is_map(error_body) do
    error_body["respCode"] || error_body["errorCode"] || "UNKNOWN_ERROR"
  end

  defp extract_error_code(_), do: "UNKNOWN_ERROR"

  defp extract_error_message(error_body) when is_map(error_body) do
    error_body["respMsg"] || error_body["message"] || "Payment failed"
  end

  defp extract_error_message(_), do: "Payment failed"
end
