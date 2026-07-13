defmodule EloServerWeb.RatingLive do
  use EloServerWeb, :live_view

  alias EloServer.Ranking

  @columns [:rank, :player_name, :games_played, :elo]

  def mount(_params, _session, socket) do
    entries = Ranking.list_rankings()

    socket =
      socket
      |> assign(:entries, entries)
      |> assign(:sort_col, 0)
      |> assign(:sort_dir_used, true)
      |> assign(:sort_dirs, %{0 => true, 1 => true, 2 => true, 3 => true})

    {:ok, socket}
  end

  def handle_event("sort", %{"col" => col_str}, socket) do
    col = String.to_integer(col_str)
    field = Enum.at(@columns, col)
    ascending? = socket.assigns.sort_dirs[col]

    entries =
      Enum.sort_by(socket.assigns.entries, &sort_key(&1, field), sort_order(field, ascending?))

    socket =
      socket
      |> assign(:entries, entries)
      |> assign(:sort_col, col)
      |> assign(:sort_dir_used, ascending?)
      |> assign(:sort_dirs, Map.put(socket.assigns.sort_dirs, col, !ascending?))

    {:noreply, socket}
  end

  defp sort_key(entry, :player_name), do: Map.fetch!(entry, :player_name)
  defp sort_key(entry, field), do: Map.fetch!(entry, field)

  defp sort_order(:player_name, true), do: :asc
  defp sort_order(:player_name, false), do: :desc
  defp sort_order(_field, true), do: :asc
  defp sort_order(_field, false), do: :desc

  defp arrow(assigns_col, col, dir) do
    cond do
      assigns_col != col -> "↑"
      dir -> "↑"
      true -> "↓"
    end
  end

  defp rank_change_class(:new), do: "new"
  defp rank_change_class(n) when n > 0, do: "up"
  defp rank_change_class(n) when n < 0, do: "down"
  defp rank_change_class(_), do: ""

  defp rank_change_label(:new), do: "NEW"
  defp rank_change_label(n) when n > 0, do: "↑#{n}"
  defp rank_change_label(n) when n < 0, do: "↓#{abs(n)}"
  defp rank_change_label(_), do: ""

  defp elo_change_class(nil), do: ""
  defp elo_change_class(diff) when diff > 0, do: "up"
  defp elo_change_class(diff) when diff < 0, do: "down"
  defp elo_change_class(_), do: ""

  defp elo_change_label(nil), do: ""
  defp elo_change_label(diff) when diff > 0, do: "↑#{round(diff)}"
  defp elo_change_label(diff) when diff < 0, do: "↓#{abs(round(diff))}"
  defp elo_change_label(_), do: ""

  def render(assigns) do
    ~H"""
    <div class="rating-page">
      <div class="rating-wrapper">
        <header class="rating-header">
          <h1>RATING DEBATES UA</h1>
        </header>

        <main class="rating-main">
          <div class="rating-table-container">
            <table class="rating-table">
              <thead>
                <tr>
                  <th phx-click="sort" phx-value-col="0">
                    RANK <span class="rating-arrow">{arrow(@sort_col, 0, @sort_dir_used)}</span>
                  </th>
                  <th phx-click="sort" phx-value-col="1">
                    PLAYER <span class="rating-arrow">{arrow(@sort_col, 1, @sort_dir_used)}</span>
                  </th>
                  <th phx-click="sort" phx-value-col="2">
                    GAMES PLAYED
                    <span class="rating-arrow">{arrow(@sort_col, 2, @sort_dir_used)}</span>
                  </th>
                  <th phx-click="sort" phx-value-col="3">
                    ELO <span class="rating-arrow">{arrow(@sort_col, 3, @sort_dir_used)}</span>
                  </th>
                </tr>
              </thead>
              <tbody>
                <tr :for={entry <- @entries}>
                  <td class="rating-place-cell">
                    <span class="rating-place">{entry.rank}</span>
                    <span class={"rating-rank-change #{rank_change_class(entry.rank_change)}"}>
                      {rank_change_label(entry.rank_change)}
                    </span>
                  </td>
                  <td>{entry.player_name}</td>
                  <td>{entry.games_played}</td>
                  <td class="rating-elo-cell">
                    <span class="rating-elo">{floor(entry.elo)}</span>
                    <span class={"rating-elo-change #{elo_change_class(entry.elo_change)}"}>
                      {elo_change_label(entry.elo_change)}
                    </span>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </main>

        <footer class="rating-footer">
          © {Date.utc_today().year} Lviv Debate Union спільно з Аніме на Аві, Східняцьке Бидло Продакшн та КООП "Озеро"
          | <.link navigate={~p"/about"}>About</.link>
        </footer>
      </div>
    </div>
    """
  end
end
