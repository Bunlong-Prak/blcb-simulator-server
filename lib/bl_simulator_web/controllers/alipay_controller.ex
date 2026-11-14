defmodule BlSimulatorWeb.AlipayController do
  use BlSimulatorWeb, :controller
  require Logger
  alias BlSimulatorWeb.ResponseFormatter

  @doc """
  Step 1: Decode QR code and get merchant information.
  Returns merchant details and paymentRequestId for the next step.
  """
  def user_initiated_pay(conn, params) when is_map(params) do
    with {:ok, validated_params} <- validate_user_initiated_params(params),
         qr_code <- get_qr_code_from_params(validated_params) do
      process_user_initiated_pay(conn, qr_code, validated_params)
    else
      {:error, message} ->
        Logger.warning("User initiated pay validation failed", error: message)
        ResponseFormatter.error_response(conn, 400, "VALIDATION_ERROR", message)
    end
  end

  @doc """
  Step 2: Process Alipay+ payment.
  Uses merchant info and payment details to complete transaction.
  """
  def push_payment(conn, params) when is_map(params) do
    with {:ok, validated_params} <- validate_push_payment_params(params),
         qr_code <- get_qr_code_from_params(validated_params),
         blcb_payment_id = generate_blcb_payment_id() do
      process_push_payment(conn, qr_code, validated_params, blcb_payment_id)
    else
      {:error, message} ->
        Logger.warning("Push payment validation failed", error: message)
        ResponseFormatter.error_response(conn, 400, "VALIDATION_ERROR", message)
    end
  end

  # Private functions

  defp validate_user_initiated_params(params) do
    qr_code = get_qr_code_from_params(params)

    cond do
      is_nil(qr_code) or qr_code == "" ->
        {:error, "QR code is required"}

      String.length(qr_code) < 10 ->
        {:error, "QR code appears to be invalid"}

      true ->
        {:ok, params}
    end
  end

  defp validate_push_payment_params(params) do
    qr_code = get_qr_code_from_params(params)

    cond do
      is_nil(qr_code) or qr_code == "" ->
        {:error, "QR code is required"}

      is_nil(params["amount"]) or params["amount"] == "0" or params["amount"] == "" ->
        {:error, "Payment amount is required"}

      is_nil(params["paymentRequestId"]) or params["paymentRequestId"] == "" ->
        {:error, "Payment request ID from userInitiatedPay is required"}

      not valid_amount?(params["amount"]) ->
        {:error, "Invalid payment amount format"}

      true ->
        {:ok, params}
    end
  end

  defp valid_amount?(amount) when is_binary(amount) do
    case Integer.parse(amount) do
      {num, ""} when num > 0 -> true
      _ -> false
    end
  end

  defp valid_amount?(amount) when is_integer(amount) and amount > 0, do: true
  defp valid_amount?(_), do: false

  defp process_user_initiated_pay(conn, qr_code, params) do
    alipay_payload =
      if has_alipay_fields?(params) do
        Map.put(params, "codeValue", qr_code)
      else
        build_alipay_user_initiated_payload(qr_code, params)
      end

    Logger.info("Calling Alipay userInitiatedPay",
      qr_code: String.slice(qr_code, 0, 20) <> "...",
      wallet_type: params["wallet_type"] || "unknown"
    )

    case BlSimulator.AlipayClient.user_initiated_pay(alipay_payload) do
      {:ok, response} ->
        result = response["result"]

        if result && Map.get(result, "resultStatus") == "F" do
          Logger.warning("Alipay userInitiatedPay reported functional failure (resultStatus: F)",
            result_code: Map.get(result, "resultCode")
          )

          error_response = format_alipay_error(response)
          display_message = error_response["details"] || "Alipay processing error"

          ResponseFormatter.error_response(
            conn,
            400,
            error_response["error_code"],
            display_message
          )
        else
          Logger.info("Alipay userInitiatedPay success")
          formatted_response = format_qr_decode_response(response)
          ResponseFormatter.success_response(conn, formatted_response)
        end

      {:error, status_code, error_body} when is_integer(status_code) ->
        Logger.warning("Alipay userInitiatedPay failed",
          status: status_code,
          error: error_body
        )

        error_response = format_alipay_error(error_body)
        user_message = error_response["message"] || "Alipay error"
        ResponseFormatter.error_response(conn, status_code, "ALIPAY_ERROR", user_message)

      {:error, :network_error, reason} ->
        Logger.error("Alipay network error", reason: reason)

        ResponseFormatter.error_response(
          conn,
          500,
          "NETWORK_ERROR",
          "Unable to connect to Alipay+ service"
        )
    end
  end

  defp process_push_payment(conn, qr_code, params, blcb_payment_id) do
    alipay_payload = build_alipay_push_payment_payload(qr_code, params, blcb_payment_id)

    Logger.info("Calling Alipay pushPayment",
      qr_code: String.slice(qr_code, 0, 20) <> "...",
      amount: params["amount"],
      wallet: params["wallet_type"] || "unknown"
    )

    case BlSimulator.AlipayClient.push_payment(alipay_payload) do
      {:ok, response} ->
        Logger.info("Alipay pushPayment success")
        formatted_response = format_payment_response(response, params)
        ResponseFormatter.success_response(conn, formatted_response)

      {:error, status_code, error_body} when is_integer(status_code) ->
        Logger.warning("Alipay pushPayment failed",
          status: status_code,
          error: error_body
        )

        error_response = format_alipay_error(error_body)
        ResponseFormatter.error_response(conn, status_code, "PAYMENT_FAILED", error_response)

      {:error, :network_error, reason} ->
        Logger.error("Alipay payment network error", reason: reason)

        ResponseFormatter.error_response(
          conn,
          500,
          "NETWORK_ERROR",
          "Unable to process payment - network error"
        )
    end
  end

  defp has_alipay_fields?(params) do
    Map.has_key?(params, "acquirerId") or
      Map.has_key?(params, "customerId") or
      Map.has_key?(params, "pspId")
  end

  defp build_alipay_user_initiated_payload(qr_code, params) do
    %{
      "acquirerId" => params["acquirer_id"] || "Z02TE1551000000A",
      "customerId" => params["customer_id"] || "09000003345935A1",
      "pspId" => params["psp_id"] || "",
      "codeValue" => qr_code
    }
  end

  defp build_alipay_push_payment_payload(qr_code, params, blcb_payment_id) do
    %{
      "acquirerId" => params["acquirer_id"] || "Z02TE1551000000A",
      "pspId" => params["psp_id"] || "102STANDARDPSP0020A",
      "codeValue" => qr_code,
      "customerId" => params["customer_id"] || "",
      "paymentRequestId" => params["paymentRequestId"],
      "paymentId" => blcb_payment_id,
      "mppPaymentId" => generate_mpp_payment_id(),
      "walletBrandName" => get_wallet_brand(params["walletBrandName"]),
      "paymentAmount" => %{
        "currency" => params["currency"] || "KHR",
        "value" => params["amount"]
      },
      "settlementAmount" => %{
        "value" => "",
        "currency" => ""
      },
      "paymentTime" => "",
      "settlementQuote" => %{
        "quoteCurrencyPair" => "",
        "quoteExpiryTime" => "",
        "quoteId" => "",
        "quotePrice" => "",
        "quoteStartTime" => ""
      }
    }
  end

  defp format_qr_decode_response(response) do
    %{
      "merchantName" =>
        get_in(response, ["merchant", "merchantName"]) ||
          get_in(response, ["order", "merchant", "merchantName"]) || "Unknown Merchant",
      "merchantMCC" =>
        get_in(response, ["merchant", "merchantMCC"]) ||
          get_in(response, ["order", "merchant", "merchantMCC"]) || "0000",
      "code_type" => response["codeType"] || "STORE_CODE",
      "is_dynamic" => response["codeType"] == "ORDER_CODE",
      "amount" => get_in(response, ["paymentAmount", "value"]),
      "currency" => get_in(response, ["paymentAmount", "currency"]) || "KHR",
      "paymentRequestId" => response["paymentRequestId"],
      "message" =>
        if(response["codeType"],
          do: "QR code decoded successfully",
          else: "Failed to decode QR code"
        )
    }
  end

  defp format_payment_response(response, params) do
    result = response["result"] || %{}

    %{
      "status" => if(result["resultStatus"] == "S", do: "success", else: "failed"),
      "transaction_id" => params["paymentRequestId"],
      "amount" => params["amount"],
      "fee" => 0,
      "deducted_amount" => params["amount"],
      "currency" => params["currency"] || "KHR",
      "merchantName" => params["merchantName"] || "Unknown",
      "wallet_type" => params["wallet_type"] || "alipay",
      "date" => response["paymentTime"] || DateTime.utc_now(),
      "result_code" => result["resultCode"],
      "message" =>
        case result["resultStatus"] do
          "S" -> "Payment completed successfully"
          "F" -> result["resultMessage"] || "Payment failed"
          "U" -> "Payment status unknown - please check again"
          _ -> "Payment processing error"
        end
    }
  end

  defp format_alipay_error(error_body) when is_map(error_body) do
    error_details = error_body["result"] || error_body

    %{
      "error_code" =>
        error_details["resultCode"] || error_details["errorCode"] || "UNKNOWN_ERROR",
      "message" => get_user_friendly_message(error_details),
      "details" =>
        error_details["resultMessage"] || error_details["message"] || "No details available"
    }
  end

  defp format_alipay_error(_),
    do: %{
      "error_code" => "UNKNOWN_ERROR",
      "message" => "An unexpected error occurred"
    }

  defp get_user_friendly_message(error_body) do
    error_code = error_body["resultCode"] || error_body["errorCode"]

    case error_code do
      "EXPIRED_CODE" -> "QR code has expired. Please generate a new one."
      "INVALID_CODE" -> "QR code is invalid or corrupted."
      "MERCHANT_NOT_REGISTERED" -> "Merchant is not registered for Alipay+ payments."
      "PAYMENT_AMOUNT_NOT_MET" -> "Payment amount does not meet the allowed limit."
      "PAYMENT_AMOUNT_INVALID" -> "Payment amount is invalid."
      "CURRENCY_NOT_SUPPORT" -> "Currency is not supported."
      "RISK_REJECT" -> "Payment rejected due to risk controls."
      _ -> error_body["resultMessage"] || error_body["message"] || "Payment processing failed"
    end
  end

  defp get_qr_code_from_params(params) do
    params["qr_code"] || params["codeValue"] || params["qrCode"] || ""
  end

  defp get_wallet_brand("alipay"), do: "Alipay"
  defp get_wallet_brand("alipay_plus"), do: "Alipay+"
  defp get_wallet_brand(_), do: "TEST_WALLET"

  defp generate_mpp_payment_id do
    timestamp = DateTime.utc_now() |> DateTime.to_unix()
    random = :rand.uniform(999_999)
    "MPP#{timestamp}#{random}"
  end

  defp generate_blcb_payment_id do
    timestamp = DateTime.utc_now() |> DateTime.to_unix()
    random = :rand.uniform(999_999)
    "BLCB#{timestamp}#{random}"
  end
end
