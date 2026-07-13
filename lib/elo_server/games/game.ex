defmodule EloServer.Games.Game do
  use Ecto.Schema

  @primary_key {:id, :binary_id, source: :ID}
  schema "Game" do
    field :is_eliminating, :boolean, source: :isEliminating
    # JSON-encoded seat placement / results, e.g. finishing order of the four teams
    field :places, :string, source: :Places
    # JSON-encoded snapshot of player ELOs / deltas at the time of the game
    field :players_elos, :string, source: :playersElos
    field :players_elo_diff, :string, source: :playersEloDiff
    field :game_type, :string, source: :gameType

    belongs_to :round, EloServer.Tournaments.Round,
      foreign_key: :round_id,
      source: :RoundId,
      references: :id,
      type: :binary_id

    belongs_to :og_team, EloServer.Tournaments.Team,
      foreign_key: :og_team_id,
      source: :OG,
      references: :id,
      type: :binary_id

    belongs_to :oo_team, EloServer.Tournaments.Team,
      foreign_key: :oo_team_id,
      source: :OO,
      references: :id,
      type: :binary_id

    belongs_to :cg_team, EloServer.Tournaments.Team,
      foreign_key: :cg_team_id,
      source: :CG,
      references: :id,
      type: :binary_id

    belongs_to :co_team, EloServer.Tournaments.Team,
      foreign_key: :co_team_id,
      source: :CO,
      references: :id,
      type: :binary_id
  end
end
