defmodule EloServerWeb.SyncController do
  use EloServerWeb, :controller

  alias EloServer.Sync

  def create(conn, params) do
    case Sync.apply_tournament(params) do
      {:ok, tournament} ->
        conn
        |> put_status(:created)
        |> json(%{short_name: tournament.short_name})

      {:error, :tournament_already_exists} ->
        conn
        |> put_status(:conflict)
        |> json(%{errors: %{detail: "Tournament already synced"}})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: %{detail: inspect(reason)}})
    end
  rescue
    error ->
      conn
      |> put_status(:unprocessable_entity)
      |> json(%{errors: %{detail: Exception.message(error)}})
  end

  def delete(conn, params) do
    short_name = Map.fetch!(params, "short_name")
    case Sync.remove_tournament(short_name) do
      {:ok, tournament} ->
        conn
        |> put_status(:ok)
        |> json(%{short_name: tournament.short_name})

      {:error, :tournament_not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{errors: %{detail: "Tournament not found"}})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: %{detail: inspect(reason)}})
    end
  rescue
    error ->
      conn
      |> put_status(:unprocessable_entity)
      |> json(%{errors: %{detail: Exception.message(error)}})
  end
end
