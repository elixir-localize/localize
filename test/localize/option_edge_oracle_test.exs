defmodule Localize.OptionEdgeOracleTest do
  @moduledoc """
  Options and inputs at the edges of the public API: options given as
  `nil`, currency formats without the symbol, NaN and infinity with a
  currency display name, numeric territory codes, currency filters, the
  parent of a locale with a variant, a usage with no unit preferences and
  lists that treat the middle as the end.

  Expected values come from independent sources: CLDR 48's `en` currency
  and accounting formats with `alt="noCurrency"` ("#,##0.00" and
  "#,##0.00;(#,##0.00)"), its territory aliases ("280" is DE, "062" is
  "034 143"), its `en` currency display names, of which these 70 carry a
  parenthesized annotation, its `en` list patterns and its length unit
  preferences (mile first for the US default usage); ICU4C 78.3 for Thai
  digits under `-u-nu-thai` and for "NaN US dollars" and "∞ US dollars";
  TR35's half-even default rounding, its truncation inheritance, which
  drops a variant first, and its fallback to the default usage; and the
  international mile of exactly 1,609.344 meters.

  """

  use ExUnit.Case, async: true

  @annotated ~w(AFA ALK AOK AON AOR ARL ARM ARP AZM BAD BAN BEC BEL BGO BOL BRB BRC BRE
                BRN BRR BRZ BYB BYR CLF CNH CSD ESA ESB GHC ILR ISJ KRH KRO MKN MRO MVP
                MXP MZM NIC PES PLZ ROL RUR SDD SDP SLL STD TMM TRL UGS USN USS UYI UYP
                VEB VEF VNN XBC XBD YUD YUM YUN YUR ZAL ZMK ZRN ZRZ ZWD ZWL ZWR)a

  test "options given as nil take their defaults" do
    assert Localize.Number.to_string(123, locale: "en-u-nu-thai", number_system: nil) ==
             {:ok, "๑๒๓"}

    assert Localize.Number.to_string(123, locale: :en, number_system: nil) == {:ok, "123"}
    assert Localize.Number.to_string(2.5, format: "#", rounding_mode: nil) == {:ok, "2"}
    assert Localize.Number.to_string(3.5, format: "#", rounding_mode: nil) == {:ok, "4"}
  end

  test "currency and accounting formats without the symbol" do
    options = [currency: :USD, currency_symbol: :none, locale: :en]

    assert Localize.Number.to_string(1234.5, [format: :currency] ++ options) ==
             {:ok, "1,234.50"}

    assert Localize.Number.to_string(-1234.5, [format: :accounting] ++ options) ==
             {:ok, "(1,234.50)"}
  end

  test "a currency display name for NaN and infinity" do
    options = [format: "#,##0.00 ¤¤¤", currency: :USD, locale: :en]

    assert Localize.Number.to_string(Decimal.new("NaN"), options) == {:ok, "NaN US dollars"}
    assert Localize.Number.to_string(Decimal.new("Infinity"), options) == {:ok, "∞ US dollars"}
  end

  test "numeric territory codes that CLDR replaces" do
    assert Localize.validate_territory(280) == {:ok, :DE}
    assert Localize.validate_territory(62) == {:ok, :"034"}
  end

  test "currency filters by code, by annotation and with every currency" do
    {:ok, currencies} = Localize.Currency.currencies_for_locale(:en)

    assert Map.keys(Localize.Currency.currency_filter(currencies, [:USD])) == [:USD]
    assert Map.keys(Localize.Currency.currency_filter(currencies, "EUR")) == [:EUR]

    assert map_size(Localize.Currency.currency_filter(currencies, [:USD, :all])) ==
             map_size(currencies)

    annotated = Localize.Currency.currency_filter(currencies, :annotated)
    assert annotated |> Map.keys() |> Enum.sort() == @annotated
  end

  test "a locale's variant is the first subtag its parent drops" do
    assert {:ok, parent} = Localize.Locale.parent("ca-ES-valencia")
    assert {parent.language, parent.territory, parent.language_variants} == {:ca, :ES, []}
  end

  test "a usage with no preferences for the unit's category falls back to the default usage" do
    assert {:ok, meters} = Localize.Unit.new(100, "meter", usage: "food")
    assert {:ok, miles} = Localize.Unit.convert_measurement_system(meters, :us)
    assert miles.name == "mile"

    value =
      if is_struct(miles.value, Decimal), do: Decimal.to_float(miles.value), else: miles.value

    assert_in_delta value, 100 / 1609.344, 1.0e-12
  end

  test "lists that treat the middle as the end" do
    options = [treat_middle_as_end: true, locale: :en]

    assert Enum.map_join(Localize.List.to_parts!(["a", "b"], options), & &1.value) == "a, b"

    assert Enum.map_join(Localize.List.to_parts!(["a", "b", "c"], options), & &1.value) ==
             "a, b, c"
  end
end
