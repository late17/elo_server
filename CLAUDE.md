# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

- `mix setup` — install deps, create/migrate DB, build assets (first-time setup)
- `mix phx.server` / `iex -S mix phx.server` — run the dev server at localhost:4000
- `mix test` — run tests (creates/migrates the test DB first, per the `test` alias)
- `mix test test/path/to_test.exs` — run a single test file
- `mix test test/path/to_test.exs:42` — run a single test at a line
- `mix test --failed` — rerun only the tests that failed last time
- `mix precommit` — **run this after finishing any change**: compiles with warnings-as-errors, removes unused deps.lock entries, formats, and runs the full test suite

## Architecture

This is a read-only ELO/ranking dashboard for debate tournaments, backed by data written by an external system (a Kotlin app — see comments referencing `CalculateRoomEloDiff`). Nearly every context module here is read-only against tables it doesn't own; there are no changesets/forms for creating games, tournaments, or results in this app.

### Domain shape

A `Tournament` has many `Round`s; a `Round` has many `Game`s. A `Game` is one debate room with four `Team`s in fixed seats — `og`/`oo`/`cg`/`co` (opening government/opposition, closing government/opposition) — always in that order (`@position_order` appears in several modules and must stay consistent). A `Team` has `PlayerInTournament` rows (not `Player` directly — players are looked up through the tournament-team join), and a `Player` carries the current cumulative `elo`/`games_played`.

Critically, **games don't store a post-match elo** — `Game.players_elos` is the *pre-match* snapshot and `Game.players_elo_diff` is the delta, both encoded as flat arrays covering all 8 players across the 4 teams (2 per team). `EloServer.Games.PlayerElos` decodes these arrays; the array index for a given player is `seat_slot * 2 + within_team_index`, where `within_team_index` comes from that team's `PlayerInTournament` rows in DB-returned order (no explicit `ORDER BY` — see the comment in `game_detail.ex` about why the teammate-lookup query shape must stay byte-for-byte identical everywhere it's used, so row order lines up with array index across modules).

### Time-travel rankings (`EloServer.Ranking`)

Only the *current* elo/games-played is persisted per player. Historical standings ("as of tournament X") are reconstructed on the fly by subtracting the elo/game diffs of every tournament that happened *after* that point — see `tournament_timeline/0`, `resolve_boundary/2`, and `snapshot/2`. `compare/3` diffs two such snapshots (by tournament, by date, or "current") to produce movement between any two points in time, including players who newly qualified or fell out of the active window between them.

Eligibility for the rating list (`eligible_at?/3`) requires: `games_played >= 20`, a game within the last 365 days, and not a tech-team player. Tech-team players are excluded from ELO pairwise scoring too (see below) but still appear in raw game data.

### Pairwise ELO scoring (`EloServer.Games.EloBreakdown`)

Ports a Kotlin reference implementation (`CalculateRoomEloDiff`) exactly: every non-tech pair of the four teams in a room is scored head-to-head (win/loss/draw by placement, weighted by elo-expected outcome), and a team's stored `elo_diff` is the sum of its pairwise terms times a historical K-factor. Since K isn't stored, per-opponent point contributions (`GameDetail`'s `points_vs_viewer`) are recovered by splitting the *stored* diff proportionally across the pairwise terms rather than recomputing K. `compute/1` asserts the pairwise terms cancel out (checksum <= 1e-9) as a consistency guard against results that don't match the game's actual persisted diff.

### Web layer

Three LiveViews under `lib/elo_server_web/live/`: `RatingLive` (current/point-in-time rankings), `CompareLive` (two-boundary comparison), `PlayerLive` (single player's profile + game history, built from `EloServer.PlayerReport`). No authentication/accounts exist in this app.

## Deployment

See `DEPLOY.md` for the full runbook (server access, deploy steps, rollback, DB dump/restore). Deploys are manual: SSH to the box, `git pull`, rebuild release, restart the `elo_server` systemd service — there is no CI/CD pipeline.
