# defmodule BlSimulatorWeb.UpiController do
#   use BlSimulatorWeb, :controller
#   require Logger
#   alias BlSimulatorWeb.ResponseFormatter

#   @doc """
#   Get QR code details for UnionPay flow
#   Frontend calls this first to get merchant info and determine if QR is static/dynamic
#   """

#   # Step 1: Check if merchant is enabled/authorized (Bongloy API)
#   # Frontend calls this first to validate merchant status

#   def check_merchant_status(conn, params) do
#     qr_code = get_qr_code_from_params(params)

#     Logger.info("Checking merchant status", qr_code: String.slice(qr_code, 0, 20) <> "...")

#     bongloy_payload = %{
#       "data" => %{
#         "qrCode" => qr_code
#       }
#     }

#     case BlSimulator.BongloyClient.check_merchant_khqr_acceptance(bongloy_payload) do
#       {:ok, response} ->
#         data = response["data"] || %{}

#         # Clean response for frontend
#         status_result = %{
#           "is_enabled" => response["respCode"] == "00000",
#           "merchant_status" => data["merchantStatus"] || "unknown",
#           # "max_payment_amount" => get_in(data, ["maxPaymentAmount", "value"]),
#           # "min_payment_amount" => get_in(data, ["minPaymentAmount", "value"]),
#           "currency" => get_in(data, ["maxPaymentAmount", "currency"]) || "KHR",
#           "message" =>
#             if(response["respCode"] == "00000", do: "Merchant enabled", else: response["respMsg"])
#         }

#         Logger.info("Merchant status checked", enabled: status_result["is_enabled"])
#         ResponseFormatter.success_response(conn, status_result)

#       {:error, status_code, error_body} ->
#         Logger.warning("Merchant status check failed", error: error_body)

#         ResponseFormatter.error_response(
#           conn,
#           status_code,
#           "MERCHANT_CHECK_FAILED",
#           "Cannot verify merchant"
#         )
#     end
#   end

#   def get_qr_details(conn, params) do
#     qr_code = get_qr_code_from_params(params)

#     Logger.info("Getting QR details for UnionPay flow",
#       qr_code: String.slice(qr_code, 0, 20) <> "..."
#     )

#     case BlSimulator.BakongClient.verify_merchant_khqr_acceptance(%{"qr_code" => qr_code}) do
#       {:ok, response} ->
#         data = response["data"] || %{}

#         # Clean response for frontend
#         merchant_info = %{
#           "merchantName" => data["merchantName"] || "Unknown Merchant",
#           # "merchant_id" => data["merchantID"] || "N/A",
#           # "currency" => parse_currency(data["transactionCurrency"]),
#           # null for static QR, value for dynamic QR
#           "destAccountId" => data["bakongAccountID"] || "",
#           "amount" => data["transactionAmount"],
#           "is_dynamic" => !is_nil(data["transactionAmount"])
#           # "DeducedAmount" => data["transactionAmount"]
#           # "max_amount" => data["maxAmount"] || "999999999", # (take tis or nah?)
#           # "store_label" => data["storeLabel"] || ""
#         }

#         Logger.info("QR details retrieved successfully", merchant: merchant_info["merchantName"])
#         ResponseFormatter.success_response(conn, merchant_info)

#       {:error, status, error} ->
#         Logger.warning("Invalid QR code", error: error)

#         ResponseFormatter.error_response(
#           conn,
#           status,
#           "INVALID_QR",
#           "QR code is invalid or expired"
#         )
#     end
#   end

#   @doc """
#   Process UnionPay payment
#   Frontend calls this after user confirms payment details
#   """
#   def process_payment(conn, params) do
#     qr_code = get_qr_code_from_params(params)
#     amount = params["amount"] || "0"
#     merchantName = params["merchantName"] || "Unknown Merchant"
#     destAccountId = params["bakongAccountID"]
#     txn_ref_id = generate_transaction_id()

#     Logger.info("Processing UnionPay payment", amount: amount)

#     upi_payload = %{
#       "data" => %{
#         "acctIdOUT" => params["account_from"] || "blcbkhppxxx@blcb",
#         # || timestamp  this right or nah??
#         "txnRefId" => txn_ref_id,
#         "assetId" => params["currency"] || "KHR",
#         "destAccountId" => params["destAccountId"] || "",
#         "note" => params["note"] || "BL Simulator Payment",
#         "txnAt" => amount,
#         "qrCode" => qr_code
#       }
#     }

