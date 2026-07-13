defmodule EloServer.Games.RoomResults do
  @moduledoc """
  Decodes the `Places` column on a `Game`.

  The stored value is `"<PREFIX>:<digits>"` where `<digits>` has one
  character per room position, in the fixed order `[OG, OO, CG, CO]`
  (mirrors the original Kotlin `RoomResults.decode`):

    * `"REG:...."` — each digit is a `RoomPlaces` code (place finished),
      decoded into `%ByPlace{}`.
    * `"ADV:...."` — each digit is a `RoomAdvancing` code (advanced or
      eliminated), decoded into `%ByAdvancing{}`.
  """

  defmodule ByPlace do
    @moduledoc "One team per finishing place: :first, :second, :third, :fourth."
    defstruct places: %{}
  end

  defmodule ByAdvancing do
    @moduledoc "Teams grouped by whether they advanced: :advancing, :eliminated."
    defstruct groups: %{}
  end

  @position_order [:og, :oo, :cg, :co]

  @room_places %{3 => :first, 2 => :second, 1 => :third, 0 => :fourth}
  @room_advancing %{1 => :advancing, 0 => :eliminated}

  @doc """
  Decodes `value` (the raw `Places` string) given a map of position to team id,
  e.g. `%{og: game.og_team_id, oo: game.oo_team_id, cg: game.cg_team_id, co: game.co_team_id}`.
  """
  def decode(value, position_to_team_id) when is_binary(value) and is_map(position_to_team_id) do
    [prefix, digits] = String.split(value, ":", parts: 2)

    if String.length(digits) != length(@position_order) do
      raise ArgumentError,
            "Expected #{length(@position_order)} place digits, got: #{value}"
    end

    digit_codes = digits |> String.to_charlist() |> Enum.map(&(&1 - ?0))

    case prefix do
      "REG" ->
        places =
          @position_order
          |> Enum.zip(digit_codes)
          |> Map.new(fn {position, code} ->
            {Map.fetch!(@room_places, code), Map.fetch!(position_to_team_id, position)}
          end)

        %ByPlace{places: places}

      "ADV" ->
        groups =
          @position_order
          |> Enum.zip(digit_codes)
          |> Enum.reduce(%{advancing: [], eliminated: []}, fn {position, code}, acc ->
            group = Map.fetch!(@room_advancing, code)
            team_id = Map.fetch!(position_to_team_id, position)
            Map.update!(acc, group, &(&1 ++ [team_id]))
          end)

        %ByAdvancing{groups: groups}

      other ->
        raise ArgumentError, "Unknown RoomResults type: #{other}"
    end
  end

  @doc "Decodes `game.places` using the game's own OG/OO/CG/CO team ids."
  def decode(%{places: places} = game) do
    decode(places, %{
      og: game.og_team_id,
      oo: game.oo_team_id,
      cg: game.cg_team_id,
      co: game.co_team_id
    })
  end
end
