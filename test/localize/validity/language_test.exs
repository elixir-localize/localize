defmodule Localize.Validity.LanguageTest do
  use ExUnit.Case, async: true

  alias Localize.Validity.Language

  describe "validate/1" do
    test "validates a regular language code as a string with status" do
      assert Language.validate("en") == {:ok, "en", :regular}
    end

    test "downcases before validation" do
      assert Language.validate("EN") == {:ok, "en", :regular}
    end

    test "validates three-letter language codes" do
      assert Language.validate("yue") == {:ok, "yue", :regular}
    end

    test "reports reserved codes from the qaa~z range" do
      assert Language.validate("qaa") == {:ok, "qaa", :reserved}
    end

    test "returns the original code on error" do
      assert Language.validate("zzz") == {:error, "zzz"}
    end

    test "nil is valid with nil status" do
      assert Language.validate(nil) == {:ok, nil, nil}
    end
  end

  describe "normalize/1" do
    test "downcases binary codes" do
      assert Language.normalize("EN") == "en"
    end

    test "passes nil through" do
      assert Language.normalize(nil) == nil
    end
  end
end
