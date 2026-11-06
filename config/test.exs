import Config

# Load environment variables from .env (if present), same as config/dev.exs,
# so local DB credentials don't need to be hardcoded or committed.
env_path = Path.expand("../.env", __DIR__)

if File.exists?(env_path) do
  env_path
  |> File.read!()
  |> String.split("\n", trim: true)
  |> Enum.each(fn line ->
    line = String.trim(line)

    case line do
      "#" <> _ ->
        :ok

      "" ->
        :ok

      _ ->
        case String.split(line, "=", parts: 2) do
          [key, value] -> System.put_env(String.trim(key), String.trim(value))
          _ -> :ok
        end
    end
  end)
end

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :elo_server, EloServer.Repo,
  username: System.get_env("DB_USERNAME", "postgres"),
  password: System.get_env("DB_PASSWORD", "postgres"),
  hostname: System.get_env("DB_HOST", "localhost"),
  database: "elo_server_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :elo_server, EloServerWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "ELZj+NE1tyfshnqxHLVeeb56tM49OaGLJx5aanWXvTCkW3Y6pHP7bBhou5ubSf85",
  server: false

# In test we don't send emails
config :elo_server, EloServer.Mailer, adapter: Swoosh.Adapters.Test

# Fixed token for the sync API in tests
config :elo_server, :sync_token, "test-sync-token"

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
