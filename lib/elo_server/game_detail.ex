defmodule EloServer.GameDetail do
  @moduledoc """
  Builds the full room breakdown for a single game: all four teams, their
  players' ratings, and the result each team got.
  """

  import Ecto.Query

  alias EloServer.Repo
  alias EloServer.Games.{EloBreakdown, Game, PlayerElos, RoomResults}
  alias EloServer.Players.{Player, PlayerInTournament}
  alias EloServer.Tournaments.{Round, Team}

  @position_order [:og, :oo, :cg, :co]

  defmodule PlayerDetail do
    @moduledoc "One player's rating within a game."
    defstruct [:player_id, :name, :elo_before, :elo_diff]
  end

  defmodule TeamDetail do
    @moduledoc "One team's rating, result, and (for opponents of the viewer) points swing within a game."
    defstruct [:seat, :name, :rating, :result, :players, :points_vs_viewer]
  end

  defmodule GameData do
    @moduledoc "Full room breakdown for a game."
    defstruct [:round_type, :round_number, :teams, :viewer_seat]
  end

  @doc """
  Returns a `%GameData{}` for `game_id`, or `nil` if no such game exists.

  When `viewer_player_id` is given and found in this room, each opponent
  team's `:points_vs_viewer` is filled in (the viewer's own team's stays
  `nil`).
  """
  def get(game_id, viewer_player_id \\ nil) do
    case fetch_game(game_id) do
      nil -> nil
      %{game: game, round: round} -> build(game, round, viewer_player_id)
    end
  end

  defp fetch_game(game_id) do
    Game
    |> where([g], g.id == ^game_id)
    |> join(:inner, [g], r in Round, on: r.id == g.round_id)
    |> select([g, r], %{game: g, round: r})
    |> Repo.one()
  end

  defp build(game, round, viewer_player_id) do
    team_by_position = %{
      og: game.og_team_id,
      oo: game.oo_team_id,
      cg: game.cg_team_id,
      co: game.co_team_id
    }

    team_ids = Map.values(team_by_position)

    teams_by_id =
      Team
      |> where([t], t.id in ^team_ids)
      |> Repo.all()
      |> Map.new(&{&1.id, &1})

    # Deliberately the same query shape (no join) as `PlayerReport`'s
    # teammate lookup: neither query has an `ORDER BY`, so Postgres's
    # otherwise-arbitrary row order must be produced by an identical query
    # to line up consistently with how the elo/diff arrays were paired to
    # teammates elsewhere in the report.
    pits_by_team =
      PlayerInTournament
      |> where([pit], pit.team_id in ^team_ids)
      |> Repo.all()
      |> Enum.group_by(& &1.team_id)

    players_by_id =
      Player
      |> where([p], p.id in ^Enum.map(List.flatten(Map.values(pits_by_team)), & &1.player_id))
      |> Repo.all()
      |> Map.new(&{&1.id, &1})

    players_by_team =
      Map.new(pits_by_team, fn {team_id, pits} ->
        {team_id, Enum.map(pits, &%{pit: &1, player: Map.fetch!(players_by_id, &1.player_id)})}
      end)

    elos_before = elos_before_by_team(game)
    results_by_team = results_by_team(game, team_by_position)

    teams =
      @position_order
      |> Enum.map(fn seat ->
        team_id = Map.fetch!(team_by_position, seat)
        team = Map.fetch!(teams_by_id, team_id)
        {befores, diffs} = Map.fetch!(elos_before, seat)
        team_members = Map.get(players_by_team, team_id, [])

        players =
          team_members
          |> Enum.zip(Enum.zip(befores, diffs))
          |> Enum.map(fn {%{pit: pit, player: player}, {before, diff}} ->
            %PlayerDetail{
              player_id: player.id,
              name: pit.name_in_tournament || player.name,
              elo_before: before,
              elo_diff: diff
            }
          end)

        rating =
          case befores do
            [] -> 0.0
            _ -> Enum.sum(befores) / length(befores)
          end

        %TeamDetail{
          seat: seat,
          name: team.name,
          rating: rating,
          result: Map.get(results_by_team, team_id),
          players: players,
          points_vs_viewer: nil
        }
      end)

    tech_by_seat =
      Map.new(@position_order, fn seat ->
        team_id = Map.fetch!(team_by_position, seat)

        tech? =
          players_by_team
          |> Map.get(team_id, [])
          |> Enum.any?(& &1.player.is_tech_team)

        {seat, tech?}
      end)

    {teams, viewer_seat} = apply_points_vs_viewer(teams, tech_by_seat, viewer_player_id)

    %GameData{
      round_type: round.type,
      round_number: round.number,
      teams: teams,
      viewer_seat: viewer_seat
    }
  end

  defp apply_points_vs_viewer(teams, tech_by_seat, viewer_player_id) do
    viewer_seat =
      viewer_player_id &&
        Enum.find_value(teams, fn team ->
          if Enum.any?(team.players, &(&1.player_id == viewer_player_id)), do: team.seat
        end)

    viewer_diff =
      viewer_seat &&
        teams
        |> Enum.find(&(&1.seat == viewer_seat))
        |> Map.fetch!(:players)
        |> Enum.find_value(fn p -> p.player_id == viewer_player_id && p.elo_diff end)

    breakdown_input =
      Enum.map(teams, fn team ->
        %{seat: team.seat, rating: team.rating, result: team.result, tech?: tech_by_seat[team.seat]}
      end)

    breakdown_result =
      if Enum.any?(breakdown_input, &(&1.result == nil)) do
        {:error, :missing_result}
      else
        EloBreakdown.compute(breakdown_input)
      end

    case {viewer_seat, breakdown_result} do
      {nil, _} ->
        {teams, nil}

      {_, {:error, _}} ->
        {teams, viewer_seat}

      {_, {:ok, %{raw_deltas: raw_deltas, terms: terms}}} ->
        raw_delta_total = Map.get(raw_deltas, viewer_seat, 0.0)

        teams =
          Enum.map(teams, fn team ->
            cond do
              team.seat == viewer_seat ->
                team

              raw_delta_total == 0.0 ->
                %{team | points_vs_viewer: nil}

              true ->
                term = Map.get(terms, {viewer_seat, team.seat}, 0.0)
                share = viewer_diff * term / raw_delta_total
                %{team | points_vs_viewer: share}
            end
          end)

        {teams, viewer_seat}
    end
  end

  # `game.players_elos` is already the pre-match snapshot (Kotlin writes it
  # as `playersStartElos`), not a post-match value — no subtraction needed.
  defp elos_before_by_team(game) do
    elos_by_team = PlayerElos.parse_by_team(game.players_elos)
    diffs_by_team = PlayerElos.parse_by_team(game.players_elo_diff)

    @position_order
    |> Map.new(fn seat ->
      befores = Map.fetch!(elos_by_team, seat)
      diffs = Map.fetch!(diffs_by_team, seat)
      {seat, {befores, diffs}}
    end)
  end

  defp results_by_team(game, team_by_position) do
    case RoomResults.decode(game.places, team_by_position) do
      %RoomResults.ByPlace{places: places} ->
        Map.new(places, fn {place, team_id} -> {team_id, place} end)

      %RoomResults.ByAdvancing{groups: groups} ->
        Map.new(groups.advancing, &{&1, :advancing})
        |> Map.merge(Map.new(groups.eliminated, &{&1, :eliminated}))
    end
  end
end
