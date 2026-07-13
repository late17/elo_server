defmodule EloServer.Ranking.Entry do
  @moduledoc """
  One row in the current player rating, with movement relative to the
  standings before the most recent tournament.
  """

  defstruct [
    :rank,
    :player_id,
    :player_name,
    :games_played,
    :elo,
    :elo_change,
    :rank_change
  ]
end
