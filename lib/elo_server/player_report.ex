defmodule EloServer.PlayerReport do
  @moduledoc """
  Builds a single player's report: profile stats plus their full game
  history (one row per game they played in, newest first).
  """

  import Ecto.Query

  alias EloServer.Repo
  alias EloServer.Games.{Game, PlayerElos, RoomResults}
  alias EloServer.Players.{Player, PlayerInTournament}
  alias EloServer.Tournaments.{Round, Tournament}

  @position_order [:og, :oo, :cg, :co]

  defmodule GameEntry do
    @moduledoc "One row in a player's game history."
    defstruct [
      :tournament_name,
      :tournament_date,
      :round_type,
      :round_number,
      :seat,
      :result,
      :elo_before,
      :elo_diff
    ]
  end

  @doc """
  Returns `%{player: %Player{}, games: [%GameEntry{}]}` for `player_id`, or
  `nil` if no such player exists.
  """
  def get(player_id) do
    case Repo.get(Player, player_id) do
      nil -> nil
      player -> %{player: player, games: game_history(player_id)}
    end
  end

  defp game_history(player_id) do
    team_ids_by_pit =
      PlayerInTournament
      |> where(player_id: ^player_id)
      |> Repo.all()
      |> Map.new(&{&1.team_id, &1})

    team_ids = Map.keys(team_ids_by_pit)

    games =
      Game
      |> where(
        [g],
        g.og_team_id in ^team_ids or g.oo_team_id in ^team_ids or
          g.cg_team_id in ^team_ids or g.co_team_id in ^team_ids
      )
      |> join(:inner, [g], r in Round, on: r.id == g.round_id)
      |> join(:inner, [g, r], t in Tournament, on: t.id == r.tournament_id)
      |> select([g, r, t], %{game: g, round: r, tournament: t})
      |> Repo.all()

    all_team_ids = games |> Enum.map(& &1.game) |> team_ids_for_games()

    teammates_by_team =
      PlayerInTournament
      |> where([pit], pit.team_id in ^all_team_ids)
      |> Repo.all()
      |> Enum.group_by(& &1.team_id)

    games
    |> Enum.map(fn %{game: game, round: round, tournament: tournament} ->
      build_entry(game, round, tournament, team_ids_by_pit, teammates_by_team)
    end)
    |> Enum.sort_by(&{Date.to_erl(&1.tournament_date), &1.round_number}, :desc)
  end

  defp team_ids_for_games(games) do
    games
    |> Enum.flat_map(&[&1.og_team_id, &1.oo_team_id, &1.cg_team_id, &1.co_team_id])
    |> Enum.uniq()
  end

  defp build_entry(game, round, tournament, team_ids_by_pit, teammates_by_team) do
    team_by_position = %{
      og: game.og_team_id,
      oo: game.oo_team_id,
      cg: game.cg_team_id,
      co: game.co_team_id
    }

    {seat, team_id} =
      Enum.find(team_by_position, fn {_pos, team_id} -> Map.has_key?(team_ids_by_pit, team_id) end)

    slot = Enum.find_index(@position_order, &(&1 == seat))

    own_pit = Map.fetch!(team_ids_by_pit, team_id)

    within_team_index =
      teammates_by_team
      |> Map.get(team_id, [])
      |> Enum.find_index(&(&1.id == own_pit.id))

    index = slot * 2 + (within_team_index || 0)

    elos = PlayerElos.parse(game.players_elos)
    diffs = PlayerElos.parse(game.players_elo_diff)
    elo_after = Enum.at(elos, index, 0.0)
    elo_diff = Enum.at(diffs, index, 0.0)

    %GameEntry{
      tournament_name: tournament.name,
      tournament_date: tournament.date,
      round_type: round.type,
      round_number: round.number,
      seat: seat,
      result: result_for(game, seat),
      elo_before: elo_after - elo_diff,
      elo_diff: elo_diff
    }
  end

  defp result_for(game, seat) do
    position_to_team_id = %{
      og: game.og_team_id,
      oo: game.oo_team_id,
      cg: game.cg_team_id,
      co: game.co_team_id
    }

    team_id = Map.fetch!(position_to_team_id, seat)

    case RoomResults.decode(game.places, position_to_team_id) do
      %RoomResults.ByPlace{places: places} ->
        Enum.find_value(places, fn {place, tid} -> tid == team_id && place end)

      %RoomResults.ByAdvancing{groups: groups} ->
        cond do
          team_id in groups.advancing -> :advancing
          team_id in groups.eliminated -> :eliminated
          true -> nil
        end
    end
  end
end
