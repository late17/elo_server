defmodule EloServer.Games.PlayerElos do
  @moduledoc """
  Decodes the `playersElos` / `playersEloDiff` columns on a `Game`.

  Both are newline-separated floats, two per team (one per player), in the
  fixed team order `[OG, OO, CG, CO]` — 8 values total.
  """

  @position_order [:og, :oo, :cg, :co]
  @players_per_team 2

  @doc "Parses a raw newline-separated string into a flat list of floats."
  def parse(value) when is_binary(value) do
    value
    |> String.split("\n", trim: true)
    |> Enum.map(&parse_float/1)
  end

  @doc """
  Parses a raw string and groups the values by team, in `[OG, OO, CG, CO]`
  order, e.g. `%{og: [1500.0, 1500.0], oo: [...], cg: [...], co: [...]}`.
  """
  def parse_by_team(value) when is_binary(value) do
    value
    |> parse()
    |> Enum.chunk_every(@players_per_team)
    |> then(&Enum.zip(@position_order, &1))
    |> Map.new()
  end

  defp parse_float(str) do
    str
    |> String.trim()
    |> String.to_float()
  end
end