#     case BlSimulator.UpiClient.upi_incoming_khqr_txn(upi_payload) do
#       {:ok, _response} ->
#         Logger.info("UnionPay payment successful", txn_ref: txn_ref_id)

#         payment_result = %{
#           "merchantName" => merchantName,
#           "amount" => amount,
#           "fromAccount" => "...",
#           "paywith" => "bakong khqr",
#           "fee" => "0",
#           "deducedAmount" => amount,
#           "txn.status" => "success",
#           "txnRefId" => txn_ref_id,
#           # "currency" => params["currency"] || "KHR",
#           "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
#           "message" => "Payment completed successfully"
#         }

#         ResponseFormatter.success_response(conn, payment_result)

#       {:error, status_code, error_body} when is_integer(status_code) ->
#         Logger.warning("UnionPay payment failed", status: status_code, error: error_body)

#         error_result = %{
#           "status" => "failed",
#           "error_code" => extract_error_code(error_body),
#           "message" => extract_error_message(error_body)
#         }

#         ResponseFormatter.error_response(conn, status_code, "PAYMENT_FAILED", error_result)

#       {:error, :network_error, reason} ->
#         Logger.error("UnionPay network error", reason: reason)

#         error_result = %{
#           "status" => "failed",
#           "error_code" => "NETWORK_ERROR",
#           "message" => "Unable to connect to payment service"
#         }

#         ResponseFormatter.error_response(conn, 500, "NETWORK_ERROR", error_result)
#     end
#   end

#   # Helper functions
#   defp get_qr_code_from_params(params) do
#     params["qr_code"] || params["codeValue"] || params["qrcode"] || params["qrCode"] || ""
#   end

#   defp generate_transaction_id do
#     timestamp = System.system_time(:millisecond)
#     random = :crypto.strong_rand_bytes(4) |> Base.encode16()
#     "TXN#{timestamp}#{random}"
#   end

#   defp extract_error_code(error_body) when is_map(error_body) do
#     error_body["respCode"] || error_body["errorCode"] || "UNKNOWN_ERROR"
#   end

#   defp extract_error_code(_), do: "UNKNOWN_ERROR"

#   defp extract_error_message(error_body) when is_map(error_body) do
#     error_body["respMsg"] || error_body["message"] || "Payment failed"
#   end

