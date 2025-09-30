defmodule BlSimulator.Repo do
  use Ecto.Repo,
    otp_app: :bl_simulator,
    adapter: Ecto.Adapters.Postgres
end
