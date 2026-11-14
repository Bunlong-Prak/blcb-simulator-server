defmodule BlSimulatorWeb.Router do
  use BlSimulatorWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {BlSimulatorWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug BlSimulatorWeb.Plugs.CORS
  end

  scope "/", BlSimulatorWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  scope "/api", BlSimulatorWeb do
    pipe_through :api

    get "/health", HealthController, :check

    # Alipay Flow
    # Step 1: Decode QR
    post "/payments/userInitiatedPay", AlipayController, :user_initiated_pay
    # Step 2: Process Payment
    post "/pushPayments/pay", AlipayController, :push_payment

    # UnionPay flow
    # Step 1 Verify merchant enabled
    post "/unionpay/check-merchant", UpiController, :check_merchant_status
    # Step 2 Get merchant details
    post "/qr/details", UpiController, :get_qr_details
    # Step 3 Process payment
    post "/unionpay/payment", UpiController, :process_payment
  end
end

