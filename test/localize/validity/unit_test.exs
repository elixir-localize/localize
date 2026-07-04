defmodule Localize.Validity.UnitTest do
  use ExUnit.Case, async: true

  alias Localize.Validity.Unit

  describe "validate/1" do
    test "validates a regular unit as an atom with status" do
      assert Unit.validate("meter") == {:ok, :meter, :regular}
    end

    test "accepts atom input" do
      assert Unit.validate(:liter) == {:ok, :liter, :regular}
    end

    test "downcases before validation" do
      assert Unit.validate("METER") == {:ok, :meter, :regular}
    end

    test "validates a compound unit code" do
      assert Unit.validate("meter_per_square_second") ==
               {:ok, :meter_per_square_second, :regular}
    end

    test "reports deprecated units with a :deprecated status" do
      assert Unit.validate("inch_hg") == {:ok, :inch_hg, :deprecated}
    end

    test "returns the original code on error" do
      assert Unit.validate("bogus") == {:error, "bogus"}
      assert Unit.validate("BOGUS") == {:error, "BOGUS"}
    end

    test "nil is valid with nil status" do
      assert Unit.validate(nil) == {:ok, nil, nil}
    end
  end

  describe "normalize/1" do
    test "downcases binary codes" do
      assert Unit.normalize("Meter") == "meter"
    end

    test "converts atom codes to downcased strings" do
      assert Unit.normalize(:METER) == "meter"
    end

    test "passes nil through" do
      assert Unit.normalize(nil) == nil
    end
  end
end
