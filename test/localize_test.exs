defmodule LocalizeTest do
  # async: false because doctests for with_locale/2 and get_locale/0
  # depend on global state (supported locales, default locale) that
  # can be mutated by concurrent tests.
  use ExUnit.Case, async: false
  doctest Localize

  describe "to_string/1 — protocol delegation" do
    test "Integer delegates to Localize.Chars" do
      assert Localize.to_string(1234) == Localize.Chars.to_string(1234)
    end

    test "Float delegates to Localize.Chars" do
      assert Localize.to_string(1234.5) == Localize.Chars.to_string(1234.5)
    end

    test "Date delegates to Localize.Chars" do
      assert Localize.to_string(~D[2025-07-10]) == Localize.Chars.to_string(~D[2025-07-10])
    end

    test "Localize.Unit delegates to Localize.Chars" do
      {:ok, unit} = Localize.Unit.new(42, "kilometer")
      assert Localize.to_string(unit) == Localize.Chars.to_string(unit)
    end
  end

  describe "to_string/2 — protocol delegation with options" do
    test "passes options through to the protocol" do
      assert Localize.to_string(1234.5, locale: :de) ==
               Localize.Chars.to_string(1234.5, locale: :de)
    end

    test "Date with format option" do
      assert Localize.to_string(~D[2025-07-10], locale: :en, format: :long) ==
               Localize.Chars.to_string(~D[2025-07-10], locale: :en, format: :long)
    end
  end

  describe "to_string!/1 and to_string!/2 — bang variants" do
    test "to_string!/1 returns the formatted string on success" do
      assert "1.234,5" = Localize.to_string!(1234.5, locale: :de)
    end

    test "to_string!/2 returns the formatted string on success" do
      assert "1,234.5" = Localize.to_string!(1234.5, locale: :en)
    end

    test "to_string!/1 raises Protocol.UndefinedError for types with no String.Chars impl" do
      assert_raise Protocol.UndefinedError, fn ->
        apply(Localize, :to_string!, [{1, 2, 3}])
      end
    end

    test "to_string!/2 raises Protocol.UndefinedError for types with no String.Chars impl" do
      assert_raise Protocol.UndefinedError, fn ->
        apply(Localize, :to_string!, [{1, 2, 3}, [locale: :en]])
      end
    end

    test "ok and bang produce equivalent strings on success" do
      {:ok, ok_string} = Localize.to_string(1234.5, locale: :de)
      bang_string = Localize.to_string!(1234.5, locale: :de)
      assert ok_string == bang_string
    end
  end

  describe "to_string/1 — Any fallback" do
    test "atoms fall through to Kernel.to_string via Localize.to_string" do
      assert {:ok, "some_atom"} = Localize.to_string(:some_atom)
    end

    test "nil falls through to an empty string via Localize.to_string" do
      assert {:ok, ""} = Localize.to_string(nil)
    end

    test "tuples raise Protocol.UndefinedError via Localize.to_string" do
      assert_raise Protocol.UndefinedError, fn ->
        apply(Localize, :to_string, [{1, 2, 3}])
      end
    end
  end
end
