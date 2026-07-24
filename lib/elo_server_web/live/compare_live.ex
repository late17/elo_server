defmodule EloServerWeb.CompareLive do
  @moduledoc """
  Time-travel comparison: pick a "From" and "To" tournament (or "Current")
  and see rank/games/elo movement across that span, in the same 4-column
  look as the main rating page.
  """

  use EloServerWeb, :live_view

  alias EloServer.Ranking

  def mount(_params, _session, socket) do
    timeline = Ranking.tournament_timeline()
    start_id = timeline |> Enum.reverse() |> Enum.at(1) |> then(& &1 && &1.id)
    start_id = start_id || (timeline |> List.first() |> then(& &1 && &1.id))

    socket =
      socket
      |> assign(:timeline, timeline)
      |> assign(:start_id, start_id)
      |> assign(:end_id, "current")
      |> compute_entries()

    {:ok, socket}
  end

  def handle_event("update", %{"start" => start_id, "end" => end_id}, socket) do
    socket =
      socket
      |> assign(:start_id, start_id)
      |> assign(:end_id, end_id)
      |> compute_entries()

    {:noreply, socket}
  end

  defp compute_entries(socket) do
    start_boundary = {:tournament, socket.assigns.start_id}
    end_boundary = boundary_for(socket.assigns.end_id)

    entries = Ranking.compare(start_boundary, end_boundary)

    assign(socket, :entries, entries)
  end

  defp boundary_for("current"), do: :current
  defp boundary_for(tournament_id), do: {:tournament, tournament_id}

  defp row_class(:disappeared), do: "rating-row-disappeared"
  defp row_class(_), do: ""

  defp rank_change_class(:new), do: "new"
  defp rank_change_class(n) when is_integer(n) and n > 0, do: "up"
  defp rank_change_class(n) when is_integer(n) and n < 0, do: "down"
  defp rank_change_class(_), do: ""

  defp rank_change_label(entry) do
    case entry.status do
      :new -> "NEW"
      :disappeared -> ""
      _ -> rank_delta_label(entry.rank_delta)
    end
  end

  defp rank_delta_label(n) when is_integer(n) and n > 0, do: "↑#{n}"
  defp rank_delta_label(n) when is_integer(n) and n < 0, do: "↓#{abs(n)}"
  defp rank_delta_label(_), do: ""

  defp elo_change_class(diff) when is_number(diff) and diff > 0, do: "up"
  defp elo_change_class(diff) when is_number(diff) and diff < 0, do: "down"
  defp elo_change_class(_), do: ""

  defp elo_change_label(diff) when is_number(diff) and diff > 0, do: "↑#{floor(diff)}"
  defp elo_change_label(diff) when is_number(diff) and diff < 0, do: "↓#{floor(abs(diff))}"
  defp elo_change_label(_), do: ""

  defp games_change_class(n) when is_integer(n) and n > 0, do: "up"
  defp games_change_class(n) when is_integer(n) and n < 0, do: "down"
  defp games_change_class(_), do: ""

  defp games_change_label(n) when is_integer(n) and n > 0, do: "↑#{n}"
  defp games_change_label(n) when is_integer(n) and n < 0, do: "↓#{abs(n)}"
  defp games_change_label(_), do: ""

  def render(assigns) do
    ~H"""
    <div class="rating-page">
      <div class="rating-wrapper">
        <header class="rating-header">
          <h1>RATING DEBATES UA</h1>
        </header>

        <main class="rating-main">
          <form phx-change="update" class="rating-compare-controls">
            <label>
              From:
              <select name="start">
                <option :for={t <- @timeline} value={t.id} selected={t.id == @start_id}>
                  {t.name} ({t.date})
                </option>
              </select>
            </label>

            <label>
              To:
              <select name="end">
                <option value="current" selected={"current" == @end_id}>Current</option>
                <option :for={t <- @timeline} value={t.id} selected={t.id == @end_id}>
                  {t.name} ({t.date})
                </option>
              </select>
            </label>
          </form>

          <div class="rating-table-container">
            <table class="rating-table">
              <thead>
                <tr>
                  <th>RANK</th>
                  <th>PLAYER</th>
                  <th>GAMES PLAYED</th>
                  <th>ELO</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={entry <- @entries} class={row_class(entry.status)}>
                  <td class="rating-place-cell">
                    <span class="rating-place">{entry.rank_end || "-"}</span>
                    <span class={"rating-rank-change #{rank_change_class(if entry.status == :new, do: :new, else: entry.rank_delta)}"}>
                      {rank_change_label(entry)}
                    </span>
                  </td>
                  <td>{entry.player_name}</td>
                  <td class="rating-elo-cell">
                    <span class="rating-elo">{entry.games_end}</span>
                    <span class={"rating-elo-change #{games_change_class(entry.games_in_span)}"}>
                      {games_change_label(entry.games_in_span)}
                    </span>
                  </td>
                  <td class="rating-elo-cell">
                    <span class="rating-elo">{floor(entry.elo_end)}</span>
                    <span class={"rating-elo-change #{elo_change_class(entry.elo_delta)}"}>
                      {elo_change_label(entry.elo_delta)}
                    </span>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </main>

        <footer class="rating-footer">
          <.link navigate={~p"/"}>Rating</.link>
        </footer>
      </div>
    </div>
    """
  end
end
