defmodule EloServerWeb.PlayerLiveTest do
  use EloServerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias EloServer.PlayerReport.GameEntry
  alias EloServerWeb.PlayerLive

  @token Application.compile_env!(:elo_server, :sync_token)

  describe "group_tournaments/1" do
    test "groups newest-first games into one entry per tournament" do
      game = fn id, tid, name, date, elo_before, diff ->
        %GameEntry{
          game_id: id,
          tournament_id: tid,
          tournament_name: name,
          tournament_date: date,
          elo_before: elo_before,
          elo_diff: diff
        }
      end

      games = [
        game.("g3", "t2", "Kyiv", ~D[2026-09-27], 1600.0, 10.0),
        game.("g2", "t2", "Kyiv", ~D[2026-09-27], 1590.0, -4.0),
        game.("g1", "t1", "Lviv", ~D[2026-05-10], 1500.0, 90.0)
      ]

      assert [kyiv, lviv] = PlayerLive.group_tournaments(games)

      assert kyiv.id == "t2"
      assert kyiv.games_count == 2
      assert kyiv.elo_after == 1610.0
      assert kyiv.elo_change == 6.0
      assert Enum.map(kyiv.games, & &1.game_id) == ["g3", "g2"]

      assert lviv.games_count == 1
      assert lviv.elo_after == 1590.0
    end

    test "points sum BP placings and stage is the furthest round reached" do
      game = fn type, result ->
        %GameEntry{
          tournament_id: "t",
          round_type: type,
          result: result,
          elo_before: 1500.0,
          elo_diff: 0.0
        }
      end

      stage_of = fn games -> hd(PlayerLive.group_tournaments(games)).stage end

      [t] =
        PlayerLive.group_tournaments([
          game.("REGULAR", :first),
          game.("REGULAR", :third),
          game.("REGULAR", :fourth),
          game.("SEMI_FINAL", :advancing)
        ])

      assert t.points == 4
      assert t.stage == :semi_final

      assert stage_of.([game.("FINAL", :advancing), game.("SEMI_FINAL", :advancing)]) == :won
      assert stage_of.([game.("FINAL", :eliminated)]) == :final
      assert stage_of.([game.("NOVICE_FINAL", :advancing)]) == :won_novice_final
      assert stage_of.([game.("JUNIOR_FINAL", :eliminated)]) == :junior_final
      assert stage_of.([game.("REGULAR", :second)]) == :prelims
    end
  end

  describe "tournament ladder" do
    defp sync_tournament(conn, short_name, name, date) do
      tournament_id = Ecto.UUID.generate()
      [og, oo, cg, co] = team_ids = for _ <- 1..4, do: Ecto.UUID.generate()
      round_id = Ecto.UUID.generate()
      player_ids = for _ <- 1..8, do: Ecto.UUID.generate()

      pits =
        team_ids
        |> Enum.with_index()
        |> Enum.flat_map(fn {team_id, team_idx} ->
          for seat <- 0..1 do
            %{
              "id" => Ecto.UUID.generate(),
              "name_in_tournament" => "Speaker",
              "team_id" => team_id,
              "player_id" => Enum.at(player_ids, team_idx * 2 + seat)
            }
          end
        end)

      payload = %{
        "tournament" => %{
          "id" => tournament_id,
          "name" => name,
          "short_name" => short_name,
          "date" => date,
          "semi_final" => false,
          "novice_final" => false,
          "junior_final" => false,
          "final" => false
        },
        "players_upsert" =>
          Enum.map(player_ids, fn id ->
            %{
              "id" => id,
              "name" => "Player #{id}",
              "is_tech_team" => false,
              "elo" => 1500.0,
              "games_played" => 1,
              "map_names" => ""
            }
          end),
        "teams" =>
          Enum.map(team_ids, &%{"id" => &1, "name" => "Team", "tournament_id" => tournament_id}),
        "players_in_tournament" => pits,
        "rounds" => [
          %{"id" => round_id, "type" => "PRELIM", "number" => 1, "tournament_id" => tournament_id}
        ],
        "games" => [
          %{
            "id" => Ecto.UUID.generate(),
            "is_eliminating" => false,
            "round_id" => round_id,
            "og" => og,
            "oo" => oo,
            "cg" => cg,
            "co" => co,
            "places" => "REG:3210",
            "players_elos" => String.duplicate("1500.0\n", 8),
            "players_elo_diff" => "10.0\n-10.0\n5.0\n-5.0\n3.0\n-3.0\n1.0\n-1.0\n",
            "game_type" => "PRELIM"
          }
        ]
      }

      conn
      |> put_req_header("authorization", "Bearer #{@token}")
      |> post(~p"/api/sync/tournament", payload)
      |> json_response(201)

      hd(player_ids)
    end

    test "tournament opens to its games, a game opens its detail, closing resets both", %{
      conn: conn
    } do
      player_id = sync_tournament(conn, "t-old", "Old Open", "2026-01-15")

      {:ok, view, html} = live(conn, ~p"/player/#{player_id}")

      assert html =~ "Old Open"
      assert has_element?(view, ".ladder-stage", "Prelims")
      assert has_element?(view, ".ladder-points", "3")
      refute has_element?(view, ".ladder-games-list")

      view |> element(".ladder-trow") |> render_click()
      assert has_element?(view, ".ladder-games-list .ladder-grow")
      refute has_element?(view, ".ladder-games-list .rating-game-detail")

      view |> element(".ladder-grow") |> render_click()
      assert has_element?(view, ".ladder-games-list .rating-game-detail")

      # Closing the tournament also closes the open game.
      view |> element(".ladder-trow") |> render_click()
      refute has_element?(view, ".ladder-games-list")
      refute has_element?(view, ".ladder-game .rating-game-detail")
    end
  end
end
