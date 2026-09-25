defmodule Localize.PublicApiOracleTest do
  @moduledoc """
  Public functions the rest of the suite leaves uncalled: default-argument
  and bang variants, compound units, alternative number systems and the
  errors bad options return.

  Expected values come from independent sources: CLDR 48's `en` currency
  symbols ("$") and its root ellipsis patterns ("… {0}", "{0} … {1}");
  ICU4C 78.3's `RuleBasedNumberFormat` ("twenty-one", "twenty twenty-four");
  ECMA-402 in Node 24 (ICU 77) for lists ("a and b") and compound units
  ("5 liters per kilometer", "5 L/km"); CLDR's likely subtags ("zh" is
  "zh-Hans-CN"); TR35's pattern quoting, where two single quotes are an
  apostrophe ("h 'o''clock'"); and the digits themselves for Arabic-Indic
  input.

  """

  use ExUnit.Case, async: true

  test "word ellipses and a quote format that does not exist in the default locale" do
    assert Localize.ellipsis("And so on", location: :before, format: :word) ==
             {:ok, "… And so on"}

    assert Localize.ellipsis(["start", "end"], format: :word) == {:ok, "start … end"}

    assert {:error, %Localize.InvalidValueError{value: :bogus}} =
             Localize.quote("text", format: :bogus)
  end

  test "currency symbols" do
    assert Localize.Currency.symbol(:USD) == {:ok, "$"}
    assert Localize.Currency.symbol(:USD, :narrow) == {:ok, "$"}
  end

  test "rule-based number formats named by atom or string" do
    assert Localize.Number.Rbnf.to_string(21, :spellout_numbering) == {:ok, "twenty-one"}
    assert Localize.Number.Rbnf.to_string(21, "spellout-numbering") == {:ok, "twenty-one"}

    assert Localize.Number.Rbnf.to_string(2024, :spellout_numbering_year) ==
             {:ok, "twenty twenty-four"}
  end

  test "lists interspersed with the default options, and a list style that does not exist" do
    assert Localize.List.intersperse(["a", "b"]) == {:ok, ["a", " and ", "b"]}

    assert {:error, %Localize.InvalidValueError{value: :bogus}} =
             Localize.List.to_string(["a", "b"], list_style: :bogus)

    assert_raise Localize.InvalidValueError, fn ->
      Localize.List.to_parts!(["a", "b"], list_style: :bogus)
    end
  end

  test "duration options that do not exist, and quoted text in a time pattern" do
    assert_raise Localize.InvalidValueError, fn ->
      Localize.Duration.to_parts!(%Localize.Duration{hour: 1}, format: :bogus)
    end

    assert {:error, %Localize.InvalidValueError{value: {:hour, :sometimes}}} =
             Localize.Duration.to_string(%Localize.Duration{hour: 1}, display: [hour: :sometimes])

    assert Localize.Duration.to_time_string(Localize.Duration.new_from_seconds(3600),
             format: "h 'o''clock'"
           ) == {:ok, "1 o'clock"}
  end

  test "compound units joined by per" do
    for {number, unit, format, expected} <- [
          {5, "liter-per-kilometer", :long, "5 liters per kilometer"},
          {5, "liter-per-kilometer", :short, "5 L/km"},
          {5, "liter-per-kilometer", :narrow, "5L/km"},
          {3, "megabyte-per-second", :long, "3 megabytes per second"},
          {60, "kilometer-per-hour", :long, "60 kilometers per hour"},
          {1, "meter-per-second", :short, "1 m/s"}
        ] do
      assert {unit, format,
              Localize.Unit.to_string(Localize.Unit.new!(number, unit),
                format: format,
                locale: :en
              )} ==
               {unit, format, {:ok, expected}}
    end
  end

  test "parsing digits of a named number system" do
    assert Localize.Number.parse("١٢٣", number_system: :arab) == {:ok, 123}

    assert {:error, %Localize.InvalidValueError{value: :bogus}} =
             Localize.Number.parse("123", number_system: :bogus)
  end

  test "language tag bang functions" do
    {:ok, tag} = Localize.LanguageTag.parse("en-Latn-US")

    assert tag |> Localize.LanguageTag.canonicalize!() |> Localize.LanguageTag.to_string() ==
             "en-Latn-US"

    {:ok, chinese} = Localize.LanguageTag.parse("zh")

    assert chinese
           |> Localize.LanguageTag.add_likely_subtags!()
           |> Localize.LanguageTag.to_string() == "zh-Hans-CN"

    {:ok, maximized} = Localize.LanguageTag.parse("zh-Hans-CN")

    assert maximized
           |> Localize.LanguageTag.remove_likely_subtags!()
           |> Localize.LanguageTag.to_string() == "zh"
  end

  test "a parsed language tag interpolates as its BCP 47 form" do
    {:ok, parsed} = Localize.LanguageTag.parse("en-US")
    {:ok, validated} = Localize.validate_locale("en-US")

    assert "#{parsed}" == "en-US"
    assert "#{validated}" == "en-US"
  end
end
