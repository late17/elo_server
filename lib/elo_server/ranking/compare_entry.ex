defmodule EloServer.Ranking.CompareEntry do
  @moduledoc """
  One player's movement between two points in time (`start_boundary` and
  `end_boundary`), reconstructed by subtracting/summing per-tournament elo
  diffs backwards from the player's current elo.
  """

  defstruct [
    :player_id,
    :player_name,
    :elo_start,
    :elo_end,
    :elo_delta,
    :rank_start,
    :rank_end,
    :rank_delta,
    :games_start,
    :games_end,
    :games_in_span,
    # :both | :new | :disappeared
    :status
  ]
end
