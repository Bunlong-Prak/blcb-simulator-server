defmodule BlSimulatorWeb.AlipayControllerTest do
  use BlSimulatorWeb.ConnCase, async: false

  setup do
    Tesla.Mock.mock(fn env ->
      cond do
        String.contains?(env.url, "userInitiatedPay") ->
          case Jason.decode!(env.body) do
            %{"codeValue" => "FAIL_QR_CODE_123"} ->
              %Tesla.Env{
                status: 200,
                body: %{
                  "result" => %{
                    "resultStatus" => "F",
                    "resultCode" => "INVALID_CODE",
                    "resultMessage" => "The code is invalid."
                  }
                }
              }

            _ ->
              %Tesla.Env{
                status: 200,
                body: %{
                  "merchant" => %{
                    "merchantName" => "Angkor Mart",
                    "merchantMCC" => "5411"
                  },
                  "codeType" => "STORE_CODE",
                  "paymentAmount" => %{
                    "value" => "15000",
                    "currency" => "KHR"
                  },
                  "paymentRequestId" => "REQ_987654321"
                }
              }
          end

        String.contains?(env.url, "pushPayments/pay") ->
          case Jason.decode!(env.body) do
            %{"paymentRequestId" => "FAIL_REQ_ID"} ->
              %Tesla.Env{
                status: 400,
                body: %{
                  "result" => %{
                    "resultStatus" => "F",
                    "resultCode" => "PAYMENT_AMOUNT_NOT_MET",
                    "resultMessage" => "Amount below limit"
                  }
                }
              }

            _ ->
              %Tesla.Env{
                status: 200,
                body: %{
                  "result" => %{
                    "resultStatus" => "S",
                    "resultCode" => "SUCCESS"
                  },
                  "paymentTime" => "2026-11-14T07:12:00Z"
                }
              }
          end
      end
    end)

    :ok
  end

  describe "POST /api/payments/userInitiatedPay" do
    test "validates missing qr_code", %{conn: conn} do
      conn = post(conn, ~p"/api/payments/userInitiatedPay", %{})

      assert json_response(conn, 400)["status"]["message"] == "QR code is required"
    end

    test "validates short/invalid qr_code", %{conn: conn} do
      conn = post(conn, ~p"/api/payments/userInitiatedPay", %{"qr_code" => "short"})

      assert json_response(conn, 400)["status"]["message"] == "QR code appears to be invalid"
    end

    test "decodes valid QR code successfully", %{conn: conn} do
      payload = %{
        "qr_code" => "00020101021230testqrcontent",
        "wallet_type" => "alipay"
      }

      conn = post(conn, ~p"/api/payments/userInitiatedPay", payload)
      body = json_response(conn, 200)

      assert body["merchantName"] == "Angkor Mart"
      assert body["merchantMCC"] == "5411"
      assert body["paymentRequestId"] == "REQ_987654321"
      assert body["currency"] == "KHR"
      assert body["is_dynamic"] == false
    end

    test "handles functional failure from upstream", %{conn: conn} do
      payload = %{
        "qr_code" => "FAIL_QR_CODE_123"
      }

      conn = post(conn, ~p"/api/payments/userInitiatedPay", payload)
      body = json_response(conn, 400)

      assert body["status"]["code"] == "INVALID_CODE"
      assert body["status"]["message"] == "The code is invalid."
    end
  end

  describe "POST /api/pushPayments/pay" do
    test "validates missing payment fields", %{conn: conn} do
      conn = post(conn, ~p"/api/pushPayments/pay", %{"qr_code" => "00020101021230testqrcontent"})
      assert json_response(conn, 400)["status"]["message"] == "Payment amount is required"

      conn =
        post(conn, ~p"/api/pushPayments/pay", %{
          "qr_code" => "00020101021230testqrcontent",
          "amount" => "10000"
        })

      assert json_response(conn, 400)["status"]["message"] ==
               "Payment request ID from userInitiatedPay is required"

      conn =
        post(conn, ~p"/api/pushPayments/pay", %{
          "qr_code" => "00020101021230testqrcontent",
          "amount" => "invalid_amount",
          "paymentRequestId" => "REQ_123"
        })

      assert json_response(conn, 400)["status"]["message"] == "Invalid payment amount format"
    end

    test "processes payment successfully", %{conn: conn} do
      payload = %{
        "qr_code" => "00020101021230testqrcontent",
        "amount" => "15000",
        "currency" => "KHR",
        "paymentRequestId" => "REQ_987654321",
        "merchantName" => "Angkor Mart",
        "wallet_type" => "alipay"
      }

      conn = post(conn, ~p"/api/pushPayments/pay", payload)
      body = json_response(conn, 200)

      assert body["status"] == "success"
      assert body["transaction_id"] == "REQ_987654321"
      assert body["amount"] == "15000"
      assert body["merchantName"] == "Angkor Mart"
      assert body["result_code"] == "SUCCESS"
    end

    test "handles upstream push payment failure", %{conn: conn} do
      payload = %{
        "qr_code" => "00020101021230testqrcontent",
        "amount" => "50",
        "paymentRequestId" => "FAIL_REQ_ID"
      }

      conn = post(conn, ~p"/api/pushPayments/pay", payload)
      body = json_response(conn, 400)

      assert body["status"]["code"] == "PAYMENT_FAILED"
    end
  end
end
