defmodule EloServer.Repo.Migrations.CreateLegacySchema do
  use Ecto.Migration

  @moduledoc """
  Mirrors the tables the local Kotlin app's Exposed ORM owns
  (`dbwork/models/DatabaseEntities.kt`), so `mix test`/`mix ecto.setup`
  can stand up a matching schema locally. Production never runs
  `mix ecto.migrate` (see DEPLOY.md) — its schema is created once by
  the Kotlin app and kept in sync by the SYNC API, not by this file.
  """

  def up do
    execute """
    CREATE TABLE "Player" (
      "ID" uuid PRIMARY KEY,
      "Name" varchar(255) NOT NULL,
      "isTechTeam" boolean NOT NULL,
      "ELO" double precision NOT NULL,
      "gamesPlayed" integer NOT NULL,
      "mapNames" text NOT NULL
    )
    """

    execute """
    CREATE TABLE "Tournament" (
      "ID" uuid PRIMARY KEY,
      "Name" varchar(255) NOT NULL,
      short_name varchar(50) NOT NULL,
      date date NOT NULL,
      semi_final boolean NOT NULL DEFAULT false,
      novice_final boolean NOT NULL DEFAULT false,
      junior_final boolean NOT NULL DEFAULT false,
      final boolean NOT NULL DEFAULT false
    )
    """

    execute """
    CREATE UNIQUE INDEX tournament_short_name_index ON "Tournament" (short_name)
    """

    execute """
    CREATE TABLE "Team" (
      "ID" uuid PRIMARY KEY,
      "Name" varchar(255) NOT NULL,
      "TournamentId" uuid NOT NULL REFERENCES "Tournament" ("ID")
    )
    """

    execute """
    CREATE TABLE "Round" (
      "ID" uuid PRIMARY KEY,
      "Type" varchar(50) NOT NULL,
      "Number" integer,
      "TournamentId" uuid NOT NULL REFERENCES "Tournament" ("ID")
    )
    """

    execute """
    CREATE TABLE "PlayerInTournament" (
      "ID" uuid PRIMARY KEY,
      "NameInTournament" varchar(255) NOT NULL,
      "TeamIdInTournament" uuid NOT NULL REFERENCES "Team" ("ID"),
      "PlayerId" uuid REFERENCES "Player" ("ID")
    )
    """

    execute """
    CREATE TABLE "Game" (
      "ID" uuid PRIMARY KEY,
      "isEliminating" boolean NOT NULL,
      "RoundId" uuid NOT NULL REFERENCES "Round" ("ID"),
      "OG" uuid NOT NULL REFERENCES "Team" ("ID"),
      "OO" uuid NOT NULL REFERENCES "Team" ("ID"),
      "CG" uuid NOT NULL REFERENCES "Team" ("ID"),
      "CO" uuid NOT NULL REFERENCES "Team" ("ID"),
      "Places" varchar(500) NOT NULL,
      "playersElos" text NOT NULL,
      "playersEloDiff" text NOT NULL,
      "gameType" text NOT NULL
    )
    """
  end

  def down do
    execute ~s(DROP TABLE "Game")
    execute ~s(DROP TABLE "PlayerInTournament")
    execute ~s(DROP TABLE "Round")
    execute ~s(DROP TABLE "Team")
    execute ~s(DROP INDEX tournament_short_name_index)
    execute ~s(DROP TABLE "Tournament")
    execute ~s(DROP TABLE "Player")
  end
end
