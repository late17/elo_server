defmodule EloServer.Tournaments.Tournament do
  use Ecto.Schema

  @primary_key {:id, :binary_id, source: :ID}
  schema "Tournament" do
    field :name, :string, source: :Name
    field :short_name, :string
    field :date, :date
    field :semi_final, :boolean
    field :novice_final, :boolean
    field :junior_final, :boolean
    field :final, :boolean

    has_many :rounds, EloServer.Tournaments.Round, foreign_key: :tournament_id
    has_many :teams, EloServer.Tournaments.Team, foreign_key: :tournament_id
  end
end
