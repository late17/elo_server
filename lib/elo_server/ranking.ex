defmodule EloServer.Ranking do
  @moduledoc """
  Computes the current player rating, along with each player's movement
  (elo change, rank change) caused by the most recent tournament, and lets
  callers compare any two points in time (`compare/2`).

  All historical state is *reconstructed*: only the current elo/games-played
  and each game's elo diff are persisted, so a player's elo/games "as of"
  some earlier tournament is derived by subtracting the diffs of every
  tournament that happened after that point.
  """

  import Ecto.Query

  alias EloServer.Repo
  alias EloServer.Ranking.{CompareEntry, Entry}
  alias EloServer.Tournaments.{Tournament, Round, Team}
  alias EloServer.Players.{Player, PlayerInTournament}
  alias EloServer.Games.{Game, PlayerElos}

  @min_games 20
  @active_within_days 365

  # ------------------------------------------------------------------
  # Current single-tournament rating (existing behavior, unchanged)
  # ------------------------------------------------------------------

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

    team_ids = team_ids_for_games(games)
    teammates_by_team = teammates_by_team(team_ids)

    compute_diffs(games, teammates_by_team)
  end

  defp team_ids_for_games(games) do
    games
    |> Enum.flat_map(&[&1.og_team_id, &1.oo_team_id, &1.cg_team_id, &1.co_team_id])
    |> Enum.uniq()
  end

  defp teammates_by_team(team_ids) do
    PlayerInTournament
    |> where([pit], pit.team_id in ^team_ids)
    |> Repo.all()
    |> Enum.group_by(& &1.team_id)
  end

  defp compute_diffs(games, teammates_by_team) do
    Enum.reduce(games, {%{}, %{}}, fn game, {elo_diffs, game_counts} ->
      diffs = PlayerElos.parse(game.players_elo_diff)

      [game.og_team_id, game.oo_team_id, game.cg_team_id, game.co_team_id]
      |> Enum.with_index()
      |> Enum.reduce({elo_diffs, game_counts}, fn {team_id, slot}, {elo_diffs, game_counts} ->
        teammates_by_team
        |> Map.get(team_id, [])
        |> Enum.with_index()
        |> Enum.reduce({elo_diffs, game_counts}, fn {pit, within_team_index},
                                                     {elo_diffs, game_counts} ->
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

  # ------------------------------------------------------------------
  # Time-travel: snapshots at, and comparisons between, arbitrary points
  # ------------------------------------------------------------------

  @typedoc "A point in tournament history to compare from/to."
  @type boundary :: :current | {:tournament, Ecto.UUID.t()} | {:date, Date.t()}

  @doc """
  Tournaments in chronological order, oldest first — drives boundary
  pickers and boundary resolution.
  """
  def tournament_timeline do
    Tournament
    |> order_by(asc: :date)
    |> Repo.all()
  end

  @doc """
  Resolves a `boundary` to a zero-based index into `tournament_timeline/0`.

  The returned index means "state as of right after the tournament at that
  index". `-1` means "before any tournament happened" (base elo).
  """
  def resolve_boundary(boundary, timeline \\ tournament_timeline())

  def resolve_boundary(:current, timeline), do: length(timeline) - 1

  def resolve_boundary({:tournament, tournament_id}, timeline) do
    Enum.find_index(timeline, &(&1.id == tournament_id)) ||
      raise ArgumentError, "unknown tournament id: #{tournament_id}"
  end

  def resolve_boundary({:date, date}, timeline) do
    timeline
    |> Enum.with_index()
    |> Enum.filter(fn {t, _i} -> Date.compare(t.date, date) != :gt end)
    |> case do
      [] -> -1
      matches -> matches |> List.last() |> elem(1)
    end
  end

  @doc """
  Reconstructed `%{elo, games, last_game_date}` for every player, as of the
  boundary at `index` in `timeline`.
  """
  def snapshot(index, timeline \\ tournament_timeline()) do
    diffs_by_tournament = all_tournament_diffs(timeline)
    participations = all_participations()

    after_indexes = (index + 1)..(length(timeline) - 1)//1

    {elo_after, games_after} =
      Enum.reduce(after_indexes, {%{}, %{}}, fn i, {elo_acc, games_acc} ->
        tournament = Enum.at(timeline, i)
        {elo_diffs, game_counts} = Map.get(diffs_by_tournament, tournament.id, {%{}, %{}})

        elo_acc = merge_sum(elo_acc, elo_diffs)
        games_acc = merge_sum(games_acc, game_counts)
        {elo_acc, games_acc}
      end)

    boundary_date = if index >= 0, do: Enum.at(timeline, index).date, else: nil

    last_game_dates =
      participations
      |> Enum.filter(fn p -> boundary_date && Date.compare(p.date, boundary_date) != :gt end)
      |> Enum.group_by(& &1.player_id, & &1.date)
      |> Map.new(fn {player_id, dates} -> {player_id, Enum.max(dates, Date, fn -> nil end)} end)

    Player
    |> Repo.all()
    |> Map.new(fn player ->
      elo = player.elo - Map.get(elo_after, player.id, 0.0)
      games = player.games_played - Map.get(games_after, player.id, 0)
      last_game_date = Map.get(last_game_dates, player.id)

      {player.id,
       %{
         player_id: player.id,
         player_name: player.name,
         is_tech_team: player.is_tech_team,
         elo: elo,
         games: games,
         last_game_date: last_game_date
       }}
    end)
  end

  defp merge_sum(acc, diffs) do
    Enum.reduce(diffs, acc, fn {k, v}, acc -> Map.update(acc, k, v, &(&1 + v)) end)
  end

  defp all_participations do
    PlayerInTournament
    |> join(:inner, [pit], t in Team, on: t.id == pit.team_id)
    |> join(:inner, [pit, t], tour in Tournament, on: tour.id == t.tournament_id)
    |> where([pit], not is_nil(pit.player_id))
    |> select([pit, t, tour], %{player_id: pit.player_id, date: tour.date})
    |> Repo.all()
  end

  defp all_tournament_diffs(timeline) do
    tournament_ids = Enum.map(timeline, & &1.id)

    games_by_tournament =
      Game
      |> join(:inner, [g], r in Round, on: r.id == g.round_id)
      |> where([g, r], r.tournament_id in ^tournament_ids)
      |> select([g, r], %{game: g, tournament_id: r.tournament_id})
      |> Repo.all()
      |> Enum.group_by(& &1.tournament_id, & &1.game)

    all_team_ids =
      games_by_tournament
      |> Map.values()
      |> List.flatten()
      |> team_ids_for_games()

    teammates_by_team = teammates_by_team(all_team_ids)

    Map.new(games_by_tournament, fn {tournament_id, games} ->
      {tournament_id, compute_diffs(games, teammates_by_team)}
    end)
  end

  @doc """
  Determines whether a snapshot entry qualifies for the rating list at the
  given boundary date (>= min games, active within the last year, not tech).

  `opts`:
    * `:include_inactive` — skip the "active within a year" check.
    * `:include_unqualified` — skip the ">= min games" check.

  Both still require the player to have actually played at least one game
  and to not be a tech-team player.
  """
  def eligible_at?(entry, boundary_date, opts \\ []) do
    include_inactive = Keyword.get(opts, :include_inactive, false)
    include_unqualified = Keyword.get(opts, :include_unqualified, false)

    games_ok = include_unqualified or entry.games >= @min_games

    active_ok =
      include_inactive or
        (entry.last_game_date != nil and
           Date.compare(entry.last_game_date, Date.add(boundary_date, -@active_within_days)) != :lt)

    games_ok and active_ok and not entry.is_tech_team and entry.last_game_date != nil
  end

  @doc """
  Compares two boundaries and returns one `CompareEntry` per player who is
  eligible for the rating list at either boundary.

    * `:both` — eligible at both ends; has a full elo/rank delta.
    * `:new` — eligible only at `end_boundary` (crossed into the list during
      the span).
    * `:disappeared` — eligible at `start_boundary` but not at `end_boundary`
      (their last game fell more than a year before the end boundary).
  """
  def compare(start_boundary, end_boundary, opts \\ []) do
    timeline = tournament_timeline()
    start_index = resolve_boundary(start_boundary, timeline)
    end_index = resolve_boundary(end_boundary, timeline)

    start_date = boundary_date(start_index, timeline, start_boundary)
    end_date = boundary_date(end_index, timeline, end_boundary)

    start_snapshot = snapshot(start_index, timeline)
    end_snapshot = snapshot(end_index, timeline)

    start_eligible =
      start_snapshot |> Map.values() |> Enum.filter(&eligible_at?(&1, start_date, opts))

    end_eligible =
      end_snapshot |> Map.values() |> Enum.filter(&eligible_at?(&1, end_date, opts))

    start_ranks = ranks_by_elo(start_eligible)
    end_ranks = ranks_by_elo(end_eligible)

    start_ids = MapSet.new(start_eligible, & &1.player_id)
    end_ids = MapSet.new(end_eligible, & &1.player_id)
    union_ids = MapSet.union(start_ids, end_ids)

    union_ids
    |> Enum.map(fn player_id ->
      start_entry = Map.fetch!(start_snapshot, player_id)
      end_entry = Map.fetch!(end_snapshot, player_id)

      status =
        cond do
          MapSet.member?(start_ids, player_id) and MapSet.member?(end_ids, player_id) -> :both
          MapSet.member?(end_ids, player_id) -> :new
          true -> :disappeared
        end

      %CompareEntry{
        player_id: player_id,
        player_name: end_entry.player_name,
        elo_start: start_entry.elo,
        elo_end: end_entry.elo,
        elo_delta: end_entry.elo - start_entry.elo,
        rank_start: Map.get(start_ranks, player_id),
        rank_end: Map.get(end_ranks, player_id),
        rank_delta: rank_delta(start_ranks, end_ranks, player_id),
        games_start: start_entry.games,
        games_end: end_entry.games,
        games_in_span: end_entry.games - start_entry.games,
        status: status
      }
    end)
    |> Enum.sort_by(& &1.elo_end, :desc)
  end

  defp boundary_date(_index, _timeline, {:date, date}), do: date
  defp boundary_date(_index, _timeline, :current), do: Date.utc_today()
  defp boundary_date(-1, _timeline, _boundary), do: nil

  defp boundary_date(index, timeline, _boundary) do
    Enum.at(timeline, index).date
  end

  defp ranks_by_elo(entries) do
    entries
    |> Enum.sort_by(& &1.elo, :desc)
    |> Enum.with_index(1)
    |> Map.new(fn {entry, rank} -> {entry.player_id, rank} end)
  end

  defp rank_delta(start_ranks, end_ranks, player_id) do
    case {Map.get(start_ranks, player_id), Map.get(end_ranks, player_id)} do
      {nil, _} -> nil
      {_, nil} -> nil
      {start_rank, end_rank} -> start_rank - end_rank
    end
  end
end
