defmodule EloServerWeb.TournamentLive do
  use EloServerWeb, :live_view

  alias EloServer.{Tournaments, Games}
  alias EloServer.Games.{RoomResults, PlayerElos}

  def mount(_params, _session, socket) do
    tournament = Tournaments.list_tournaments() |> List.first()

    {teams, rounds} =
      if tournament do
        teams = Tournaments.list_teams(tournament.id)
        rounds = Tournaments.list_rounds(tournament.id)

        rounds =
          Enum.map(rounds, fn round ->
            games = Games.list_games_for_round(round.id)
            %{round | games: games}
          end)

        {teams, rounds}
      else
        {[], []}
      end

    socket =
      socket
      |> assign(:tournament, tournament)
      |> assign(:teams, teams)
      |> assign(:rounds, rounds)

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="max-w-3xl mx-auto py-10">
        <h1 class="text-2xl font-bold mb-2">Debate Elo</h1>

        <%= if @tournament do %>
          <div class="mb-8">
            <h2 class="text-xl font-semibold">{@tournament.name}</h2>
            <p class="text-base-content/70">
              {@tournament.short_name} &middot; {@tournament.date}
            </p>
          </div>

          <div class="mb-8">
            <h3 class="font-semibold mb-2">Teams ({length(@teams)})</h3>
            <ul class="list-disc list-inside space-y-1">
              <li :for={team <- @teams}>{team.name}</li>
            </ul>
          </div>

          <div>
            <h3 class="font-semibold mb-2">Rounds ({length(@rounds)})</h3>
            <div :for={round <- @rounds} class="mb-6 border-t pt-4">
              <p class="font-medium">{round.type} — Round {round.number}</p>

              <div :for={game <- round.games} class="mt-2 pl-4 text-sm">
                <p>
                  OG: {game.og_team.name} &middot; OO: {game.oo_team.name} &middot;
                  CG: {game.cg_team.name} &middot; CO: {game.co_team.name}
                </p>
                <p class="text-base-content/70">
                  Places: {inspect(RoomResults.decode(game))}
                </p>
                <p class="text-base-content/70">
                  ELO diffs: {inspect(PlayerElos.parse_by_team(game.players_elo_diff))}
                </p>
              </div>
            </div>
          </div>
        <% else %>
          <p>No tournament data found.</p>
        <% end %>
      </div>
    </Layouts.app>
    """
  end
end
