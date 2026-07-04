defmodule Localize.DateTime.FormatModuleTest do
  use ExUnit.Case, async: true

  # Coverage for Localize.DateTime.Format (format resolution and
  # variant selection) and Localize.DateTime.Format.Compiler
  # (pattern tokenization), including their error paths.

  doctest Localize.DateTime.Format

  alias Localize.DateTime.Format
  alias Localize.DateTime.Format.Compiler

  describe "resolve_format/3,5" do
    test "resolves a standard date format with default calendar and options" do
      assert {:ok, "MMM d, y"} = Format.resolve_format(:date, :medium, :en)
    end

    test "passes a binary pattern through unchanged" do
      assert {:ok, "y-M-d"} = Format.resolve_format(:date, "y-M-d", :en)
    end

    test "returns an unresolved-format error for an unknown skeleton" do
      assert {:error, %Localize.DateTimeUnresolvedFormatError{format: :bogus, locale: :en}} =
               Format.resolve_format(:date, :bogus, :en)
    end

    test "resolves a time skeleton for a specific calendar" do
      assert {:ok, pattern} = Format.resolve_format(:time, :short, :en, :gregorian)
      assert pattern =~ "h:mm"
    end
  end

  describe "format data accessors" do
    test "date_formats/1 returns the standard style skeleton map" do
      assert {:ok, formats} = Format.date_formats(:en)
      assert is_atom(formats.medium)
    end

    test "time_formats/1 returns the standard style skeleton map" do
      assert {:ok, formats} = Format.time_formats(:en)
      assert is_atom(formats.short)
    end

    test "date_time_formats/1 returns the {1}/{0} wrapper patterns" do
      assert {:ok, formats} = Format.date_time_formats(:en)
      assert formats |> Map.values() |> Enum.any?(&(&1 =~ "{1}"))
    end

    test "date_time_at_formats/1 returns the at-joining patterns" do
      assert {:ok, %{standard: at_formats}} = Format.date_time_at_formats(:en)
      assert at_formats.full == "{1} 'at' {0}"
      assert at_formats.short == "{1}, {0}"
    end

    test "available_formats/1 maps skeletons to patterns" do
      assert {:ok, available} = Format.available_formats(:en)
      assert Map.has_key?(available, :yMMMd)
    end

    test "standard_formats/0 lists the four standard styles" do
      assert Format.standard_formats() == [:short, :medium, :long, :full]
    end
  end

  describe "resolve_variant/2" do
    test "a binary pattern passes through" do
      assert Format.resolve_variant("h:mm a") == "h:mm a"
    end

    test "the standard/variant axis defaults to :standard" do
      assert Format.resolve_variant(%{standard: "s", variant: "v"}) == "s"
    end

    test "prefer: :variant selects the variant pattern" do
      assert Format.resolve_variant(%{standard: "s", variant: "v"}, prefer: :variant) == "v"
    end

    test "the unicode/ascii axis honours prefer: :ascii" do
      assert Format.resolve_variant(%{unicode: "u", ascii: "a"}, prefer: :ascii) == "a"
      assert Format.resolve_variant(%{unicode: "u", ascii: "a"}) == "u"
    end

    test "the format/number_system shape surfaces the pattern" do
      assert Format.resolve_variant(%{format: "f", number_system: %{"y" => :jpanyear}}) == "f"
    end

    test "plural-keyed maps fall back to :other" do
      assert Format.resolve_variant(%{other: "o", one: "1"}) == "o"
    end

    test "an unrecognised map shape returns nil" do
      assert Format.resolve_variant(%{unrecognised: 1}) == nil
    end

    test "a non-map non-binary value returns nil" do
      assert Format.resolve_variant(42) == nil
    end
  end

  describe "number_system_overrides/4" do
    test "returns an empty map for an invalid locale" do
      assert Format.number_system_overrides(:date, :medium, :zzz, :gregorian) == %{}
    end

    test "returns an empty map for a binary format name" do
      assert Format.number_system_overrides(:date, "y-M-d", :en, :gregorian) == %{}
    end
  end

  describe "Compiler.tokenize/1" do
    test "tokenizes a simple pattern into handler tokens" do
      assert {:ok, tokens, 1} = Compiler.tokenize("yyyy/MM/dd")

      assert tokens == [
               {:year, 1, 4},
               {:literal, 1, "/"},
               {:month, 1, 2},
               {:literal, 1, "/"},
               {:day_of_month, 1, 2}
             ]
    end

    test "an empty pattern tokenizes to an empty list" do
      assert {:ok, [], 1} = Compiler.tokenize("")
    end

    test "inserts a decimal separator between s and S runs" do
      assert {:ok, tokens, 1} = Compiler.tokenize("ssSSS")

      assert tokens == [
               {:second, 1, 2},
               {:decimal_separator, nil, nil},
               {:fractional_second, 1, 3}
             ]
    end

    test "accepts the number_system/format map shape" do
      assert {:ok, [{:year, 1, 1}], 1} =
               Compiler.tokenize(%{number_system: %{"y" => :jpanyear}, format: "y"})
    end

    test "an unterminated quote returns a tokenize error" do
      assert {:error, %Localize.DateTimeFormatError{reason: :tokenize_error, format: "'abc"}} =
               Compiler.tokenize("'abc")
    end

    test "an unquoted non-symbol letter run returns a tokenize error" do
      assert {:error, %Localize.DateTimeFormatError{reason: :tokenize_error}} =
               Compiler.tokenize("hh:mm garbage")
    end
  end
end
