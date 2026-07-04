defmodule Localize.Collation.NormalizerNumericTest do
  use ExUnit.Case, async: true

  alias Localize.Collation
  alias Localize.Collation.Normalizer

  describe "Normalizer.nfd/1 canonical reordering" do
    test "swaps combining marks into canonical order" do
      # U+0301 (ccc 230) must come after U+0323 (ccc 220).
      assert Normalizer.nfd("a\u0301\u0323") == "a\u0323\u0301"
    end

    test "reorders across multiple passes" do
      # ccc: U+05AE = 228, U+0301 = 230, U+0323 = 220.
      assert Normalizer.normalize_to_codepoints("a\u05AE\u0301\u0323", true) ==
               [0x61, 0x0323, 0x05AE, 0x0301]
    end

    test "an empty string normalizes to an empty string" do
      assert Normalizer.nfd("") == ""
    end

    test "canonically equivalent strings compare equal with normalization" do
      assert Collation.compare("a\u0301\u0323", "a\u0323\u0301", normalization: true) == :eq
    end
  end

  describe "numeric collation" do
    test "sorts by numeric value rather than digit sequence" do
      assert Collation.sort(["a10", "a2", "a007", "a7"], numeric: true) ==
               ["a2", "a007", "a7", "a10"]
    end

    test "leading zeros do not affect the numeric value" do
      assert Collation.compare("07", "7", numeric: true) == :eq
      assert Collation.compare("0", "00", numeric: true) == :eq
    end

    test "mixed digit and letter runs compare run by run" do
      assert Collation.compare("a1b2", "a1b10", numeric: true) == :lt

      assert Collation.sort(["a1b2", "a1b10", "a1a9"], numeric: true) ==
               ["a1a9", "a1b2", "a1b10"]
    end

    test "non-ASCII decimal digits participate in numeric ordering" do
      # Arabic-Indic 12 sorts before 21.
      assert Collation.compare("١٢", "٢١", numeric: true) == :lt
    end

    test "non-ASCII digit values come from the block zero, not cp mod 10" do
      # The Arabic-Indic block starts at U+0660 (2 mod 10), so a
      # rem(cp, 10) valuation wraps: ٩ (9) would value below ١ (1).
      assert Collation.compare("٢", "١٠", numeric: true) == :lt
      assert Collation.compare("١", "٩", numeric: true) == :lt

      assert Collation.sort(["١٠", "٢", "١", "٩"], numeric: true) ==
               ["١", "٢", "٩", "١٠"]
    end

    test "digits with the same numeric value compare equal across scripts" do
      # Arabic-Indic zero equals ASCII zero, and ٧ equals 7.
      assert Collation.compare("٠", "0", numeric: true) == :eq
      assert Collation.compare("٧", "7", numeric: true) == :eq
    end

    test "a digit run inside letters compares equal regardless of zero padding" do
      assert Collation.compare("a01b", "a1b", numeric: true) == :eq
    end
  end
end
