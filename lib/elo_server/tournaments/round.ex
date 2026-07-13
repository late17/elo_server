defmodule EloServer.Tournaments.Round do
  use Ecto.Schema

  @primary_key {:id, :binary_id, source: :ID}
  schema "Round" do
    field :type, :string, source: :Type
    field :number, :integer, source: :Number

    belongs_to :tournament, EloServer.Tournaments.Tournament,
      foreign_key: :tournament_id,
      source: :TournamentId,
      references: :id,
      type: :binary_id

    has_many :games, EloServer.Games.Game, foreign_key: :round_id
  end
end
