defmodule EloServer.Ranking do
  @moduledoc """
  Computes the current player rating, along with each player's movement
  (elo change, rank change) caused by the most recent tournament.

  Mirrors the original Kotlin computation: elo/rank *before* the last
  tournament is reconstructed by subtracting that tournament's per-player
  elo diff from the player's current elo, then the two orderings (before vs.
  after) are compared to derive rank movement.
  """

  import Ecto.Query

  alias EloServer.Repo
  alias EloServer.Ranking.Entry
  alias EloServer.Tournaments.{Tournament, Round, Team}
  alias EloServer.Players.{Player, PlayerInTournament}
  alias EloServer.Games.{Game, PlayerElos}

  @min_games 20
  @active_within_days 365

  def list_rankings(today \\ Date.utc_today()) do
    players = eligible_players(today)

    case last_tournament() do
      nil ->
        players
        |> Enum.sort_by(& &1.elo, :desc)
        |> Enum.with_index(1)
        |> Enum.map(fn {player, rank} ->
          %Entry{
            rank: rank,
            player_id: player.id,
            player_name: player.name,
            games_played: player.games_played,
            elo: player.elo,
            elo_change: nil,
            rank_change: nil
          }
        end)

      tournament ->
        {elo_diffs, game_counts} = tournament_diffs(tournament.id)

        ranked =
          players
          |> Enum.map(fn player ->
            diff = Map.get(elo_diffs, player.id, 0.0)
            games_in_tournament = Map.get(game_counts, player.id, 0)

            %{
              player: player,
              diff: diff,
              elo_before: player.elo - diff,
              games_before: player.games_played - games_in_tournament
            }
          end)

        new_order = Enum.sort_by(ranked, & &1.player.elo, :desc)
        old_order = Enum.sort_by(ranked, & &1.elo_before, :desc)

        old_ranks =
          old_order
          |> Enum.with_index(1)
          |> Map.new(fn {row, rank} -> {row.player.id, rank} end)

        new_order
        |> Enum.with_index(1)
        |> Enum.map(fn {row, new_rank} ->
          %Entry{
            rank: new_rank,
            player_id: row.player.id,
            player_name: row.player.name,
            games_played: row.player.games_played,
            elo: row.player.elo,
            elo_change: if(row.diff != 0.0, do: row.diff, else: nil),
            rank_change: rank_change(row, old_ranks, new_rank)
          }
        end)
    end
  end

  defp rank_change(%{games_before: games_before}, _old_ranks, _new_rank)
       when games_before < @min_games do
    :new
  end

  defp rank_change(row, old_ranks, new_rank) do
    old_rank = Map.fetch!(old_ranks, row.player.id)
    old_rank - new_rank
  end

  defp last_tournament do
    Tournament
    |> order_by(desc: :date)
    |> limit(1)
    |> Repo.one()
  end

  defp eligible_players(today) do
    since = Date.add(today, -@active_within_days)

    active_player_ids =
      PlayerInTournament
      |> join(:inner, [pit], t in Team, on: t.id == pit.team_id)
      |> join(:inner, [pit, t], tour in Tournament, on: tour.id == t.tournament_id)
      |> where([pit, t, tour], tour.date >= ^since)
      |> where([pit], not is_nil(pit.player_id))
      |> select([pit], pit.player_id)
      |> distinct(true)
      |> Repo.all()
      |> MapSet.new()

    Player
    |> where([p], p.games_played >= @min_games)
    |> where([p], p.is_tech_team == false)
    |> Repo.all()
    |> Enum.filter(&MapSet.member?(active_player_ids, &1.id))
  end

  defp tournament_diffs(tournament_id) do
    round_ids =
      Round
      |> where(tournament_id: ^tournament_id)
      |> select([r], r.id)
      |> Repo.all()

    games =
      Game
      |> where([g], g.round_id in ^round_ids)
      |> Repo.all()

    team_ids =
      games
      |> Enum.flat_map(&[&1.og_team_id, &1.oo_team_id, &1.cg_team_id, &1.co_team_id])
      |> Enum.uniq()

    teammates_by_team =
      PlayerInTournament
      |> where([pit], pit.team_id in ^team_ids)
      |> Repo.all()
      |> Enum.group_by(& &1.team_id)

    Enum.reduce(games, {%{}, %{}}, fn game, {elo_diffs, game_counts} ->
      diffs = PlayerElos.parse(game.players_elo_diff)

      [game.og_team_id, game.oo_team_id, game.cg_team_id, game.co_team_id]
      |> Enum.with_index()
      |> Enum.reduce({elo_diffs, game_counts}, fn {team_id, slot}, {elo_diffs, game_counts} ->
        teammates_by_team
        |> Map.get(team_id, [])
        |> Enum.with_index()
        |> Enum.reduce({elo_diffs, game_counts}, fn {pit, within_team_index}, {elo_diffs, game_counts} ->
          case pit.player_id do
            nil ->
              {elo_diffs, game_counts}

            player_id ->
              index = slot * 2 + within_team_index
              diff = Enum.at(diffs, index, 0.0)

              {
                Map.update(elo_diffs, player_id, diff, &(&1 + diff)),
                Map.update(game_counts, player_id, 1, &(&1 + 1))
              }
          end
        end)
      end)
    end)
  end
end
