defmodule Localize.CallerOptionKeysTest do
  use ExUnit.Case, async: true

  alias Localize.Number.Parser

  # An option a caller supplies must not become part of a `:persistent_term`
  # key, since a key is never removed and each new value would grow the
  # VM's memory for good. Each test passes values no other test uses and
  # checks that no key holds one of them, which tests running at the same
  # time cannot disturb.

  @unknown_atoms ~w(caller_key_one caller_key_two caller_key_three caller_key_four caller_key_five)a

  @currency_statuses [:all, :current, :historic, :tender, :annotated, :unannotated]

  describe "currency filters" do
    test "an :only entry that names no currency matches nothing and adds no key" do
      values = unique_strings("only")

      for value <- values do
        assert {:error, %Localize.UnknownCurrencyError{}} =
                 Parser.parse_currency_amount("$1,234.50", locale: :en, only: [value])
      end

      refute keyed?(values)
    end

    test "an :except entry that names no currency excludes nothing and adds no key" do
      values = unique_strings("except")

      for value <- values do
        assert {:ok, {:USD, amount}} =
                 Parser.parse_currency_amount("$1,234.50", locale: :en, except: [value, :JPY])

        assert Decimal.equal?(amount, Decimal.new("1234.50"))
      end

      refute keyed?(values)
    end

    test "a filter of currency codes reads as the codes and is not kept in :persistent_term" do
      for code <- [:EUR, :GBP, :CHF, :AUD, :NZD, :SEK, :NOK, :DKK, :PLN, :CZK] do
        assert {:ok, {:USD, _amount}} =
                 Parser.parse_currency_amount("$1,234.50", locale: :en, only: [:USD, code])

        assert {:ok, {:USD, _amount}} =
                 Parser.parse_currency_amount("$1,234.50",
                   locale: :en,
                   only: ["USD", Atom.to_string(code)]
                 )
      end

      refute Enum.any?(:persistent_term.get(), &code_filter_key?/1)
    end

    test "an entry of the wrong kind is still an error" do
      assert {:error, %Localize.InvalidValueError{}} =
               Parser.parse_currency_amount("$1,234.50", locale: :en, only: [1])
    end
  end

  describe ":separators" do
    test "a value that is not an atom is an error and adds no key" do
      values = unique_strings("separators")

      for value <- values do
        assert {:error, %Localize.InvalidValueError{}} =
                 Parser.parse("1,234", locale: :en, separators: value)
      end

      refute keyed?(values)
    end

    test "a set the locale lacks reads with its standard set and adds no key" do
      for name <- @unknown_atoms do
        assert {:ok, 1234} = Parser.parse("1,234", locale: :en, separators: name)
      end

      refute keyed?(@unknown_atoms)
    end

    test "a set the locale has is still read" do
      assert {:ok, 1234.56} = Parser.parse("1,234.56", locale: :"en-ZA", separators: :us)
    end
  end

  describe ":currency" do
    test "an unknown currency is an error and adds no key" do
      for currency <- @unknown_atoms do
        assert {:error, %Localize.UnknownCurrencyError{}} =
                 Parser.parse("1,234", locale: :en, currency: currency)
      end

      refute keyed?(@unknown_atoms)
    end
  end

  describe "collation :type" do
    test "a value that is not an atom is an error and adds no key" do
      values = unique_strings("type")

      for value <- values do
        assert {:error, %Localize.InvalidValueError{}} =
                 Localize.Collation.compare("a", "b", locale: :en, type: value)
      end

      refute keyed?(values)
    end

    test "a type no tailoring has collates in the standard order and adds no key" do
      for type <- @unknown_atoms do
        assert Localize.Collation.compare("côte", "coté", locale: :fr, type: type) ==
                 Localize.Collation.compare("côte", "coté", locale: :fr)
      end

      refute keyed?(@unknown_atoms)
    end
  end

  defp unique_strings(prefix) do
    unique = System.unique_integer([:positive])

    for index <- 1..50 do
      "caller-#{prefix}-#{unique}-#{index}"
    end
  end

  defp keyed?(values) do
    Enum.any?(:persistent_term.get(), fn {key, _value} ->
      Enum.any?(values, &holds?(key, &1))
    end)
  end

  defp holds?(value, value) do
    true
  end

  defp holds?(term, value) when is_tuple(term) do
    term
    |> Tuple.to_list()
    |> holds?(value)
  end

  defp holds?(list, value) when is_list(list) do
    Enum.any?(list, &holds?(&1, value))
  end

  defp holds?(_term, _value) do
    false
  end

  defp code_filter_key?({{Localize.Number.Lexicon, {:currencies, _locale, only, except}}, _}) do
    not Enum.all?(only ++ except, &(&1 in @currency_statuses))
  end

  defp code_filter_key?(_entry) do
    false
  end
end
