defmodule EloServerWeb.PlayerLive do
  @moduledoc """
  A single player's report: profile stats plus their full game history,
  in the same art-deco stylistic as the rating pages.
  """

  use EloServerWeb, :live_view

  alias EloServer.{GameDetail, PlayerReport}

  def mount(%{"id" => player_id}, _session, socket) do
    socket =
      case PlayerReport.get(player_id) do
        nil ->
          socket
          |> put_flash(:error, "Player not found")
          |> push_navigate(to: ~p"/")

        report ->
          socket
          |> assign(:player, report.player)
          |> assign(:games, report.games)
          |> assign(:position_counts, position_counts(report.games))
          |> assign(:place_counts, place_counts(report.games))
          |> assign(:round_type_counts, round_type_counts(report.games))
          |> assign(:tournament_wins, tournament_wins(report.games))
          |> assign(:final_losses, final_losses(report.games))
          |> assign(:semi_final_losses, semi_final_losses(report.games))
          |> assign(:expanded_game_id, nil)
          |> assign(:expanded_game, nil)
      end

    {:ok, socket}
  end

  def handle_event("toggle_game", %{"id" => game_id}, socket) do
    socket =
      if socket.assigns.expanded_game_id == game_id do
        socket
        |> assign(:expanded_game_id, nil)
        |> assign(:expanded_game, nil)
      else
        socket
        |> assign(:expanded_game_id, game_id)
        |> assign(:expanded_game, GameDetail.get(game_id, socket.assigns.player.id))
      end

    {:noreply, socket}
  end

  @final_round_types ["FINAL", "NOVICE_FINAL", "JUNIOR_FINAL"]

  defp position_counts(games) do
    Enum.reduce(games, %{og: 0, oo: 0, cg: 0, co: 0}, fn game, acc ->
      Map.update!(acc, game.seat, &(&1 + 1))
    end)
  end

  defp place_counts(games) do
    Enum.reduce(games, %{first: 0, second: 0, third: 0, fourth: 0}, fn game, acc ->
      case game.result do
        place when place in [:first, :second, :third, :fourth] -> Map.update!(acc, place, &(&1 + 1))
        _ -> acc
      end
    end)
  end

  defp round_type_counts(games) do
    Enum.reduce(games, %{semi_final: 0, final: 0}, fn game, acc ->
      case game.round_type do
        "SEMI_FINAL" -> Map.update!(acc, :semi_final, &(&1 + 1))
        type when type in @final_round_types -> Map.update!(acc, :final, &(&1 + 1))
        _ -> acc
      end
    end)
  end

  defp tournament_wins(games) do
    games
    |> Enum.filter(&(&1.result == :advancing and &1.round_type in @final_round_types))
    |> Enum.map(&{&1.tournament_name, &1.tournament_date, &1.round_type})
    |> Enum.sort_by(fn {_name, date, _type} -> Date.to_erl(date) end, :desc)
  end

  defp final_losses(games) do
    games
    |> Enum.filter(&(&1.result == :eliminated and &1.round_type in @final_round_types))
    |> Enum.map(&{&1.tournament_name, &1.tournament_date, &1.round_type})
    |> Enum.sort_by(fn {_name, date, _type} -> Date.to_erl(date) end, :desc)
  end

  defp semi_final_losses(games) do
    games
    |> Enum.filter(&(&1.result == :eliminated and &1.round_type == "SEMI_FINAL"))
    |> Enum.map(&{&1.tournament_name, &1.tournament_date})
    |> Enum.sort_by(fn {_name, date} -> Date.to_erl(date) end, :desc)
  end

  defp seat_label(:og), do: "OG"
  defp seat_label(:oo), do: "OO"
  defp seat_label(:cg), do: "CG"
  defp seat_label(:co), do: "CO"

  @no_number_round_types ["SEMI_FINAL" | @final_round_types]

  defp round_label(round_type, _round_number) when round_type in @no_number_round_types do
    String.replace(round_type, "_", " ")
  end

  defp round_label(round_type, round_number) do
    "#{round_type} #{round_number}"
  end

  defp result_label(:first), do: "1st"
  defp result_label(:second), do: "2nd"
  defp result_label(:third), do: "3rd"
  defp result_label(:fourth), do: "4th"
  defp result_label(:advancing), do: "Advanced"
  defp result_label(:eliminated), do: "Eliminated"
  defp result_label(_), do: "-"

  defp result_class(:first), do: "up"
  defp result_class(:second), do: "up-light"
  defp result_class(:third), do: "down-light"
  defp result_class(:fourth), do: "down"
  defp result_class(:advancing), do: "up"
  defp result_class(:eliminated), do: "down"
  defp result_class(_), do: ""

  defp elo_change_class(diff) when is_number(diff) and diff > 0, do: "up"
  defp elo_change_class(diff) when is_number(diff) and diff < 0, do: "down"
  defp elo_change_class(_), do: ""

  defp elo_change_label(diff) when is_number(diff) and diff > 0, do: "↑#{floor(diff)}"
  defp elo_change_label(diff) when is_number(diff) and diff < 0, do: "↓#{floor(abs(diff))}"
  defp elo_change_label(_), do: ""

  defp signed_points(nil), do: "—"

  defp signed_points(value) when is_number(value) do
    sign = if value >= 0, do: "+", else: "−"
    :erlang.float_to_binary(abs(value), decimals: 1)
    |> then(&"#{sign}#{&1}")
  end

  defp points_class(nil), do: ""
  defp points_class(value) when is_number(value) and value > 0, do: "up"
  defp points_class(value) when is_number(value) and value < 0, do: "down"
  defp points_class(_), do: ""

  defp win_label("FINAL"), do: "Won"
  defp win_label("NOVICE_FINAL"), do: "Won Novice Final"
  defp win_label("JUNIOR_FINAL"), do: "Won Junior Final"

  defp final_loss_label("FINAL"), do: "Reached Final"
  defp final_loss_label("NOVICE_FINAL"), do: "Reached Novice Final"
  defp final_loss_label("JUNIOR_FINAL"), do: "Reached Junior Final"

  def render(assigns) do
    ~H"""
    <div class="rating-page">
      <div class="rating-wrapper">
        <header class="rating-header">
          <h1>RATING DEBATES UA</h1>
        </header>

        <main class="rating-main">
          <div class="rating-profile">
            <h2 class="rating-profile-name">{@player.name}</h2>
            <div class="rating-profile-stats">
              <div class="rating-profile-stat">
                <span class="rating-profile-stat-label">Games Played</span>
                <span class="rating-profile-stat-value">{@player.games_played}</span>
              </div>
              <div class="rating-profile-stat">
                <span class="rating-profile-stat-label">ELO</span>
                <span class="rating-profile-stat-value">{floor(@player.elo)}</span>
              </div>
            </div>

            <div class="rating-profile-substats">
              <div class="rating-profile-substat">
                <span class="rating-profile-substat-label">OG</span>
                <span class="rating-profile-substat-value">{@position_counts.og}</span>
              </div>
              <div class="rating-profile-substat">
                <span class="rating-profile-substat-label">OO</span>
                <span class="rating-profile-substat-value">{@position_counts.oo}</span>
              </div>
              <div class="rating-profile-substat">
                <span class="rating-profile-substat-label">CG</span>
                <span class="rating-profile-substat-value">{@position_counts.cg}</span>
              </div>
              <div class="rating-profile-substat">
                <span class="rating-profile-substat-label">CO</span>
                <span class="rating-profile-substat-value">{@position_counts.co}</span>
              </div>
            </div>

            <div class="rating-profile-substats">
              <div class="rating-profile-substat">
                <span class="rating-profile-substat-label">1st</span>
                <span class="rating-profile-substat-value">{@place_counts.first}</span>
              </div>
              <div class="rating-profile-substat">
                <span class="rating-profile-substat-label">2nd</span>
                <span class="rating-profile-substat-value">{@place_counts.second}</span>
              </div>
              <div class="rating-profile-substat">
                <span class="rating-profile-substat-label">3rd</span>
                <span class="rating-profile-substat-value">{@place_counts.third}</span>
              </div>
              <div class="rating-profile-substat">
                <span class="rating-profile-substat-label">4th</span>
                <span class="rating-profile-substat-value">{@place_counts.fourth}</span>
              </div>
            </div>

            <div class="rating-profile-substats">
              <div class="rating-profile-substat">
                <span class="rating-profile-substat-label">Semi Finals</span>
                <span class="rating-profile-substat-value">{@round_type_counts.semi_final}</span>
              </div>
              <div class="rating-profile-substat">
                <span class="rating-profile-substat-label">Finals</span>
                <span class="rating-profile-substat-value">{@round_type_counts.final}</span>
              </div>
              <div class="rating-profile-substat">
                <span class="rating-profile-substat-label">Wins 🏆</span>
                <span class="rating-profile-substat-value">{length(@tournament_wins)}</span>
              </div>
            </div>

            <div :if={@tournament_wins != []} class="rating-profile-wins">
              <span class="rating-profile-wins-label">🏆 Tournament Wins</span>
              <ul class="rating-profile-wins-list">
                <li :for={{name, date, round_type} <- @tournament_wins}>
                  {win_label(round_type)} — {name} ({date})
                </li>
              </ul>
            </div>

            <div :if={@final_losses != []} class="rating-profile-wins">
              <span class="rating-profile-wins-label">Finals</span>
              <ul class="rating-profile-wins-list">
                <li :for={{name, date, round_type} <- @final_losses}>
                  {final_loss_label(round_type)} — {name} ({date})
                </li>
              </ul>
            </div>

            <div :if={@semi_final_losses != []} class="rating-profile-wins">
              <span class="rating-profile-wins-label">Semi Finals</span>
              <ul class="rating-profile-wins-list">
                <li :for={{name, date} <- @semi_final_losses}>
                  Reached Semi Final — {name} ({date})
                </li>
              </ul>
            </div>
          </div>

          <div class="rating-table-container">
            <table class="rating-table rating-history-table">
              <thead>
                <tr>
                  <th></th>
                  <th>DATE</th>
                  <th>TOURNAMENT</th>
                  <th>ROUND</th>
                  <th>SEAT</th>
                  <th>RESULT</th>
                  <th>ELO</th>
                </tr>
              </thead>
              <tbody>
                <%= for game <- @games do %>
                  <tr
                    class="rating-game-row"
                    phx-click="toggle_game"
                    phx-value-id={game.game_id}
                  >
                    <td class="rating-game-chevron">
                      {if @expanded_game_id == game.game_id, do: "▾", else: "▸"}
                    </td>
                    <td>{game.tournament_date}</td>
                    <td>{game.tournament_name}</td>
                    <td>{round_label(game.round_type, game.round_number)}</td>
                    <td>{seat_label(game.seat)}</td>
                    <td class={result_class(game.result)}>{result_label(game.result)}</td>
                    <td class="rating-elo-cell">
                      <span class="rating-elo">{floor(game.elo_before + game.elo_diff)}</span>
                      <span class={"rating-elo-change #{elo_change_class(game.elo_diff)}"}>
                        {elo_change_label(game.elo_diff)}
                      </span>
                    </td>
                  </tr>
                  <tr :if={@expanded_game_id == game.game_id}>
                    <td colspan="7" class="rating-game-detail-cell">
                      <div :if={@expanded_game} class="rating-game-detail">
                        <div :for={team <- @expanded_game.teams} class="rating-game-team">
                          <div class="rating-game-team-header">
                            <span class="rating-game-team-seat">{seat_label(team.seat)}</span>
                            <span class="rating-game-team-name">{team.name}</span>
                            <span class={"rating-game-team-result #{result_class(team.result)}"}>
                              {result_label(team.result)}
                            </span>
                          </div>
                          <div class="rating-game-team-rating">
                            Team rating: {floor(team.rating)}
                          </div>
                          <ul class="rating-game-players">
                            <li
                              :for={player <- team.players}
                              class={
                                "rating-game-player" <>
                                  if(player.player_id == @player.id, do: " rating-game-player-self", else: "")
                              }
                            >
                              <.link navigate={~p"/player/#{player.player_id}"}>
                                {player.name}
                              </.link>
                              <span class="rating-game-player-elo">
                                {floor(player.elo_before + player.elo_diff)}
                              </span>
                              <span class={"rating-game-player-change #{elo_change_class(player.elo_diff)}"}>
                                {elo_change_label(player.elo_diff)}
                              </span>
                            </li>
                          </ul>
                          <div :if={team.seat != @expanded_game.viewer_seat} class="rating-game-team-points">
                            <span>vs you</span>
                            <span class={points_class(team.points_vs_viewer)}>
                              {signed_points(team.points_vs_viewer)}
                            </span>
                          </div>
                        </div>
                      </div>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        </main>

        <footer class="rating-footer">
          © {Date.utc_today().year} Lviv Debate Union спільно з Аніме на Аві, Східняцьке Бидло Продакшн та КООП "Озеро"
          | <.link navigate={~p"/about"} class="rating-footer-about">About</.link>
        </footer>
      </div>
    </div>
    """
  end
end
