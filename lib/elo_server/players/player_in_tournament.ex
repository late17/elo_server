defmodule EloServer.Players.PlayerInTournament do
  use Ecto.Schema

  @primary_key {:id, :binary_id, source: :ID}
  schema "PlayerInTournament" do
    field :name_in_tournament, :string, source: :NameInTournament

    belongs_to :team, EloServer.Tournaments.Team,
      foreign_key: :team_id,
      source: :TeamIdInTournament,
      references: :id,
      type: :binary_id

    belongs_to :player, EloServer.Players.Player,
      foreign_key: :player_id,
      source: :PlayerId,
      references: :id,
      type: :binary_id
  end
end
