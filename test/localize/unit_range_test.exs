defmodule Localize.UnitRangeTest do
  @moduledoc """
  Unit ranges, with the default options and in every width.

  Expected values come from ECMA-402's `formatRange` on `Intl.NumberFormat`
  with `style: "unit"` in Node 24 (ICU 77): "2–5 kilometers", "2–5 km" and
  "2–5km" in `en`, the French plural ranges "0–1 jour" and "1–2 jours", and
  "1.5–2.25 hours". A single unit, "2 kilometers", comes from `format` with
  the same options. Node writes a plain space where CLDR's French day
  pattern, in CLDR 48 and 49 alike, has a no-break space ("{0} jour"), which
  is the space the French ranges take here.

  """

  use ExUnit.Case, async: true

  setup do
    %{start: Localize.Unit.new!(2, "kilometer"), finish: Localize.Unit.new!(5, "kilometer")}
  end

  test "the default options format the range in the default locale", context do
    %{start: start, finish: finish} = context

    assert Localize.Unit.to_range_string(start, finish) == {:ok, "2–5 kilometers"}
    assert Localize.Unit.to_range_string!(start, finish) == "2–5 kilometers"
    assert {:ok, parts} = Localize.Unit.to_range_parts(start, finish)
    assert Enum.map_join(parts, & &1.value) == "2–5 kilometers"

    assert Enum.map_join(Localize.Unit.to_range_parts!(start, finish), & &1.value) ==
             "2–5 kilometers"

    assert Enum.map_join(Localize.Unit.to_parts!(start), & &1.value) == "2 kilometers"
  end

  test "each width", %{start: start, finish: finish} do
    for {format, expected} <- [long: "2–5 kilometers", short: "2–5 km", narrow: "2–5km"] do
      assert {format, Localize.Unit.to_range_string(start, finish, format: format, locale: :en)} ==
               {format, {:ok, expected}}
    end
  end

  test "French plural ranges" do
    for {from, to, expected} <- [{0, 1, "0–1 jour"}, {1, 2, "1–2 jours"}] do
      range_start = Localize.Unit.new!(from, "day")
      range_end = Localize.Unit.new!(to, "day")

      assert Localize.Unit.to_range_string(range_start, range_end, locale: :fr) == {:ok, expected}
    end
  end

  test "fractional endpoints" do
    range_start = Localize.Unit.new!(1.5, "hour")
    range_end = Localize.Unit.new!(2.25, "hour")

    assert Localize.Unit.to_range_string(range_start, range_end, locale: :en) ==
             {:ok, "1.5–2.25 hours"}
  end

  test "units of different kinds are an error, which the bang functions raise", %{start: start} do
    mass = Localize.Unit.new!(1, "kilogram")

    assert {:error, %Localize.InvalidValueError{}} = Localize.Unit.to_range_string(start, mass)
    assert_raise Localize.InvalidValueError, fn -> Localize.Unit.to_range_string!(start, mass) end
    assert_raise Localize.InvalidValueError, fn -> Localize.Unit.to_range_parts!(start, mass) end
  end
end
