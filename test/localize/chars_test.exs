defmodule Localize.CharsTest do
  use ExUnit.Case, async: true

  doctest Localize.Chars

  describe "to_string/1 — built-in scalars" do
    test "Integer delegates to Localize.Number" do
      assert {:ok, _} = Localize.Chars.to_string(1234)
    end

    test "Float delegates to Localize.Number" do
      assert {:ok, _} = Localize.Chars.to_string(1234.5)
    end

    test "Decimal delegates to Localize.Number" do
      assert {:ok, _} = Localize.Chars.to_string(Decimal.new("42.50"))
    end

    test "BitString returns the string unchanged" do
      assert {:ok, "hello"} = Localize.Chars.to_string("hello")
    end
  end

  describe "to_string/1 — date and time" do
    test "Date delegates to Localize.Date" do
      assert {:ok, _} = Localize.Chars.to_string(~D[2025-07-10])
    end

    test "Time delegates to Localize.Time" do
      assert {:ok, _} = Localize.Chars.to_string(~T[14:30:00])
    end

    test "DateTime delegates to Localize.DateTime" do
      {:ok, dt, _} = DateTime.from_iso8601("2025-07-10T14:30:00Z")
      assert {:ok, _} = Localize.Chars.to_string(dt)
    end

    test "NaiveDateTime delegates to Localize.DateTime" do
      assert {:ok, _} = Localize.Chars.to_string(~N[2025-07-10 14:30:00])
    end
  end

  describe "to_string/1 — collections and structs" do
    test "Range delegates to Localize.Number.to_range_string" do
      assert {:ok, _} = Localize.Chars.to_string(3..5)
    end

    test "List delegates to Localize.List" do
      assert {:ok, "a, b, and c"} = Localize.Chars.to_string(["a", "b", "c"])
    end

    test "Localize.Unit delegates to Localize.Unit" do
      {:ok, unit} = Localize.Unit.new(42, "kilometer")
      assert {:ok, _} = Localize.Chars.to_string(unit)
    end

    test "Localize.Duration delegates to Localize.Duration" do
      {:ok, duration} = Localize.Duration.new(~D[2025-01-01], ~D[2025-02-15])
      assert {:ok, _} = Localize.Chars.to_string(duration)
    end

    test "Localize.LanguageTag delegates to LocaleDisplay.display_name" do
      {:ok, tag} = Localize.validate_locale(:en)
      assert {:ok, name} = Localize.Chars.to_string(tag)
      assert is_binary(name)
      assert String.contains?(name, "English")
    end

    test "Localize.Currency delegates to Currency.display_name" do
      {:ok, currency} = Localize.Currency.currency_for_code(:USD)
      assert {:ok, _} = Localize.Chars.to_string(currency)
    end
  end

  describe "to_string/2 — locale-driven output" do
    test "Float formats differently in :en vs :de" do
      assert {:ok, "1,234.5"} = Localize.Chars.to_string(1234.5, locale: :en)
      assert {:ok, "1.234,5"} = Localize.Chars.to_string(1234.5, locale: :de)
    end

    test "Integer formats differently in :en vs :de" do
      assert {:ok, "1,234,567"} = Localize.Chars.to_string(1_234_567, locale: :en)
      assert {:ok, "1.234.567"} = Localize.Chars.to_string(1_234_567, locale: :de)
    end

    test "Decimal formats with the requested locale" do
      # Decimal rendering matches float rendering: trailing zeros
      # beyond the pattern's minimum fraction digits are stripped,
      # so `Decimal.new("1234.50")` renders as "1,234.5" under the
      # standard `#,##0.###` pattern (min 0, max 3).
      assert {:ok, "1,234.5"} =
               Localize.Chars.to_string(Decimal.new("1234.50"), locale: :en)

      assert {:ok, "1.234,5"} =
               Localize.Chars.to_string(Decimal.new("1234.50"), locale: :de)
    end

    test "Date formats differently in :en vs :de" do
      {:ok, en} = Localize.Chars.to_string(~D[2025-07-10], locale: :en, format: :long)
      {:ok, de} = Localize.Chars.to_string(~D[2025-07-10], locale: :de, format: :long)
      assert en != de
      assert String.contains?(en, "July")
      assert String.contains?(de, "Juli")
    end

    test "Time formats with the requested locale" do
      {:ok, en} = Localize.Chars.to_string(~T[14:30:00], locale: :en, prefer: :ascii)
      {:ok, de} = Localize.Chars.to_string(~T[14:30:00], locale: :de)
      assert String.contains?(en, "PM")
      refute String.contains?(de, "PM")
    end

    test "DateTime formats with the requested locale" do
      {:ok, en} =
        Localize.Chars.to_string(~N[2025-07-10 14:30:00],
          locale: :en,
          format: :short,
          prefer: :ascii
        )

      assert String.contains?(en, "7/10/25")
    end

    test "NaiveDateTime delegates the same as DateTime" do
      assert {:ok, _} =
               Localize.Chars.to_string(~N[2025-07-10 14:30:00],
                 locale: :de,
                 prefer: :ascii
               )
    end

    test "Range formats with the locale-appropriate separator" do
      assert {:ok, _} = Localize.Chars.to_string(3..5, locale: :en)
      assert {:ok, _} = Localize.Chars.to_string(3..5, locale: :de)
    end

    test "BitString ignores options and returns the string unchanged" do
      assert {:ok, "hello"} = Localize.Chars.to_string("hello", locale: :en)
      assert {:ok, "hello"} = Localize.Chars.to_string("hello", locale: :de)
    end

    test "List joins with locale-specific conjunctions" do
      assert {:ok, "a, b, and c"} = Localize.Chars.to_string(["a", "b", "c"], locale: :en)
      assert {:ok, "a, b et c"} = Localize.Chars.to_string(["a", "b", "c"], locale: :fr)
    end

    test "Localize.Unit formats with the requested locale" do
      {:ok, unit} = Localize.Unit.new(42, "kilometer")
      assert {:ok, "42 kilometers"} = Localize.Chars.to_string(unit, locale: :en)
      assert {:ok, "42 km"} = Localize.Chars.to_string(unit, format: :short, locale: :en)
    end

    test "Localize.Duration formats with the requested locale" do
      {:ok, duration} = Localize.Duration.new(~D[2025-01-01], ~D[2025-02-15])
      assert {:ok, _} = Localize.Chars.to_string(duration, locale: :en)
    end

    test "Localize.LanguageTag formats as a localized display name" do
      {:ok, tag} = Localize.validate_locale(:fr)
      {:ok, en_name} = Localize.Chars.to_string(tag, locale: :en)
      {:ok, de_name} = Localize.Chars.to_string(tag, locale: :de)
      assert String.contains?(en_name, "French")
      assert String.contains?(de_name, "Französisch")
    end

    test "Localize.Currency formats as a localized display name" do
      {:ok, currency} = Localize.Currency.currency_for_code(:USD)
      assert {:ok, name} = Localize.Chars.to_string(currency, locale: :en)
      assert is_binary(name)
    end
  end

  describe "fallback behaviour" do
    # Values are routed through `apply/3` to keep them opaque to
    # the compiler's gradual type checker so that the negative
    # cases below cannot be flagged at compile time.

    test "atoms fall through to Kernel.to_string" do
      assert {:ok, "some_atom"} = Localize.Chars.to_string(:some_atom)
    end

    test "nil falls through to Kernel.to_string and produces an empty string" do
      assert {:ok, ""} = Localize.Chars.to_string(nil)
    end

    test "true and false fall through to Kernel.to_string" do
      assert {:ok, "true"} = Localize.Chars.to_string(true)
      assert {:ok, "false"} = Localize.Chars.to_string(false)
    end

    test "charlists fall through to Kernel.to_string" do
      assert {:ok, "hello"} = Localize.Chars.to_string(~c"hello")
    end

    test "tuples raise Protocol.UndefinedError (no String.Chars impl)" do
      assert_raise Protocol.UndefinedError, fn ->
        apply(Localize.Chars, :to_string, [{1, 2, 3}])
      end
    end

    test "plain maps raise Protocol.UndefinedError (no String.Chars impl)" do
      assert_raise Protocol.UndefinedError, fn ->
        apply(Localize.Chars, :to_string, [%{a: 1}])
      end
    end

    test "anonymous functions raise Protocol.UndefinedError" do
      assert_raise Protocol.UndefinedError, fn ->
        apply(Localize.Chars, :to_string, [fn -> :ok end])
      end
    end
  end

  describe "heterogeneous integration" do
    test "Enum.map over a list of mixed supported types" do
      {:ok, unit} = Localize.Unit.new(42, "kilometer")

      values = [
        1234.5,
        ~D[2025-07-10],
        unit,
        "literal"
      ]

      results = Enum.map(values, &Localize.Chars.to_string(&1, locale: :en))
      assert Enum.all?(results, &match?({:ok, _}, &1))

      assert Enum.map(results, &elem(&1, 1)) == [
               "1,234.5",
               "Jul 10, 2025",
               "42 kilometers",
               "literal"
             ]
    end
  end
end
