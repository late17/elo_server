defmodule EloServer.Players.Player do
  use Ecto.Schema

  @primary_key {:id, :binary_id, source: :ID}
  schema "Player" do
    field :name, :string, source: :Name
    field :is_tech_team, :boolean, source: :isTechTeam
    field :elo, :float, source: :ELO
    field :map_names, :string, source: :mapNames
    field :games_played, :integer, source: :gamesPlayed

    has_many :player_in_tournaments, EloServer.Players.PlayerInTournament,
      foreign_key: :player_id
  end
end