#   defp extract_error_message(_), do: "Payment failed"
# end
defmodule BlSimulatorWeb.UpiController do
  use BlSimulatorWeb, :controller
  require Logger
  alias BlSimulatorWeb.ResponseFormatter

  @doc """
  Get QR code details for UnionPay flow
  Frontend calls this first to get merchant info and determine if QR is static/dynamic
  """

  # Step 1: Check if merchant is enabled/authorized (Bongloy API)
  def check_merchant_status(conn, params) do
    qr_code = get_qr_code_from_params(params)

    Logger.info("Checking merchant status", qr_code: String.slice(qr_code, 0, 20) <> "...")

    bongloy_payload = %{
      "data" => %{
        "qrCode" => qr_code
      }
    }

    case BlSimulator.BongloyClient.check_merchant_khqr_acceptance(bongloy_payload) do
      {:ok, response} ->
        # NEW LOGIC: Check upstream respCode for functional errors
        if response["respCode"] == "00000" do
          data = response["data"] || %{}
          # Clean response for frontend
          status_result = %{
            "is_enabled" => true,
            "merchant_status" => data["merchantStatus"] || "unknown",
            "currency" => get_in(data, ["maxPaymentAmount", "currency"]) || "KHR",
            "message" => "Merchant enabled"
          }

          Logger.info("Merchant status checked", enabled: status_result["is_enabled"])
          ResponseFormatter.success_response(conn, status_result)
        else
          # Handle functional error returned in a 200 OK response
          Logger.warning("Merchant status check failed (respCode: #{response["respCode"]})")
          error_msg = response["respMsg"] || "Cannot verify merchant status"
          ResponseFormatter.error_response(conn, 400, response["respCode"], error_msg)
        end

      # END NEW LOGIC

      {:error, status_code, error_body} ->
        Logger.warning("Merchant status check failed (HTTP Error)", error: error_body)

        ResponseFormatter.error_response(
          conn,
          status_code,
          "MERCHANT_CHECK_FAILED",
          "Cannot verify merchant"
        )
    end
  end

  def get_qr_details(conn, params) do
    qr_code = get_qr_code_from_params(params)

    Logger.info("Getting QR details for UnionPay flow",
      qr_code: String.slice(qr_code, 0, 20) <> "..."
    )

    case BlSimulator.BakongClient.verify_merchant_khqr_acceptance(%{"qr_code" => qr_code}) do
      {:ok, response} ->
        data = response["data"] || %{}

        # Clean response for frontend
        merchant_info = %{
          "merchantName" => data["merchantName"] || "Unknown Merchant",
          # "merchant_id" => data["merchantID"] || "N/A",
          # "currency" => parse_currency(data["transactionCurrency"]),
          # null for static QR, value for dynamic QR
          "destAccountId" => data["bakongAccountID"] || "",
          "amount" => data["transactionAmount"],
          "is_dynamic" => !is_nil(data["transactionAmount"])
          # "DeducedAmount" => data["transactionAmount"]
          # "max_amount" => data["maxAmount"] || "999999999", # (take tis or nah?)
          # "store_label" => data["storeLabel"] || ""
        }

        Logger.info("QR details retrieved successfully", merchant: merchant_info["merchantName"])
        ResponseFormatter.success_response(conn, merchant_info)

      {:error, status, error} ->
        Logger.warning("Invalid QR code", error: error)

        ResponseFormatter.error_response(
          conn,
          status,
          "INVALID_QR",
          "QR code is invalid or expired"
        )
    end
  end

  #         conn,
  #         status,
  #         "INVALID_QR",
  #         "QR code is invalid or expired"
  #       )
  #   end
  # end

  @doc """
  Process UnionPay payment
  Frontend calls this after user confirms payment details
  """
  def process_payment(conn, params) do
    qr_code = get_qr_code_from_params(params)
    amount = params["amount"] || "0"
    merchantName = params["merchantName"] || "Unknown Merchant"
    # destAccountId is not used, but let's keep the parameter access for context
    # destAccountId = params["bakongAccountID"]
    txn_ref_id = generate_transaction_id()

    Logger.info("Processing UnionPay payment", amount: amount)

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
      {:ok, response} ->
        # NEW LOGIC: Check upstream respCode for functional errors
        resp_code = response["respCode"]

        if resp_code == "00000" do
          # SUCCESS PATH
          Logger.info("UnionPay payment successful", txn_ref: txn_ref_id)

          payment_result = %{
            "merchantName" => merchantName,
            "amount" => amount,
            "fromAccount" => "...",
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
        else
          # FAILURE PATH: Upstream returned an error (e.g., "00001", "00099") in a 200 OK response
          Logger.warning("UnionPay payment failed (respCode: #{resp_code})",
            error_msg: response["respMsg"]
          )

          error_result = %{
            "status" => "failed",
            "error_code" => extract_error_code(response),
            "message" => extract_error_message(response)
          }

          # Use HTTP 400 for functional validation failures
          ResponseFormatter.error_response(conn, 400, "PAYMENT_FAILED", error_result)
        end

      # END NEW LOGIC

      {:error, status_code, error_body} when is_integer(status_code) ->
        # EXISTING LOGIC: Handles true HTTP errors (4xx, 5xx) from the client
        Logger.warning("UnionPay payment failed (HTTP Error)",
          status: status_code,
          error: error_body
        )

        error_result = %{
          "status" => "failed",
          "error_code" => extract_error_code(error_body),
          "message" => extract_error_message(error_body)
        }

        ResponseFormatter.error_response(conn, status_code, "PAYMENT_FAILED", error_result)

      {:error, :network_error, reason} ->
        Logger.error("UnionPay network error", reason: reason)

        error_result = %{
          "status" => "failed",
          "error_code" => "NETWORK_ERROR",
          "message" => "Unable to connect to payment service"
        }

        ResponseFormatter.error_response(conn, 500, "NETWORK_ERROR", error_result)
    end
  end

  # Helper functions (No changes needed here, they correctly extract details from the error map)
  defp get_qr_code_from_params(params) do
    params["qr_code"] || params["codeValue"] || params["qrcode"] || params["qrCode"] || ""
  end

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
