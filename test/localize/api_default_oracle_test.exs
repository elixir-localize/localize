defmodule Localize.ApiDefaultOracleTest do
  @moduledoc """
  Public functions called with their default arguments or with inputs the
  rest of the suite does not pass: unit arithmetic on decimal values, unit
  preferences for the default locale, time zone lookups in the default
  locale and the territory of a language tag that has none.

  Expected values come from independent sources: decimal arithmetic with
  CLDR 49's `en` unit pattern ("{0} meters"); TR35's unit preference
  algorithm, which takes the first preferred unit whose value is at least
  1, over CLDR 49's US length preferences (mile, foot, inch), so one meter
  is in feet; CLDR's `en` region format ("{0} Time") and time zone short
  ids ("ausyd" is Australia/Sydney); and CLDR's likely subtags ("fr" is
  "fr-Latn-FR").

  """

  use ExUnit.Case, async: true

  test "unit subtraction and absolute value with decimal values" do
    meters = &Localize.Unit.new!(&1, "meter")

    assert {:ok, difference} = Localize.Unit.sub(meters.(Decimal.new("5.5")), meters.(2))
    assert Localize.Unit.to_string(difference, locale: :en) == {:ok, "3.5 meters"}

    assert {:ok, difference} = Localize.Unit.sub(meters.(5), meters.(Decimal.new("2.5")))
    assert Localize.Unit.to_string(difference, locale: :en) == {:ok, "2.5 meters"}

    assert {:ok, absolute} = Localize.Unit.Math.abs(meters.(Decimal.new("-4.2")))
    assert Localize.Unit.to_string(absolute, locale: :en) == {:ok, "4.2 meters"}
  end

  test "unit preferences with the default options" do
    meter = Localize.Unit.new!(1, "meter")

    assert {:ok, [:foot], _options} = Localize.Unit.Preference.preferred_units(meter)
    assert Localize.Unit.Preference.preferred_units!(meter) == [:foot]
  end

  test "time zone lookups in the default locale" do
    assert Localize.DateTime.Timezone.generic_location_format("Europe/Rome") ==
             {:ok, "Italy Time"}

    australia = Localize.DateTime.Timezone.timezones_by_territory()[:AU]
    assert Enum.any?(australia, &(&1.short_zone == "ausyd"))
  end

  test "the territory of a language tag without one" do
    {:ok, tag} = Localize.LanguageTag.parse("fr")
    assert Localize.Territory.territory_from_locale(tag) == {:ok, :FR}
  end
end
