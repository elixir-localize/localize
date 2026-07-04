defmodule Localize.Validity.SubdivisionTest do
  use ExUnit.Case, async: true

  alias Localize.Validity.Subdivision

  describe "validate/1" do
    test "validates a subdivision code as an atom with status" do
      assert Subdivision.validate("usca") == {:ok, :usca, :regular}
    end

    test "downcases before validation" do
      assert Subdivision.validate("GBENG") == {:ok, :gbeng, :regular}
    end

    test "returns the original code on error" do
      assert Subdivision.validate("zzzzzz") == {:error, "zzzzzz"}
    end

    test "nil is valid with nil status" do
      assert Subdivision.validate(nil) == {:ok, nil, nil}
    end
  end

  describe "normalize/1" do
    test "downcases binary codes" do
      assert Subdivision.normalize("GBENG") == "gbeng"
    end

    test "converts atom codes to downcased strings" do
      assert Subdivision.normalize(:GBENG) == "gbeng"
    end

    test "passes nil through" do
      assert Subdivision.normalize(nil) == nil
    end
  end
end
