defmodule BlSimulatorWeb.UpiControllerTest do
  use BlSimulatorWeb.ConnCase, async: false

  setup do
    Tesla.Mock.mock(fn env ->
      cond do
        String.contains?(env.url, "checkMerchantKHQRAcceptance") ->
          case Jason.decode!(env.body) do
            %{"data" => %{"qrCode" => "DISABLED_MERCHANT_QR"}} ->
              %Tesla.Env{
                status: 200,
                body: %{
                  "respCode" => "00001",
                  "respMsg" => "Merchant not eligible for cross-border transactions"
                }
              }

            _ ->
              %Tesla.Env{
                status: 200,
                body: %{
                  "respCode" => "00000",
                  "data" => %{
                    "merchantStatus" => "ACTIVE",
                    "maxPaymentAmount" => %{"currency" => "KHR", "value" => "10000000"}
                  }
                }
              }
          end

        String.contains?(env.url, "verify-and-decode") ->
          case Jason.decode!(env.body) do
            %{"qr_code" => "EXPIRED_QR_CODE_123"} ->
              %Tesla.Env{
                status: 400,
                body: %{"error" => "Expired KHQR"}
              }

            _ ->
              %Tesla.Env{
                status: 200,
                body: %{
                  "data" => %{
                    "merchantName" => "Siem Reap Mart",
                    "bakongAccountID" => "siemreap@acleda",
                    "transactionAmount" => "25000"
                  }
                }
              }
          end

        String.contains?(env.url, "upiIncomingKhqrTxn") ->
          case Jason.decode!(env.body) do
            %{"data" => %{"txnAt" => "999999999"}} ->
              %Tesla.Env{
                status: 200,
                body: %{
                  "respCode" => "00099",
                  "respMsg" => "Exceeds maximum allowable balance"
                }
              }

            _ ->
              %Tesla.Env{
                status: 200,
                body: %{
                  "respCode" => "00000",
                  "respMsg" => "Success"
                }
              }
          end
      end
    end)

    :ok
  end

  describe "POST /api/unionpay/check-merchant" do
    test "validates missing qr_code", %{conn: conn} do
      conn = post(conn, ~p"/api/unionpay/check-merchant", %{})

      assert json_response(conn, 400)["status"]["message"] == "QR code is required"
    end

    test "validates short qr_code", %{conn: conn} do
      conn = post(conn, ~p"/api/unionpay/check-merchant", %{"qr_code" => "short"})

      assert json_response(conn, 400)["status"]["message"] == "QR code appears to be invalid"
    end

    test "returns enabled merchant status successfully", %{conn: conn} do
      payload = %{"qr_code" => "00020101021230testqrcontent"}
      conn = post(conn, ~p"/api/unionpay/check-merchant", payload)
      body = json_response(conn, 200)

      assert body["is_enabled"] == true
      assert body["merchant_status"] == "ACTIVE"
      assert body["currency"] == "KHR"
      assert body["message"] == "Merchant enabled"
    end

    test "handles disabled merchant response", %{conn: conn} do
      payload = %{"qr_code" => "DISABLED_MERCHANT_QR"}
      conn = post(conn, ~p"/api/unionpay/check-merchant", payload)
      body = json_response(conn, 400)

      assert body["status"]["code"] == "00001"
      assert body["status"]["message"] == "Merchant not eligible for cross-border transactions"
    end
  end

  describe "POST /api/qr/details" do
    test "validates missing qr_code", %{conn: conn} do
      conn = post(conn, ~p"/api/qr/details", %{})

      assert json_response(conn, 400)["status"]["message"] == "QR code is required"
    end

    test "returns decoded KHQR details", %{conn: conn} do
      payload = %{"qr_code" => "00020101021230testqrcontent"}
      conn = post(conn, ~p"/api/qr/details", payload)
      body = json_response(conn, 200)

      assert body["merchantName"] == "Siem Reap Mart"
      assert body["destAccountId"] == "siemreap@acleda"
      assert body["amount"] == "25000"
      assert body["is_dynamic"] == true
    end

    test "handles invalid/expired KHQR upstream error", %{conn: conn} do
      payload = %{"qr_code" => "EXPIRED_QR_CODE_123"}
      conn = post(conn, ~p"/api/qr/details", payload)
      body = json_response(conn, 400)

      assert body["status"]["code"] == "INVALID_QR"
      assert body["status"]["message"] == "QR code is invalid or expired"
    end
  end

  describe "POST /api/unionpay/payment" do
    test "validates missing or invalid payment parameters", %{conn: conn} do
      conn = post(conn, ~p"/api/unionpay/payment", %{"amount" => "25000"})
      assert json_response(conn, 400)["status"]["message"] == "QR code is required"

      conn =
        post(conn, ~p"/api/unionpay/payment", %{
          "qr_code" => "00020101021230testqrcontent",
          "amount" => "0"
        })

      assert json_response(conn, 400)["status"]["message"] ==
               "Payment amount must be a positive number"
    end

    test "processes UnionPay payment successfully", %{conn: conn} do
      payload = %{
        "qr_code" => "00020101021230testqrcontent",
        "amount" => "25000",
        "currency" => "KHR",
        "merchantName" => "Siem Reap Mart",
        "destAccountId" => "siemreap@acleda"
      }

      conn = post(conn, ~p"/api/unionpay/payment", payload)
      body = json_response(conn, 200)

      assert body["merchantName"] == "Siem Reap Mart"
      assert body["amount"] == "25000"
      assert body["txn.status"] == "success"
      assert String.starts_with?(body["txnRefId"], "TXN")
      assert body["message"] == "Payment completed successfully"
    end

    test "handles upstream UPI payment failure", %{conn: conn} do
      payload = %{
        "qr_code" => "00020101021230testqrcontent",
        "amount" => "999999999"
      }

      conn = post(conn, ~p"/api/unionpay/payment", payload)
      body = json_response(conn, 400)

      assert body["status"]["code"] == "PAYMENT_FAILED"
    end
  end
end
