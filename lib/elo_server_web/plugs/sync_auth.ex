defmodule EloServerWeb.Plugs.SyncAuth do
  @moduledoc """
  Authenticates requests to the SYNC API via a shared-secret bearer token,
  configured as `config :elo_server, :sync_token`.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    expected_token = Application.fetch_env!(:elo_server, :sync_token)

    with [header] <- get_req_header(conn, "authorization"),
         "Bearer " <> token <- header,
         true <- Plug.Crypto.secure_compare(token, expected_token) do
      conn
    else
      _ ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(401, Jason.encode!(%{errors: %{detail: "Unauthorized"}}))
        |> halt()
    end
  end
end
