defmodule EloServerWeb.SyncControllerTest do
  use EloServerWeb.ConnCase, async: true

  alias EloServer.Repo
  alias EloServer.Tournaments.Tournament
  alias EloServer.Players.Player

  @token Application.compile_env!(:elo_server, :sync_token)

  defp player(id, overrides \\ %{}) do
    Map.merge(
      %{
        "id" => id,
        "name" => "Player #{id}",
        "is_tech_team" => false,
        "elo" => 1500.0,
        "games_played" => 0,
        "map_names" => ""
      },
      overrides
    )
  end

  defp valid_payload do
    tournament_id = Ecto.UUID.generate()
    team_ids = for _ <- 1..4, do: Ecto.UUID.generate()
    [og, oo, cg, co] = team_ids
    round_id = Ecto.UUID.generate()
    game_id = Ecto.UUID.generate()
    player_ids = for _ <- 1..8, do: Ecto.UUID.generate()

    players_in_tournament =
      team_ids
      |> Enum.with_index()
      |> Enum.flat_map(fn {team_id, team_idx} ->
        for seat <- 0..1 do
          player_idx = team_idx * 2 + seat
          player_id = Enum.at(player_ids, player_idx)

          %{
            "id" => Ecto.UUID.generate(),
            "name_in_tournament" => "Speaker #{player_idx}",
            "team_id" => team_id,
            "player_id" => player_id
          }
        end
      end)

    %{
      "tournament" => %{
        "id" => tournament_id,
        "name" => "Kyiv Debate Open",
        "short_name" => "kdo2026",
        "date" => "2026-01-15",
        "semi_final" => false,
        "novice_final" => false,
        "junior_final" => false,
        "final" => false
      },
      "players_upsert" => Enum.map(player_ids, &player/1),
      "teams" =>
        Enum.map(team_ids, fn id ->
          %{"id" => id, "name" => "Team #{id}", "tournament_id" => tournament_id}
        end),
      "players_in_tournament" => players_in_tournament,
      "rounds" => [
        %{"id" => round_id, "type" => "PRELIM", "number" => 1, "tournament_id" => tournament_id}
      ],
      "games" => [
        %{
          "id" => game_id,
          "is_eliminating" => false,
          "round_id" => round_id,
          "og" => og,
          "oo" => oo,
          "cg" => cg,
          "co" => co,
          "places" => "[1,2,3,4]",
          "players_elos" => "[1500,1500,1500,1500,1500,1500,1500,1500]",
          "players_elo_diff" => "[10,-10,5,-5,3,-3,1,-1]",
          "game_type" => "PRELIM"
        }
      ]
    }
  end

  test "returns 401 without a valid bearer token", %{conn: conn} do
    conn = post(conn, ~p"/api/sync/tournament", valid_payload())
    assert json_response(conn, 401)
  end

  test "returns 401 with a wrong bearer token", %{conn: conn} do
    conn =
      conn
      |> put_req_header("authorization", "Bearer wrong-token")
      |> post(~p"/api/sync/tournament", valid_payload())

    assert json_response(conn, 401)
  end

  test "applies a new tournament end to end", %{conn: conn} do
    payload = valid_payload()

    conn =
      conn
      |> put_req_header("authorization", "Bearer #{@token}")
      |> post(~p"/api/sync/tournament", payload)

    assert %{"short_name" => "kdo2026"} = json_response(conn, 201)

    assert Repo.get_by(Tournament, short_name: "kdo2026")
    assert Repo.aggregate(Player, :count) == 8

    first_player_id = payload["players_upsert"] |> List.first() |> Map.fetch!("id")
    player = Repo.get!(Player, first_player_id)
    assert player.elo == 1500.0
  end

  test "rejects a duplicate tournament short_name", %{conn: conn} do
    payload = valid_payload()

    conn1 =
      conn
      |> put_req_header("authorization", "Bearer #{@token}")
      |> post(~p"/api/sync/tournament", payload)

    assert json_response(conn1, 201)

    duplicate_payload = %{
      payload
      | "tournament" => %{payload["tournament"] | "id" => Ecto.UUID.generate()}
    }

    conn2 =
      conn
      |> put_req_header("authorization", "Bearer #{@token}")
      |> post(~p"/api/sync/tournament", duplicate_payload)

    assert json_response(conn2, 409)
  end

  test "rolls back everything when the payload is malformed", %{conn: conn} do
    payload = valid_payload()
    broken_payload = Map.put(payload, "games", [%{"id" => Ecto.UUID.generate()}])

    conn =
      conn
      |> put_req_header("authorization", "Bearer #{@token}")
      |> post(~p"/api/sync/tournament", broken_payload)

    assert json_response(conn, 422)
    refute Repo.get_by(Tournament, short_name: "kdo2026")
    assert Repo.aggregate(Player, :count) == 0
  end
end
