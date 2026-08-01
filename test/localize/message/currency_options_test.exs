defmodule Localize.Message.CurrencyOptionsTest do
  use ExUnit.Case, async: true

  alias Localize.Message.{Interpreter, Parser}

  defp format(source, bindings) do
    {:ok, parsed} = Parser.parse(source)
    options = [locale: "en-US"]

    case Interpreter.format_list(parsed, bindings, options) do
      {:ok, iolist, _, _} -> :erlang.iolist_to_binary(iolist)
      {:error, iolist, _, _} -> :erlang.iolist_to_binary(iolist)
    end
  end

  describe "currency formatting" do
    test "basic currency with currency code" do
      assert format("{$amount :currency currency=USD}", %{"amount" => 42.50}) == "$42.50"
    end

    test "currency with integer value" do
      assert format("{$amount :currency currency=EUR}", %{"amount" => 100}) == "€100.00"
    end

    test "currency with string value" do
      assert format("{$amount :currency currency=USD}", %{"amount" => "42.50"}) == "$42.50"
    end
  end

  describe "currencyDisplay option" do
    test "narrowSymbol displays narrow currency symbol" do
      assert format(
               "{$amount :currency currency=USD currencyDisplay=narrowSymbol}",
               %{"amount" => 42.50}
             ) == "$42.50"
    end

    test "code displays ISO currency code" do
      result =
        format(
          "{$amount :currency currency=USD currencyDisplay=code}",
          %{"amount" => 42.50}
        )

      # CLDR uses non-breaking space (U+00A0) between ISO code and number
      assert result == "USD\u00A042.50"
    end

    test "default displays standard currency symbol" do
      assert format("{$amount :currency currency=EUR}", %{"amount" => 42.50}) == "€42.50"
    end
  end

  describe "currencySign option" do
    test "accounting wraps negative values in parentheses" do
      assert format(
               "{$amount :currency currency=USD currencySign=accounting}",
               %{"amount" => -42.50}
             ) == "($42.50)"
    end

    test "standard uses minus sign for negative values" do
      result = format("{$amount :currency currency=USD}", %{"amount" => -42.50})
      assert result =~ "-"
      assert result =~ "42.50"
    end

    test "accounting with positive value formats normally" do
      assert format(
               "{$amount :currency currency=USD currencySign=accounting}",
               %{"amount" => 42.50}
             ) == "$42.50"
    end
  end

  describe "combined options" do
    test "currencyDisplay=code with currencySign=accounting" do
      result =
        format(
          "{$amount :currency currency=USD currencyDisplay=code currencySign=accounting}",
          %{"amount" => -42.50}
        )

      assert result =~ "USD"
      assert result =~ "42.50"
      # Accounting format wraps in parentheses
      assert result =~ "("
    end

    test "currency with minimumFractionDigits" do
      assert format(
               "{$amount :currency currency=USD minimumFractionDigits=0}",
               %{"amount" => 42}
             ) == "$42"
    end
  end
end
