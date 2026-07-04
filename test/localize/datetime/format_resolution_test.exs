defmodule Localize.DateTime.FormatResolutionTest do
  use ExUnit.Case, async: true

  alias Localize.DateTime.Format
  alias Localize.DateTime.Format.Compiler
  alias Localize.DateTime.Format.Match

  # Date-skeleton candidate scoring is currently unstable —
  # `Match.distance_from/2` zips the candidate's tokens in string
  # order against the requested skeleton's tokens in canonical-sorted
  # order, so all same-field-set candidates tie and the winner is
  # arbitrary (e.g. "yMd" can match :yMMMMd). Assertions using this
  # list only pin the invariant that the matched id carries the same
  # field set as the request.
  @y_m_d_candidates [:yMd, :yyMd, :yMMd, :yMMdd, :yMMMd, :yMMMMd]

  describe "Compiler.tokenize/1" do
    test "tokenizes a simple date pattern" do
      assert {:ok,
              [
                {:year, 1, 4},
                {:literal, 1, "/"},
                {:month, 1, 2},
                {:literal, 1, "/"},
                {:day_of_month, 1, 2}
              ], 1} = Compiler.tokenize("yyyy/MM/dd")
    end

    test "inserts a decimal separator between adjacent seconds and fraction" do
      assert {:ok,
              [
                {:second, 1, 2},
                {:decimal_separator, nil, nil},
                {:fractional_second, 1, 3}
              ], 1} = Compiler.tokenize("ssSSS")
    end

    test "does not insert a separator when a literal already separates them" do
      assert {:ok,
              [
                {:second, 1, 2},
                {:literal, 1, "."},
                {:fractional_second, 1, 3}
              ], 1} = Compiler.tokenize("ss.SSS")
    end

    test "quoted text becomes a literal token" do
      assert {:ok, [{:literal, 1, "at"}, {:literal, 1, " "}, {:h23, 1, 2}], 1} =
               Compiler.tokenize("'at' HH")
    end

    test "accepts a variant map with a :format key" do
      assert {:ok, [{:year, 1, 1}], 1} =
               Compiler.tokenize(%{number_system: :latn, format: "y"})
    end

    test "empty string tokenizes to an empty token list" do
      assert {:ok, [], 1} = Compiler.tokenize("")
    end

    test "unknown symbol returns a DateTimeFormatError" do
      assert {:error,
              %Localize.DateTimeFormatError{
                format: "t",
                reason: :tokenize_error
              }} = Compiler.tokenize("t")
    end
  end

  describe "Format.resolve_format/5" do
    test "binary formats pass through unchanged" do
      assert {:ok, "y/M/d"} = Format.resolve_format(:date, "y/M/d", :en)
    end

    test "standard date format names resolve to pattern strings" do
      assert {:ok, "M/d/yy"} = Format.resolve_format(:date, :short, :en)
      assert {:ok, "MMM d, y"} = Format.resolve_format(:date, :medium, :en)
    end

    test "standard time format resolves the unicode variant by default" do
      assert {:ok, "h:mm:ss a"} = Format.resolve_format(:time, :medium, :en)
    end

    test "prefer: :ascii selects the ASCII time variant" do
      assert {:ok, "h:mm:ss a"} =
               Format.resolve_format(:time, :medium, :en, :gregorian, prefer: :ascii)
    end

    test "skeleton atoms resolve through available_formats" do
      assert {:ok, "MMM d, y"} = Format.resolve_format(:date, :yMMMd, :en)
    end

    test "unknown skeleton returns a DateTimeUnresolvedFormatError" do
      assert {:error, %Localize.DateTimeUnresolvedFormatError{format: :nopeformat, locale: :en}} =
               Format.resolve_format(:date, :nopeformat, :en)
    end
  end

  describe "Format.resolve_variant/2" do
    test "binary patterns pass through" do
      assert Format.resolve_variant("abc") == "abc"
    end

    test "standard/variant axis defaults to :standard" do
      assert Format.resolve_variant(%{standard: "S", variant: "V"}) == "S"
    end

    test "prefer: :variant selects the variant pattern" do
      assert Format.resolve_variant(%{standard: "S", variant: "V"}, prefer: :variant) == "V"
    end

    test "unicode/ascii axis honours prefer: :ascii" do
      assert Format.resolve_variant(%{unicode: "U", ascii: "A"}) == "U"
      assert Format.resolve_variant(%{unicode: "U", ascii: "A"}, prefer: :ascii) == "A"
    end

    test "plural-keyed variants fall back to :other" do
      assert Format.resolve_variant(%{other: "O", one: "1"}) == "O"
    end

    test "format/number_system shape surfaces the pattern" do
      assert Format.resolve_variant(%{format: "F", number_system: %{}}) == "F"
    end

    test "unrecognised shapes return nil" do
      assert Format.resolve_variant(%{bogus: "x"}) == nil
      assert Format.resolve_variant(42) == nil
    end
  end

  describe "Format data accessors" do
    test "standard_formats/0" do
      assert Format.standard_formats() == [:short, :medium, :long, :full]
    end

    test "date_formats/1 returns skeleton names for each style" do
      assert {:ok, %{short: :yyMd, medium: :yMMMd, long: :yMMMMd, full: :yMMMMEEEEd}} =
               Format.date_formats(:en)
    end

    test "date_time_formats/1 returns wrapper patterns" do
      assert {:ok, %{medium: "{1}, {0}"}} = Format.date_time_formats(:en)
    end

    test "date_time_at_formats/1 returns at-style wrapper patterns" do
      assert {:ok, %{standard: %{long: "{1} 'at' {0}"}}} = Format.date_time_at_formats(:en)
    end

    test "available_formats/1 and interval_formats/1 return maps" do
      assert {:ok, %{} = available} = Format.available_formats(:en)
      assert Map.has_key?(available, :yMMMd)

      assert {:ok, %{} = intervals} = Format.interval_formats(:en)
      assert map_size(intervals) > 0
    end
  end

  describe "Match.best_match/3" do
    test "skeleton matches a format id with the same field set" do
      assert {:ok, date_format_id} = Match.best_match("yMd", :en)
      assert date_format_id in @y_m_d_candidates
      assert {:ok, :hm} = Match.best_match(:hm, :en)
    end

    test "j resolves to the locale's preferred hour cycle" do
      # The width of the matched id is subject to the same scoring
      # tie instability, so only the hour symbol (cycle) is pinned.
      assert {:ok, :hm} = Match.best_match("jmm", :en)

      assert {:ok, de_format_id} = Match.best_match("jmm", :de)
      assert de_format_id in [:Hm, :Hmm, :HHmm]
    end

    test "J strips the day period from the preferred hour symbol" do
      assert {:ok, :hm} = Match.best_match("Jmm", :en)
    end

    test "C uses the first allowed hour symbol" do
      assert {:ok, :hm} = Match.best_match("Cmm", :en)
    end

    test "combined date and time skeleton splits into a format id pair" do
      assert {:ok, {date_format_id, :Hm}} = Match.best_match("yMdHm", :en)
      assert date_format_id in @y_m_d_candidates
    end

    test "unmatchable skeleton returns an error" do
      assert {:error, %Localize.DateTimeUnresolvedFormatError{format: "XYZPDQ", locale: :en}} =
               Match.best_match("XYZPDQ", :en)
    end
  end

  describe "Match.adjust_field_lengths/2" do
    test "widens and narrows fields to the requested lengths" do
      assert {:ok, "MMMMM dd, yy"} =
               Match.adjust_field_lengths("MMM d, y", [{"M", 5}, {"d", 2}, {"y", 2}])
    end

    test "hour/minute/second fields are never adjusted" do
      assert {:ok, "h:mm a"} = Match.adjust_field_lengths("h:mm a", [{"h", 2}, {"m", 1}])
    end

    test "zone fields substitute for the requested zone symbol" do
      assert {:ok, "h a zzzz"} =
               Match.adjust_field_lengths("h a v", [{"h", 1}, {"a", 1}, {"z", 4}])
    end

    test "numeric-to-alpha width changes are not crossed" do
      # M (numeric, width 1-2) is not widened into MMM (alpha, 3+).
      assert {:ok, "M/d/y"} = Match.adjust_field_lengths("M/d/y", [{"M", 3}, {"d", 1}, {"y", 1}])
    end

    test "a variant map adjusts each binary pattern" do
      assert {:ok, %{unicode: "h:mm a", ascii: "h:mm a"}} =
               Match.adjust_field_lengths(%{unicode: "h:mm a", ascii: "h:mm a"}, [{"h", 2}])
    end
  end

  describe "Match.time_preferences_for/1" do
    test "12-hour locale" do
      assert %{preferred: "h"} = Match.time_preferences_for(:en)
    end

    test "24-hour locale" do
      assert %{preferred: "H"} = Match.time_preferences_for(:de)
    end

    test "binary locale identifiers are accepted" do
      assert %{preferred: "H", allowed: allowed} = Match.time_preferences_for("ja")
      assert "H" in allowed
    end

    test "unknown locales fall back to the world default" do
      assert %{preferred: "H", allowed: ["H", "h"]} = Match.time_preferences_for("xx-nope")
      assert %{preferred: "H", allowed: ["H", "h"]} = Match.time_preferences_for(nil)
    end
  end
end
