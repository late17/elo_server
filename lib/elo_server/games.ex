defmodule EloServer.Games do
  @moduledoc """
  Read-only access to debate games (the four teams competing in a round).
  """

  import Ecto.Query

  alias EloServer.Repo
  alias EloServer.Games.Game

  def list_games_for_round(round_id) do
    Game
    |> where(round_id: ^round_id)
    |> preload([:og_team, :oo_team, :cg_team, :co_team])
    |> Repo.all()
  end

  def get_game!(id) do
    Game
    |> preload([:round, :og_team, :oo_team, :cg_team, :co_team])
    |> Repo.get!(id)
  end
end
