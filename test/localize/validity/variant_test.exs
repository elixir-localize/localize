defmodule Localize.Validity.VariantTest do
  use ExUnit.Case, async: true

  alias Localize.Validity.Variant

  describe "validate/1 with a single variant" do
    test "validates a numeric variant" do
      assert Variant.validate("1901") == {:ok, "1901", :regular}
    end

    test "validates an alphabetic variant" do
      assert Variant.validate("rozaj") == {:ok, "rozaj", :regular}
    end

    test "downcases before validation" do
      assert Variant.validate("ROZAJ") == {:ok, "rozaj", :regular}
    end

    test "reports deprecated variants with a :deprecated status" do
      assert Variant.validate("heploc") == {:ok, "heploc", :deprecated}
    end

    test "special-cases the CLDR posix variant as :obsolete" do
      assert Variant.validate("posix") == {:ok, "posix", :obsolete}
    end

    test "returns the original code on error" do
      assert Variant.validate("notavariant") == {:error, "notavariant"}
    end
  end

  describe "validate/1 with a list of variants" do
    test "an empty list is valid with nil status" do
      assert Variant.validate([]) == {:ok, [], nil}
    end

    test "validates each variant, accumulating in reverse order" do
      assert Variant.validate(["fonipa", "scouse"]) ==
               {:ok, ["scouse", "fonipa"], :regular}
    end

    test "halts on the first invalid variant" do
      assert Variant.validate(["fonipa", "bogus"]) == {:error, "bogus"}
    end
  end

  describe "normalize/1" do
    test "downcases a binary variant" do
      assert Variant.normalize("FONIPA") == "fonipa"
    end

    test "downcases and sorts a list of variants" do
      assert Variant.normalize(["SCOUSE", "FONIPA"]) == ["fonipa", "scouse"]
    end

    test "passes nil through" do
      assert Variant.normalize(nil) == nil
    end
  end
end
