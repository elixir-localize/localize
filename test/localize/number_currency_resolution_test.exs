defmodule Localize.NumberCurrencyResolutionTest do
  @moduledoc """
  Resolving currency names, symbols and ISO 4217 codes in scanned text.

  A currency name or code names a currency only as a whole word: "dolars"
  ends in "ars" but names no Argentine peso, while "ars" standing alone is
  its code. A symbol, or a code written against digits, needs no space. With
  `:fuzzy`, a misspelled name resolves to the currency it most nearly spells,
  and text that spells none is left as it is.

  """

  use ExUnit.Case, async: true

  defp resolve(text, options \\ []) do
    text
    |> Localize.Number.scan()
    |> Localize.Number.resolve_currencies(options)
  end

  test "a name or code matches only as a whole word" do
    assert resolve("100 US dolars") == [100, " US dolars"]
    assert resolve("100 dolars ars") == [100, " dolars ", :ARS]
    assert resolve("100 US dollars") == [100, :USD]
    assert resolve("100 euros") == [100, :EUR]
  end

  test "a symbol, or a code against digits, needs no space" do
    assert resolve("$100") == [:USD, 100]
    assert resolve("USD100") == [:USD, 100]
    assert resolve("100 USD") == [100, :USD]
  end

  test "fuzzy matching resolves a misspelled name" do
    assert resolve("100 US dolars", fuzzy: 0.8) == [100, :USD]
    assert resolve("100 eurso", fuzzy: 0.8) == [100, :EUR]
    assert resolve("100 qwertyuiop", fuzzy: 0.8) == [100, " qwertyuiop"]
    assert Localize.Number.resolve_currency("US dolars", fuzzy: 0.8) == [:USD]
  end

  test "an invalid fuzzy value or locale is reported as itself, not as an unknown currency" do
    assert {:error, %Localize.InvalidValueError{value: 2.0}} =
             Localize.Number.resolve_currency("US dolars", fuzzy: 2.0)

    assert {:error, %Localize.InvalidLocaleError{}} =
             Localize.Number.resolve_currency("US dollars", locale: "zz-notalocale")

    assert {:error, %Localize.UnknownCurrencyError{}} =
             Localize.Number.resolve_currency("qwertyuiop")
  end

  # Regression: te spells XAF's singular and plural with the same number of
  # graphemes, so the plural could match as the singular and leave the rest
  # of the word in the remainder.
  test "the longest name matches even when a shorter one has as many graphemes" do
    {:ok, strings} = Localize.Currency.strings_for_currency(:XAF, :te)
    plural = Enum.max_by(strings, &byte_size/1)

    assert Localize.Number.resolve_currency(plural <> " 100", locale: :te) == [:XAF, " 100"]
    assert Localize.Number.resolve_currency("100 " <> plural, locale: :te) == ["100 ", :XAF]
  end
end
