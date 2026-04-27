defmodule EloServer.Repo do
  use Ecto.Repo,
    otp_app: :elo_server,
    adapter: Ecto.Adapters.Postgres
end
