defmodule EloServer.Sync do
  @moduledoc """
  Write path for the SYNC API: applies one already-computed tournament
  (produced locally by the Kotlin app's `CalcTournament`) to this
  database in a single transaction. This module owns the only writes
  this app ever performs — everything else here is read-only.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias EloServer.Repo
  alias EloServer.Tournaments.{Tournament, Round, Team}
  alias EloServer.Players.{Player, PlayerInTournament}
  alias EloServer.Games.Game

  @doc "True if a tournament with this short_name has already been synced."
  def tournament_exists?(short_name) do
    Repo.exists?(from t in Tournament, where: t.short_name == ^short_name)
  end

  @doc """
  Applies a decoded sync payload (string-keyed maps, as produced by
  `Jason.decode!/1`) in one transaction. Returns `{:ok, tournament}` or
  `{:error, reason}`; on error nothing is persisted.
  """
  def apply_tournament(payload) do
    tournament_attrs = Map.fetch!(payload, "tournament")
    short_name = Map.fetch!(tournament_attrs, "short_name")

    Multi.new()
    |> Multi.run(:duplicate_check, fn repo, _ ->
      if repo.exists?(from t in Tournament, where: t.short_name == ^short_name) do
        {:error, :tournament_already_exists}
      else
        {:ok, nil}
      end
    end)
    |> Multi.run(:players, fn repo, _ -> upsert_players(repo, payload["players_upsert"] || []) end)
    |> Multi.insert(:tournament, tournament_struct(tournament_attrs))
    |> Multi.run(:teams, fn repo, _ ->
      insert_each(repo, Team, payload["teams"] || [], &team_struct/1)
    end)
    |> Multi.run(:players_in_tournament, fn repo, _ ->
      insert_each(repo, PlayerInTournament, payload["players_in_tournament"] || [], &pit_struct/1)
    end)
    |> Multi.run(:rounds, fn repo, _ ->
      insert_each(repo, Round, payload["rounds"] || [], &round_struct/1)
    end)
    |> Multi.run(:games, fn repo, _ ->
      insert_each(repo, Game, payload["games"] || [], &game_struct/1)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{tournament: tournament}} -> {:ok, tournament}
      {:error, _failed_step, reason, _changes} -> {:error, reason}
    end
  end

  @doc """
  Reverts and deletes the tournament identified by `short_name`, mirroring the
  Kotlin console app's `RemoveTournamentService`: each player's `elo`/`games_played`
  is reverted using the diffs stored on `Game.players_elo_diff` at sync time, then
  every structural row for the tournament (games/players_in_tournament/rounds/teams/
  tournament) is deleted. `Player` rows themselves (and any aliases) are left intact,
  since aliases aren't tracked per-tournament. Returns `{:ok, tournament}` or
  `{:error, reason}`; on error nothing is persisted.
  """
  def remove_tournament(short_name) do
    Multi.new()
    |> Multi.run(:tournament, fn repo, _ ->
      case repo.one(from t in Tournament, where: t.short_name == ^short_name) do
        nil -> {:error, :tournament_not_found}
        tournament -> {:ok, tournament}
      end
    end)
    |> Multi.run(:teams, fn repo, %{tournament: tournament} ->
      {:ok, repo.all(from t in Team, where: t.tournament_id == ^tournament.id)}
    end)
    |> Multi.run(:rounds, fn repo, %{tournament: tournament} ->
      {:ok, repo.all(from r in Round, where: r.tournament_id == ^tournament.id)}
    end)
    |> Multi.run(:pits, fn repo, %{teams: teams} ->
      team_ids = Enum.map(teams, & &1.id)
      {:ok, repo.all(from p in PlayerInTournament, where: p.team_id in ^team_ids)}
    end)
    |> Multi.run(:games, fn repo, %{rounds: rounds} ->
      round_ids = Enum.map(rounds, & &1.id)
      {:ok, repo.all(from g in Game, where: g.round_id in ^round_ids)}
    end)
    |> Multi.run(:revert_players, fn repo, %{games: games, pits: pits} ->
      revert_players(repo, games, pits)
    end)
    |> Multi.run(:delete_games, fn repo, %{games: games} -> delete_each(repo, games) end)
    |> Multi.run(:delete_pits, fn repo, %{pits: pits} -> delete_each(repo, pits) end)
    |> Multi.run(:delete_rounds, fn repo, %{rounds: rounds} -> delete_each(repo, rounds) end)
    |> Multi.run(:delete_teams, fn repo, %{teams: teams} -> delete_each(repo, teams) end)
    |> Multi.run(:delete_tournament, fn repo, %{tournament: tournament} -> repo.delete(tournament) end)
    |> Repo.transaction()
    |> case do
      {:ok, %{tournament: tournament}} -> {:ok, tournament}
      {:error, _failed_step, reason, _changes} -> {:error, reason}
    end
  end

  defp delete_each(repo, rows) do
    Enum.reduce_while(rows, {:ok, []}, fn row, {:ok, acc} ->
      case repo.delete(row) do
        {:ok, deleted} -> {:cont, {:ok, [deleted | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  # Mirrors RemoveTournamentService.computeReversal: a team only "participated"
  # (incrementing its players' games_played at sync time) when it is non-tech and
  # paired against at least one other non-tech team in the room. Elo diffs are
  # subtracted straight from the stored per-slot players_elo_diff regardless of
  # participation (non-participants were stored as 0.0 anyway).
  defp revert_players(repo, games, pits) do
    pits_by_team = Enum.group_by(pits, & &1.team_id)
    player_ids = pits |> Enum.map(& &1.player_id) |> Enum.reject(&is_nil/1) |> Enum.uniq()
    players_by_id = repo.all(from p in Player, where: p.id in ^player_ids) |> Map.new(&{&1.id, &1})

    {elo_deltas, game_deltas} =
      Enum.reduce(games, {%{}, %{}}, fn game, acc ->
        apply_game_deltas(game, pits_by_team, players_by_id, acc)
      end)

    elo_deltas
    |> Map.keys()
    |> Enum.reduce_while({:ok, []}, fn player_id, {:ok, acc} ->
      player = Map.fetch!(players_by_id, player_id)
      elo_delta = Map.get(elo_deltas, player_id, 0.0)
      game_delta = Map.get(game_deltas, player_id, 0)

      changes = %{
        elo: player.elo - elo_delta,
        games_played: max(0, player.games_played - game_delta)
      }

      case repo.update(Ecto.Changeset.change(player, changes)) do
        {:ok, updated} -> {:cont, {:ok, [updated | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp apply_game_deltas(game, pits_by_team, players_by_id, {elo_deltas, game_deltas}) do
    diffs = String.split(game.players_elo_diff || "", "\n")
    team_ids = [game.og_team_id, game.oo_team_id, game.cg_team_id, game.co_team_id]

    is_tech_team =
      Map.new(team_ids, fn team_id ->
        teammates = Map.get(pits_by_team, team_id, [])

        tech? =
          Enum.any?(teammates, fn pit ->
            case Map.get(players_by_id, pit.player_id) do
              nil -> false
              player -> player.is_tech_team
            end
          end)

        {team_id, tech?}
      end)

    team_ids
    |> Enum.with_index()
    |> Enum.reduce({elo_deltas, game_deltas}, fn {team_id, slot}, acc ->
      participated =
        !Map.fetch!(is_tech_team, team_id) &&
          team_ids
          |> Enum.with_index()
          |> Enum.any?(fn {other_id, i} -> i != slot && !Map.fetch!(is_tech_team, other_id) end)

      teammates = Map.get(pits_by_team, team_id, [])

      teammates
      |> Enum.with_index()
      |> Enum.reduce(acc, fn {pit, within_team_index}, {elo_deltas, game_deltas} ->
        case pit.player_id do
          nil ->
            {elo_deltas, game_deltas}

          player_id ->
            index = slot * 2 + within_team_index
            diff = diffs |> Enum.at(index, "0.0") |> parse_float()

            elo_deltas = Map.update(elo_deltas, player_id, diff, &(&1 + diff))

            game_deltas =
              if participated do
                Map.update(game_deltas, player_id, 1, &(&1 + 1))
              else
                game_deltas
              end

            {elo_deltas, game_deltas}
        end
      end)
    end)
  end

  defp parse_float(str) do
    case Float.parse(str) do
      {value, _} -> value
      :error -> 0.0
    end
  end

  defp upsert_players(repo, players) do
    Enum.reduce_while(players, {:ok, []}, fn attrs, {:ok, acc} ->
      case repo.insert(player_struct(attrs),
             on_conflict: {:replace, [:name, :elo, :games_played, :map_names]},
             conflict_target: :id
           ) do
        {:ok, player} -> {:cont, {:ok, [player | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp insert_each(repo, schema, rows, to_struct) do
    Enum.reduce_while(rows, {:ok, []}, fn attrs, {:ok, acc} ->
      case repo.insert(to_struct.(attrs)) do
        {:ok, row} -> {:cont, {:ok, [row | acc]}}
        {:error, reason} -> {:halt, {:error, {schema, attrs, reason}}}
      end
    end)
  end

  defp player_struct(attrs) do
    %Player{
      id: Map.fetch!(attrs, "id"),
      name: Map.fetch!(attrs, "name"),
      is_tech_team: Map.fetch!(attrs, "is_tech_team"),
      elo: Map.fetch!(attrs, "elo") * 1.0,
      games_played: Map.fetch!(attrs, "games_played"),
      map_names: Map.fetch!(attrs, "map_names")
    }
  end

  defp tournament_struct(attrs) do
    %Tournament{
      id: Map.fetch!(attrs, "id"),
      name: Map.fetch!(attrs, "name"),
      short_name: Map.fetch!(attrs, "short_name"),
      date: Date.from_iso8601!(Map.fetch!(attrs, "date")),
      semi_final: Map.fetch!(attrs, "semi_final"),
      novice_final: Map.fetch!(attrs, "novice_final"),
      junior_final: Map.fetch!(attrs, "junior_final"),
      final: Map.fetch!(attrs, "final")
    }
  end

  defp team_struct(attrs) do
    %Team{
      id: Map.fetch!(attrs, "id"),
      name: Map.fetch!(attrs, "name"),
      tournament_id: Map.fetch!(attrs, "tournament_id")
    }
  end

  defp pit_struct(attrs) do
    %PlayerInTournament{
      id: Map.fetch!(attrs, "id"),
      name_in_tournament: Map.fetch!(attrs, "name_in_tournament"),
      team_id: Map.fetch!(attrs, "team_id"),
      player_id: Map.fetch!(attrs, "player_id")
    }
  end

  defp round_struct(attrs) do
    %Round{
      id: Map.fetch!(attrs, "id"),
      type: Map.fetch!(attrs, "type"),
      number: Map.get(attrs, "number"),
      tournament_id: Map.fetch!(attrs, "tournament_id")
    }
  end

  defp game_struct(attrs) do
    %Game{
      id: Map.fetch!(attrs, "id"),
      is_eliminating: Map.fetch!(attrs, "is_eliminating"),
      round_id: Map.fetch!(attrs, "round_id"),
      og_team_id: Map.fetch!(attrs, "og"),
      oo_team_id: Map.fetch!(attrs, "oo"),
      cg_team_id: Map.fetch!(attrs, "cg"),
      co_team_id: Map.fetch!(attrs, "co"),
      places: Map.fetch!(attrs, "places"),
      players_elos: Map.fetch!(attrs, "players_elos"),
      players_elo_diff: Map.fetch!(attrs, "players_elo_diff"),
      game_type: Map.fetch!(attrs, "game_type")
    }
  end
end
