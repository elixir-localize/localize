defmodule Localize.Validity.ScriptTest do
  use ExUnit.Case, async: true

  alias Localize.Validity.Script

  describe "validate/1" do
    test "validates a capitalized script code as an atom with status" do
      assert Script.validate("Latn") == {:ok, :Latn, :regular}
    end

    test "capitalizes lowercase input before validation" do
      assert Script.validate("latn") == {:ok, :Latn, :regular}
    end

    test "accepts atom input" do
      assert Script.validate(:Adlm) == {:ok, :Adlm, :regular}
    end

    test "validates private use scripts from the Qaaa~x range" do
      assert {:ok, :Qaaa, status} = Script.validate("qaaa")
      assert status in [:private_use, :reserved, :special]
    end

    test "returns the original code on error" do
      assert Script.validate("Wxyz") == {:error, "Wxyz"}
    end

    test "nil is valid with nil status" do
      assert Script.validate(nil) == {:ok, nil, nil}
    end
  end

  describe "normalize/1" do
    test "capitalizes binary codes" do
      assert Script.normalize("LATN") == "Latn"
      assert Script.normalize("latn") == "Latn"
    end

    test "converts atom codes to capitalized strings" do
      assert Script.normalize(:latn) == "Latn"
    end

    test "passes nil through" do
      assert Script.normalize(nil) == nil
    end
  end

  describe "unicode_to_subtag/1" do
    test "maps a Unicode script name to its BCP 47 subtag" do
      assert Script.unicode_to_subtag(:devanagari) == {:ok, :Deva}
      assert Script.unicode_to_subtag(:braille) == {:ok, :Brai}
    end

    test "returns an InvalidSubtagError for an unknown script" do
      assert {:error, %Localize.InvalidSubtagError{} = exception} =
               Script.unicode_to_subtag("NotAScript")

      assert exception.key == "unicode_script"
      assert exception.value == "NotAScript"
      assert exception.reason == :unknown_script
    end
  end

  describe "unicode_to_subtag!/1" do
    test "returns the subtag directly" do
      assert Script.unicode_to_subtag!(:gothic) == :Goth
    end

    test "raises on an unknown script" do
      assert_raise Localize.InvalidSubtagError, fn ->
        Script.unicode_to_subtag!("NotAScript")
      end
    end
  end

  describe "unicode_to_subtag_map/0" do
    test "returns a map of unicode script names to subtags" do
      map = Script.unicode_to_subtag_map()
      assert is_map(map)
      assert map[:devanagari] == :Deva
    end
  end
end
