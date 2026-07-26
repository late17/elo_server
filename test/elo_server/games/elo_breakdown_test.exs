defmodule EloServer.Games.EloBreakdownTest do
  use ExUnit.Case, async: true

  alias EloServer.Games.EloBreakdown

  @teams [
    %{seat: :og, rating: 1826.0, result: :fourth, tech?: false},
    %{seat: :oo, rating: 1781.0, result: :third, tech?: false},
    %{seat: :cg, rating: 1634.0, result: :second, tech?: false},
    %{seat: :co, rating: 1765.0, result: :first, tech?: false}
  ]

  test "raw deltas sum to zero (checksum)" do
    assert {:ok, %{raw_deltas: raw_deltas}} = EloBreakdown.compute(@teams)

    raw_deltas
    |> Map.values()
    |> Enum.sum()
    |> then(&assert_in_delta(&1, 0.0, 1.0e-9))
  end

  test "per-opponent shares of a player's stored diff sum back to that diff" do
    assert {:ok, %{raw_deltas: raw_deltas, terms: terms}} = EloBreakdown.compute(@teams)

    viewer_seat = :og
    viewer_diff = -52.0
    raw_delta_total = Map.fetch!(raw_deltas, viewer_seat)

    shares =
      for opp <- [:oo, :cg, :co] do
        term = Map.fetch!(terms, {viewer_seat, opp})
        viewer_diff * term / raw_delta_total
      end

    assert_in_delta(Enum.sum(shares), viewer_diff, 1.0e-6)
  end

  test "tied teams contribute nothing between them" do
    teams = [
      %{seat: :og, rating: 1500.0, result: :advancing, tech?: false},
      %{seat: :oo, rating: 1500.0, result: :advancing, tech?: false},
      %{seat: :cg, rating: 1500.0, result: :eliminated, tech?: false},
      %{seat: :co, rating: 1500.0, result: :eliminated, tech?: false}
    ]

    assert {:ok, %{terms: terms}} = EloBreakdown.compute(teams)
    assert Map.fetch!(terms, {:og, :oo}) == 0.0
    assert Map.fetch!(terms, {:cg, :co}) == 0.0
  end

  test "tech teams are excluded from all pairings" do
    teams = [
      %{seat: :og, rating: 1500.0, result: :first, tech?: true},
      %{seat: :oo, rating: 1500.0, result: :second, tech?: false},
      %{seat: :cg, rating: 1500.0, result: :third, tech?: false},
      %{seat: :co, rating: 1500.0, result: :fourth, tech?: false}
    ]

    assert {:ok, %{raw_deltas: raw_deltas}} = EloBreakdown.compute(teams)
    refute Map.has_key?(raw_deltas, :og)
  end
end
