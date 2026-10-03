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

  # Regression: equally close strings ("ac" and "ag" are equally far from
  # "ab") were taken in whatever order the map yielded them, which for more
  # than 32 strings is hash order.
  test "fuzzy matching takes the alphabetically first of equally close strings" do
    strings =
      for(i <- 1..40, into: %{}, do: {"zzzzzzzz#{i}", :ZZZ})
      |> Map.put("ac", :AC)
      |> Map.put("ag", :AG)

    assert Localize.Number.Parser.find_and_replace(strings, "ab", 0.5) == {:ok, [:AC]}
    assert Localize.Number.resolve_currency("usx", fuzzy: 0.7) == [:UGX]
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

  # In `fr` "$" is the narrow symbol of the Canadian, US and Australian
  # dollars among others, and names none of them alone. CLDR's `fr-CA`
  # writes the Canadian dollar "$", and is the same language as `fr` in
  # another territory (a match distance of 4), where every other dollar's
  # locales are other languages. Spanish is spoken in Mexico, the United
  # States and Argentina alike, each writing its own dollar or peso "$".
  describe "a string several of the locale's currencies share" do
    test "names the currency of the nearest locale that writes it" do
      assert Localize.Number.resolve_currency("$100", locale: :fr) == [:CAD, "100"]
      assert resolve("100 $", locale: :fr) == [100, :CAD]
    end

    test "stays unknown where two currencies' locales are as near" do
      assert {:error, %Localize.UnknownCurrencyError{}} =
               Localize.Number.resolve_currency("$100", locale: :es)
    end

    test "is listed with its claimants" do
      assert {:ok, %{"$" => claimants}} = Localize.Currency.ambiguous_currency_strings(:fr)
      assert [:AUD, :CAD, :USD] -- claimants == []

      assert {:ok, strings} = Localize.Currency.currency_strings(:fr)
      refute Map.has_key?(strings, "$")
    end

    test "is resolved only among the currencies the filters keep" do
      assert Localize.Number.resolve_currency("$100", locale: :fr, only: [:USD, :AUD]) ==
               {:error, Localize.UnknownCurrencyError.exception(currency: "$100")}
    end
  end
end
