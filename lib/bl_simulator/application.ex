defmodule BlSimulator.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      BlSimulatorWeb.Telemetry,
      BlSimulator.Repo,
      {DNSCluster, query: Application.get_env(:bl_simulator, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: BlSimulator.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: BlSimulator.Finch},
      # Start a worker by calling: BlSimulator.Worker.start_link(arg)
      # {BlSimulator.Worker, arg},
      # Start to serve requests, typically the last entry
      BlSimulatorWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: BlSimulator.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    BlSimulatorWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
