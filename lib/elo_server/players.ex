defmodule EloServer.Players do
  @moduledoc """
  Read-only access to players and their tournament participation.
  """

  import Ecto.Query

  alias EloServer.Repo
  alias EloServer.Players.{Player, PlayerInTournament}

  def list_players do
    Player
    |> order_by(desc: :elo)
    |> Repo.all()
  end

  def get_player!(id), do: Repo.get!(Player, id)

  def list_players_in_tournament(tournament_id) do
    PlayerInTournament
    |> join(:inner, [pit], t in assoc(pit, :team))
    |> where([pit, t], t.tournament_id == ^tournament_id)
    |> preload([pit, t], player: [], team: [])
    |> Repo.all()
  end
end
