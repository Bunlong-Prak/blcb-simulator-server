# BLCB Simulator Server

[![Elixir CI](https://img.shields.io/badge/Elixir-1.14+-purple.svg)](https://elixir-lang.org/)
[![Phoenix Framework](https://img.shields.io/badge/Phoenix-1.7-orange.svg)](https://phoenixframework.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

**BLCB Simulator Server** (Bongloy Cross-Border Simulator Server) is a high-performance backend application built with [Elixir](https://elixir-lang.org/) and [Phoenix](https://phoenixframework.org/). It serves as an API gateway and payment simulator proxy for testing and orchestrating cross-border mobile QR payment workflows across **Alipay+**, **UnionPay International (UPI)**, and Cambodia's **Bakong KHQR** ecosystem (via Bongloy verification).

---

## Table of Contents

- [Overview](#overview)
- [Architecture & Key Features](#architecture--key-features)
- [Supported Payment Flows](#supported-payment-flows)
  - [1. Alipay+ Flow](#1-alipay-flow)
  - [2. UnionPay (UPI) & Bakong KHQR Flow](#2-unionpay-upi--bakong-khqr-flow)
- [API Reference](#api-reference)
  - [System Health](#system-health)
  - [Alipay+ Endpoints](#alipay-endpoints)
  - [UnionPay & KHQR Endpoints](#unionpay--khqr-endpoints)
- [Configuration & Environment Variables](#configuration--environment-variables)
- [Getting Started](#getting-started)
  - [Prerequisites](#prerequisites)
  - [Installation & Setup](#installation--setup)
  - [Running the Server](#running-the-server)
- [Project Structure](#project-structure)
- [Error Handling & Response Format](#error-handling--response-format)

---

## Overview

In cross-border payment integration, testing mobile wallets against different switch networks (such as Alipay+ and UnionPay International) requires coordinating multi-step transactions: decoding QR codes, verifying merchant eligibility against national switches (e.g. Bakong KHQR), and pushing payment authorizations.

BLCB Simulator Server acts as a central proxy and formatting layer that:
- Normalizes disparate upstream API formats into consistent client-friendly responses.
- Simulates and validates static and dynamic QR transactions.
- Handles functional failure mapping (e.g. invalid QR, expired QR, unauthorized merchant, risk rejection).
- Provides pre-configured CORS support for web and mobile simulator frontend interfaces.

---

## Architecture & Key Features

- **Built with Phoenix 1.7 & Bandit**: Lightning-fast, lightweight HTTP handling using Bandit and Elixir's OTP concurrency model.
- **Resilient Upstream Clients**: Modular Tesla HTTP clients with configurable timeouts, JSON serialization, and centralized error logging:
  - `BlSimulator.AlipayClient`: Communicates with Alipay+ APIs.
  - `BlSimulator.BongloyClient`: Verifies merchant eligibility through Bongloy verification services.
  - `BlSimulator.BakongClient`: Decodes and verifies Bakong KHQR payload specifications.
  - `BlSimulator.UpiClient`: Interacts with UnionPay International (UPI) incoming KHQR switch endpoints.
- **Clean Response Standardization**: `BlSimulatorWeb.ResponseFormatter` ensures unified response envelopes and structured error messages across all endpoints.
- **Zero-Friction CORS**: Integrated plug supporting preflight and cross-origin requests for frontends running on different ports or domains.

---

## Supported Payment Flows

### 1. Alipay+ Flow

```
[ Client / Frontend ]                [ BLCB Simulator ]                  [ Alipay+ Switch ]
         |                                   |                                   |
         |--- 1. POST /payments/userInitiatedPay ->|                                   |
         |    (Pass QR code)                 |--- Forward to Alipay+ ----------->|
         |                                   |<-- Decoded Merchant & Request ID -|
         |<-- Normalized Merchant Info ------|                                   |
         |                                   |                                   |
         |--- 2. POST /pushPayments/pay ---->|                                   |
         |    (Payment details & req ID)     |--- Generate IDs & Push Payment -->|
         |                                   |<-- Upstream Result ---------------|
         |<-- Final Transaction Status ------|                                   |
```

### 2. UnionPay (UPI) & Bakong KHQR Flow

```
[ Client / Frontend ]         [ BLCB Simulator ]       [ Bongloy API ]    [ Bakong Service ]    [ UPI Switch ]
         |                            |                       |                  |                   |
         |-- 1. check-merchant ------>|                       |                  |                   |
         |   (Verify acceptance)      |-- Verify merchant --->|                  |                   |
         |                            |<-- Status (OK/Err) ---|                  |                   |
         |<-- Merchant Enabled -------|                                          |                   |
         |                            |                                          |                   |
         |-- 2. qr/details ---------->|                                          |                   |
         |   (Decode KHQR)            |-- Verify & Decode ---------------------->|                   |
         |                            |<-- Merchant name, account, dynamic flag -|                   |
         |<-- Parsed QR Details ------|                                                              |
         |                            |                                                              |
         |-- 3. unionpay/payment ---->|                                                              |
         |   (Process payment)        |-- Push incoming KHQR transaction --------------------------->|
         |                            |<-- Settlement confirmation ----------------------------------|
         |<-- Payment Success --------|                                                              |
```

---

## API Reference

All API routes are served under `/api` and expect/return `application/json`.

### System Health

#### `GET /api/health`
Checks server health, uptime timestamp, and running version.

**Response (200 OK):**
```json
{
  "status": "healthy",
  "service": "bl_simulator",
  "timestamp": "2026-11-14T07:05:00Z",
  "version": "0.1.0"
}
```

---

### Alipay+ Endpoints

#### 1. Decode QR (`POST /api/payments/userInitiatedPay`)
Decodes user-presented or merchant-presented QR codes to retrieve merchant data and obtain a `paymentRequestId`.

**Request Body:**
```json
{
  "qr_code": "00020101021230...",
  "wallet_type": "alipay",
  "acquirer_id": "Z02TE1551000000A",
  "customer_id": "09000003345935A1",
  "psp_id": ""
}
```

**Success Response (200 OK):**
```json
{
  "merchantName": "Khmer Coffee & Bakery",
  "merchantMCC": "5812",
  "code_type": "STORE_CODE",
  "is_dynamic": false,
  "amount": "12000",
  "currency": "KHR",
  "paymentRequestId": "2026111410000001",
  "message": "QR code decoded successfully"
}
```

#### 2. Process Payment (`POST /api/pushPayments/pay`)
Executes the push payment transaction using the `paymentRequestId` from Step 1.

**Request Body:**
```json
{
  "qr_code": "00020101021230...",
  "amount": "12000",
  "currency": "KHR",
  "paymentRequestId": "2026111410000001",
  "merchantName": "Khmer Coffee & Bakery",
  "wallet_type": "alipay",
  "walletBrandName": "alipay"
}
```

**Success Response (200 OK):**
```json
{
  "status": "success",
  "transaction_id": "2026111410000001",
  "amount": "12000",
  "fee": 0,
  "deducted_amount": "12000",
  "currency": "KHR",
  "merchantName": "Khmer Coffee & Bakery",
  "wallet_type": "alipay",
  "date": "2026-11-14T07:05:20Z",
  "result_code": "SUCCESS",
  "message": "Payment completed successfully"
}
```

---

### UnionPay & KHQR Endpoints

#### 1. Check Merchant Status (`POST /api/unionpay/check-merchant`)
Validates whether the merchant represented in the KHQR is registered and authorized to accept cross-border payments.

**Request Body:**
```json
{
  "qr_code": "00020101021230..."
}
```

**Success Response (200 OK):**
```json
{
  "is_enabled": true,
  "merchant_status": "ACTIVE",
  "currency": "KHR",
  "message": "Merchant enabled"
}
```

#### 2. Get QR Details (`POST /api/qr/details`)
Decodes the Bakong KHQR to extract merchant account information, destination account, and transaction amount (if dynamic QR).

**Request Body:**
```json
{
  "qr_code": "00020101021230..."
}
```

**Success Response (200 OK):**
```json
{
  "merchantName": "Phnom Penh Mart",
  "destAccountId": "merchant@acleda",
  "amount": "25000",
  "is_dynamic": true
}
```

#### 3. Execute UnionPay Payment (`POST /api/unionpay/payment`)
Submits the incoming KHQR transaction through the UnionPay International switch.

**Request Body:**
```json
{
  "qr_code": "00020101021230...",
  "amount": "25000",
  "currency": "KHR",
  "merchantName": "Phnom Penh Mart",
  "destAccountId": "merchant@acleda",
  "account_from": "blcbkhppxxx@blcb",
  "note": "Lunch order #42"
}
```

**Success Response (200 OK):**
```json
{
  "merchantName": "Phnom Penh Mart",
  "amount": "25000",
  "fromAccount": "...",
  "paywith": "bakong khqr",
  "fee": "0",
  "deducedAmount": "25000",
  "txn.status": "success",
  "txnRefId": "TXN1763103900000ABCD",
  "currency": "KHR",
  "timestamp": "2026-11-14T07:05:45Z",
  "message": "Payment completed successfully"
}
```

---

## Configuration & Environment Variables

All external base URLs and runtime secrets are managed via `config/runtime.exs` and can be set using environment variables:

| Variable | Description | Default |
| :--- | :--- | :--- |
| `PORT` | Port the Phoenix server binds to | `4000` |
| `ALIPAY_BASE_URL` | Base URL for Alipay+ upstream service | `http://localhost:4002` |
| `BONGLOY_BASE_URL` | Base URL for Bongloy merchant verification API | `https://verify.bongloy.asia` |
| `BAKONG_BASE_URL` | Base URL for Bakong KHQR verification & decode | `http://172.168.253.12:8000` |
| `UPI_URL` | Base URL for UnionPay International (UPI) switch | `http://localhost:4003` |
| `DATABASE_URL` | PostgreSQL connection URL *(production)* | `ecto://postgres:postgres@localhost/bl_simulator_dev` |
| `SECRET_KEY_BASE` | Phoenix secret key base *(production)* | Generated via `mix phx.gen.secret` |
| `PHX_SERVER` | Set to `true` to run the endpoint when using releases | `nil` |

---

## Getting Started

### Prerequisites

- **Elixir**: 1.14 or newer
- **Erlang/OTP**: 25 or newer
- **PostgreSQL**: 14 or newer (for Ecto repository)
- **Node.js** (optional, only if modifying dev frontend assets)

### Installation & Setup

1. **Clone the repository:**
   ```bash
   git clone https://github.com/Bunlong-Prak/blcb-simulator-server.git
   cd blcb-simulator-server
   ```

2. **Install dependencies:**
   ```bash
   mix deps.get
   ```

3. **Set up database:**
   ```bash
   mix ecto.setup
   ```

### Running the Server

Start the Phoenix server:
```bash
mix phx.server
```

Or start inside interactive Elixir shell (IEx):
```bash
iex -S mix phx.server
```

The simulator will be available at `http://localhost:4000`. You can test the health endpoint immediately:
```bash
curl http://localhost:4000/api/health
```

---

## Project Structure

```text
blcb-simulator-server/
├── config/
│   ├── config.exs             # General app configuration
│   ├── dev.exs                # Development environment settings
│   ├── prod.exs               # Production environment settings
│   └── runtime.exs            # Dynamic runtime env variables & upstream URLs
├── lib/
│   ├── bl_simulator/
│   │   ├── alipay_client.ex   # Tesla client for Alipay+ APIs
│   │   ├── bakong_client.ex   # Tesla client for Bakong KHQR decode APIs
│   │   ├── bongloy_client.ex  # Tesla client for Bongloy verification APIs
│   │   ├── upi_client.ex      # Tesla client for UnionPay switch APIs
│   │   ├── application.ex     # OTP Application supervisor
│   │   └── repo.ex            # Ecto Repo module
│   └── bl_simulator_web/
│       ├── controllers/
│       │   ├── alipay_controller.ex  # Alipay+ multi-step flow controller
│       │   ├── upi_controller.ex     # UnionPay/KHQR flow controller
│       │   └── health_controller.ex  # Service health check controller
│       ├── plugs/
│       │   └── cors.ex               # Permissive CORS plug for simulator UIs
│       ├── response_formatter.ex     # Consistent JSON success/error envelopes
│       ├── router.ex                 # API and browser routing definitions
│       └── endpoint.ex               # Phoenix endpoint configuration
└── mix.exs                    # Elixir application configuration & dependencies
```

---

## Error Handling & Response Format

When validation fails or an upstream service returns an error, the simulator returns consistent error envelopes with relevant HTTP status codes:

```json
{
  "status": {
    "code": "VALIDATION_ERROR",
    "message": "QR code is required"
  }
}
```

Common upstream error codes mapped to user-friendly messages:
- `INVALID_CODE`: QR code is invalid or corrupted.
- `EXPIRED_CODE`: QR code has expired.
- `MERCHANT_NOT_REGISTERED`: Merchant is not registered for cross-border acceptance.
- `PAYMENT_AMOUNT_INVALID`: Payment amount format is invalid or below limit.
- `NETWORK_ERROR`: Unable to connect to upstream switch or service.

---

## License

This project is licensed under the [MIT License](LICENSE).
