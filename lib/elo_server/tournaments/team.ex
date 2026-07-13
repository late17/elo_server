defmodule EloServer.Tournaments.Team do
  use Ecto.Schema

  @primary_key {:id, :binary_id, source: :ID}
  schema "Team" do
    field :name, :string, source: :Name

    belongs_to :tournament, EloServer.Tournaments.Tournament,
      foreign_key: :tournament_id,
      source: :TournamentId,
      references: :id,
      type: :binary_id

    has_many :players_in_tournament, EloServer.Players.PlayerInTournament,
      foreign_key: :team_id
  end
end
