defmodule EloServerWeb.RatingLive do
  use EloServerWeb, :live_view

  alias EloServer.Ranking

  @columns [:rank, :player_name, :games_played, :elo]

  def mount(_params, _session, socket) do
    timeline = Ranking.tournament_timeline()

    socket =
      socket
      |> assign(:timeline, timeline)
      |> assign(:sort_col, 0)
      |> assign(:sort_dir_used, true)
      |> assign(:sort_dirs, %{0 => true, 1 => true, 2 => true, 3 => true})

    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    timeline = socket.assigns.timeline
    last_index = length(timeline) - 1

    {index, entries} =
      case params["t"] && Enum.find_index(timeline, &(&1.id == params["t"])) do
        nil ->
          {last_index, Ranking.list_rankings()}

        index ->
          {index, Ranking.list_rankings_at({:tournament, Enum.at(timeline, index).id})}
      end

    socket =
      socket
      |> assign(:entries, apply_sort(entries, socket.assigns))
      |> assign(:current_index, index)
      |> assign(:current_tournament, if(index >= 0, do: Enum.at(timeline, index)))
      |> assign(:at_oldest?, timeline == [] or index <= 0)
      |> assign(:at_newest?, index >= last_index)

    {:noreply, socket}
  end

  def handle_event("sort", %{"col" => col_str}, socket) do
    col = String.to_integer(col_str)
    ascending? = socket.assigns.sort_dirs[col]

    socket =
      socket
      |> assign(:sort_col, col)
      |> assign(:sort_dir_used, ascending?)
      |> assign(:sort_dirs, Map.put(socket.assigns.sort_dirs, col, !ascending?))

    {:noreply, assign(socket, :entries, apply_sort(socket.assigns.entries, socket.assigns))}
  end

  def handle_event("step", %{"dir" => dir}, socket) do
    timeline = socket.assigns.timeline
    target_index = socket.assigns.current_index + if(dir == "back", do: -1, else: 1)

    path =
      case Enum.at(timeline, target_index) do
        nil -> ~p"/"
        tournament -> ~p"/?t=#{tournament.id}"
      end

    {:noreply, push_patch(socket, to: path)}
  end

  defp apply_sort(entries, %{sort_col: col, sort_dir_used: ascending?}) do
    field = Enum.at(@columns, col)
    Enum.sort_by(entries, &sort_key(&1, field), sort_order(field, ascending?))
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
  defp elo_change_label(diff) when diff > 0, do: "↑#{floor(diff)}"
  defp elo_change_label(diff) when diff < 0, do: "↓#{floor(abs(diff))}"
  defp elo_change_label(_), do: ""

  def render(assigns) do
    ~H"""
    <div class="rating-page">
      <div class="rating-wrapper">
        <header class="rating-header">
          <h1>RATING DEBATES UA</h1>
        </header>
        
        <main class="rating-main">
          <div :if={@timeline != []} class="rating-history-nav">
            <button
              type="button"
              class="rating-history-nav-btn"
              phx-click="step"
              phx-value-dir="back"
              disabled={@at_oldest?}
              aria-label="Previous tournament"
            >
              ‹
            </button>
            <div class="rating-history-nav-label">
              <span class="rating-history-nav-name">{@current_tournament.name}</span>
              <span class="rating-history-nav-date">{@current_tournament.date}</span>
            </div>
            
            <button
              type="button"
              class="rating-history-nav-btn"
              phx-click="step"
              phx-value-dir="forward"
              disabled={@at_newest?}
              aria-label="Next tournament"
            >
              ›
            </button>
          </div>
          
          <div class="rating-table-container">
            <table class="rating-table rating-leaderboard">
              <thead>
                <tr>
                  <th
                    class={["rating-col-rank", @sort_col == 0 && "sorted"]}
                    phx-click="sort"
                    phx-value-col="0"
                  >
                    <span class="lb-long">RANK</span><span class="lb-short">#</span>
                    <span class="rating-arrow">{arrow(@sort_col, 0, @sort_dir_used)}</span>
                  </th>
                  
                  <th
                    class={["rating-col-player", @sort_col == 1 && "sorted"]}
                    phx-click="sort"
                    phx-value-col="1"
                  >
                    PLAYER <span class="rating-arrow">{arrow(@sort_col, 1, @sort_dir_used)}</span>
                  </th>
                  
                  <th
                    class={["rating-col-games", @sort_col == 2 && "sorted"]}
                    phx-click="sort"
                    phx-value-col="2"
                  >
                    <span class="lb-long">GAMES PLAYED</span><span class="lb-short">G</span>
                    <span class="rating-arrow">{arrow(@sort_col, 2, @sort_dir_used)}</span>
                  </th>
                  
                  <th
                    class={["rating-col-elo", @sort_col == 3 && "sorted"]}
                    phx-click="sort"
                    phx-value-col="3"
                  >
                    ELO <span class="rating-arrow">{arrow(@sort_col, 3, @sort_dir_used)}</span>
                  </th>
                </tr>
              </thead>
              
              <tbody>
                <tr :for={entry <- @entries}>
                  <td class="rating-col-rank" data-label="Rank">
                    <span class="rating-place-cell">
                      <span class="rating-place">{entry.rank}</span>
                      <span class={"rating-rank-change #{rank_change_class(entry.rank_change)}"}>
                        {rank_change_label(entry.rank_change)}
                      </span>
                    </span>
                  </td>
                  
                  <td class="rating-col-player" data-label="Player">
                    <.link navigate={~p"/player/#{entry.player_id}"} class="rating-player-link">
                      {entry.player_name}
                    </.link>
                  </td>
                  
                  <td class="rating-col-games" data-label="Games Played">{entry.games_played}</td>
                  
                  <td class="rating-col-elo" data-label="Elo">
                    <span class="rating-elo-cell">
                      <span class="rating-elo">{floor(entry.elo)}</span>
                      <span class={"rating-elo-change #{elo_change_class(entry.elo_change)}"}>
                        {elo_change_label(entry.elo_change)}
                      </span>
                    </span>
                  </td>
                </tr>
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
