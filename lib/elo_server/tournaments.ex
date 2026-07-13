defmodule EloServer.Tournaments do
  @moduledoc """
  Read-only access to tournaments, rounds, and teams.
  """

  import Ecto.Query

  alias EloServer.Repo
  alias EloServer.Tournaments.{Tournament, Round, Team}

  def list_tournaments do
    Tournament
    |> order_by(desc: :date)
    |> Repo.all()
  end

  def get_tournament!(id), do: Repo.get!(Tournament, id)

  def list_rounds(tournament_id) do
    Round
    |> where(tournament_id: ^tournament_id)
    |> order_by(asc: :number)
    |> Repo.all()
  end

  def list_teams(tournament_id) do
    Team
    |> where(tournament_id: ^tournament_id)
    |> Repo.all()
  end
end
