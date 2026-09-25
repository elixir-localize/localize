defmodule Localize.DurationFormattingTest do
  @moduledoc """
  Durations formatted as lists of units, through every public entry point.

  Expected values come from ECMA-402's `Intl.DurationFormat` in Node 24
  (ICU 77) in the long, short and narrow styles, and from its
  `formatToParts`, which tags each number with its unit. Node writes a plain
  space where CLDR's French hour pattern has a no-break space
  ("{0} heures", while its minute pattern has a plain one), so the French
  case takes CLDR 48's spaces.

  """

  use ExUnit.Case, async: true

  @cases [
    {:en, :long, %Localize.Duration{hour: 2, minute: 30}, "2 hours, 30 minutes"},
    {:en, :short, %Localize.Duration{hour: 2, minute: 30}, "2 hr, 30 min"},
    {:en, :narrow, %Localize.Duration{hour: 2, minute: 30}, "2h 30m"},
    {:en, :long, %Localize.Duration{year: 1, month: 2, day: 3}, "1 year, 2 months, 3 days"},
    {:en, :long, %Localize.Duration{hour: 2}, "2 hours"},
    {:en, :long, %Localize.Duration{month: 11, day: 30}, "11 months, 30 days"},
    {:fr, :long, %Localize.Duration{hour: 2, minute: 30}, "2 heures et 30 minutes"},
    {:de, :short, %Localize.Duration{day: 1, hour: 5}, "1 Tg., 5 Std."}
  ]

  test "durations match ICU through to_string and to_parts" do
    for {locale, format, duration, expected} <- @cases do
      options = [format: format, locale: locale]
      label = {locale, format, expected}

      assert {label, Localize.Duration.to_string(duration, options)} == {label, {:ok, expected}}
      assert {label, Localize.Duration.to_string!(duration, options)} == {label, expected}

      assert {:ok, parts} = Localize.Duration.to_parts(duration, options)
      assert {label, Enum.map_join(parts, & &1.value)} == {label, expected}

      assert {label, Enum.map_join(Localize.Duration.to_parts!(duration, options), & &1.value)} ==
               {label, expected}
    end
  end

  test "each number part carries its unit, as ECMA-402's formatToParts does" do
    duration = %Localize.Duration{hour: 2, minute: 30}

    assert {:ok, parts} = Localize.Duration.to_parts(duration, locale: :en)

    assert for(%{type: :integer} = part <- parts, do: {part.value, part.unit}) ==
             [{"2", :hour}, {"30", :minute}]
  end

  test "the default options format in the default locale" do
    duration = %Localize.Duration{hour: 2, minute: 30}

    assert Localize.Duration.to_string!(duration) == "2 hours, 30 minutes"
    assert {:ok, parts} = Localize.Duration.to_parts(duration)
    assert Enum.map_join(parts, & &1.value) == "2 hours, 30 minutes"

    assert Enum.map_join(Localize.Duration.to_parts!(duration), & &1.value) ==
             "2 hours, 30 minutes"
  end
end
