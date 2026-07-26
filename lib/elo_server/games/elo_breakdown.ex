defmodule EloServer.Games.EloBreakdown do
  @moduledoc """
  Ports the pairwise scoring from the Kotlin `CalculateRoomEloDiff`: each pair
  of (non-tech) teams is compared by actual room result, weighted by the
  elo-expected outcome. The per-team raw delta is the sum of its pairwise
  terms; the stored `elo_diff` is `raw_delta * player_k`, so splitting a
  player's stored diff across opponents in proportion to their pairwise terms
  reproduces the same per-opponent shares without needing the historical K.

  Note: `is_tech_team` is read as it stands today, not as it was at game
  time — if a player's tech status changed since, older games could compute
  slightly different pairings than they originally did. The checksum guard
  below is the safety net for that drift.
  """

  @f_400 400.0

  @place_points %{
    first: 3,
    second: 2,
    third: 1,
    fourth: 0,
    advancing: 1,
    eliminated: 0
  }

  @doc """
  `teams` is a list of `%{seat:, rating:, result:, tech?:}`.

  Returns `{:ok, %{raw_deltas: %{seat => float}, terms: %{{seat_a, seat_b} => float}}}`
  or `{:error, :checksum_failed}` if the pairwise terms don't cancel out
  (mirrors the Kotlin's `require(checksum.absoluteValue <= 1e-9)`).
  """
  def compute(teams) do
    pairs = pairs(teams)

    terms =
      Map.new(pairs, fn {a, b} ->
        {{a.seat, b.seat}, pair_term(a, b)}
      end)

    raw_deltas =
      Enum.reduce(terms, %{}, fn {{seat_a, seat_b}, term}, acc ->
        acc
        |> Map.update(seat_a, term, &(&1 + term))
        |> Map.update(seat_b, -term, &(&1 - term))
      end)

    checksum = raw_deltas |> Map.values() |> Enum.sum()

    if abs(checksum) <= 1.0e-9 do
      {:ok, %{raw_deltas: raw_deltas, terms: symmetric_terms(terms)}}
    else
      {:error, :checksum_failed}
    end
  end

  defp pairs(teams) do
    for {a, i} <- Enum.with_index(teams),
        b <- Enum.drop(teams, i + 1),
        not a.tech?,
        not b.tech? do
      {a, b}
    end
  end

  defp pair_term(a, b) do
    score =
      cond do
        Map.fetch!(@place_points, a.result) > Map.fetch!(@place_points, b.result) -> 1.0
        Map.fetch!(@place_points, a.result) < Map.fetch!(@place_points, b.result) -> 0.0
        true -> 0.5
      end

    if score == 0.5 do
      0.0
    else
      expected_score = 1.0 / (:math.pow(10.0, (b.rating - a.rating) / @f_400) + 1.0)
      score - expected_score
    end
  end

  defp symmetric_terms(terms) do
    Enum.reduce(terms, terms, fn {{a, b}, term}, acc ->
      Map.put(acc, {b, a}, -term)
    end)
  end
end
