defmodule Localize.Message.PluralSelectionTest do
  @moduledoc """
  Plural selection on the number a numeric function displays.

  MF2 applies the plural rules to the operand "as modified by function
  options" (tr35-messageFormat.md, Rule Selection), and TR35 takes the plural
  operands from the digits shown. Expected categories come from ICU4C 78.3's
  MessageFormat 2 where it displays the same digits, and otherwise from the
  CLDR plural rules applied to the displayed number: ICU4C formats neither
  `:percent` nor `maximumFractionDigits=0`.

  """

  use ExUnit.Case, async: true

  @variants "zero {{zero}} one {{one}} two {{two}} few {{few}} many {{many}} * {{other}}"

  defp select(declaration, value, locale) do
    message = ".input {$n #{declaration}}\n.match $n\n" <> @variants
    Localize.Message.format(message, %{"n" => value}, locale: locale)
  end

  describe "as ICU4C selects" do
    test "fraction digits an option adds are visible fraction digits" do
      assert select(":number minimumFractionDigits=1", 2, :ru) == {:ok, "other"}
      assert select(":number minimumFractionDigits=1", 21, :ru) == {:ok, "other"}
      assert select(":number minimumFractionDigits=1", 11, :ru) == {:ok, "other"}
      assert select(":number minimumFractionDigits=1", 21, :pl) == {:ok, "other"}
      assert select(":number minimumFractionDigits=1", 1, :en) == {:ok, "other"}
      assert select(":number minimumFractionDigits=1", 1, :fr) == {:ok, "one"}
      assert select(":number minimumFractionDigits=1", 1, :ar) == {:ok, "one"}
      assert select(":number minimumFractionDigits=1", 1, :lt) == {:ok, "one"}
    end

    test "a float that displays without a fraction selects as an integer" do
      assert select(":number", 100.0, :ru) == {:ok, "many"}
      assert select(":number", 100.0, :pl) == {:ok, "many"}
    end

    test "significant digits round the number selected" do
      assert select(":number maximumSignificantDigits=2", 101, :ru) == {:ok, "many"}
      assert select(":number maximumSignificantDigits=2", 101, :lt) == {:ok, "other"}
    end
  end

  describe "by the CLDR plural rules for the displayed number" do
    # 0.215 displays as "22 %" and 0.05 as "5 %".
    test ":percent selects the percentage displayed" do
      assert select(":percent", 0.215, :ru) == {:ok, "few"}
      assert select(":percent", 0.05, :ru) == {:ok, "many"}
    end

    # 1.5 displays as "2", and 0.9999 with two significant digits as "1".
    test "rounding to the digits displayed" do
      assert select(":number maximumFractionDigits=0", 1.5, :ru) == {:ok, "few"}
      assert select(":number maximumSignificantDigits=2", 0.9999, :en) == {:ok, "one"}
    end

    test ":offset selects the adjusted number" do
      assert select(":offset add=1", 1, :ru) == {:ok, "few"}
    end

    test ":integer selects a Decimal operand truncated" do
      assert select(":integer", Decimal.new("21.5"), :ru) == {:ok, "one"}

      message = ".input {$n :integer}\n{{{$n}}}"
      bindings = %{"n" => Decimal.new("21.5")}
      assert Localize.Message.format(message, bindings, locale: :en) == {:ok, "21"}
    end
  end
end
