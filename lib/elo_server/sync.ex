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
