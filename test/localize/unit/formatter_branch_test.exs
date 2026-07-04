defmodule Localize.Unit.FormatterBranchTest do
  use ExUnit.Case, async: true

  alias Localize.Unit

  defp unit!(value, name), do: Unit.new!(value, name)

  describe "token-list unit patterns" do
    test "Japanese fahrenheit uses a prefix-and-suffix token pattern" do
      assert Unit.to_string(unit!(30, "fahrenheit"), locale: "ja") == {:ok, "華氏 30 度"}
    end

    test "Decimal values resolve a plural form" do
      assert Unit.to_string(unit!(Decimal.new("2.5"), "meter")) == {:ok, "2.5 meters"}
    end
  end

  describe "currency-per-unit pattern shapes" do
    test "a prefix-position per-unit pattern places the currency after the unit" do
      assert Unit.to_string(unit!(5, "curr-usd-per-meter"), locale: "ko") ==
               {:ok, "미터당 US$5.00"}
    end

    test "a denominator without a CLDR per-unit pattern falls back to a plain join" do
      assert Unit.to_string(unit!(5, "curr-usd-per-century")) == {:ok, "$5.00 per century"}
    end
  end

  describe "NIF backend" do
    @describetag :nif

    test "formats through the NIF when requested" do
      if Localize.Nif.available?() do
        assert Localize.Unit.Formatter.to_string(unit!(5, "meter"), backend: :nif) ==
                 {:ok, "5 meters"}
      end
    end

    test "returns an error for an invalid locale" do
      if Localize.Nif.available?() do
        assert {:error, %Localize.InvalidLocaleError{}} =
                 Localize.Unit.Formatter.to_string(unit!(5, "meter"),
                   backend: :nif,
                   locale: "zz-bogus"
                 )
      end
    end
  end
end
