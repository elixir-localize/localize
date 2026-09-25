defmodule Localize.DateTime.AppendItemsTest do
  @moduledoc """
  TR35 append items: a skeleton asking for a field combination the locale
  does not ship resolves to the closest available format, augmented with
  the missing fields from the locale's `appendItems` templates.
  """

  use ExUnit.Case, async: true

  alias Localize.DateTime.Format.AppendItems
  alias Localize.DateTime.Format.Match

  @date ~D[2024-07-06]
  @time ~T[14:30:45]
  @datetime ~U[2024-07-06 14:30:45Z]

  describe "subset matching" do
    # `en` ships `yMMMd` but no quarter or week variant of it, so the match
    # is the subset and the odd field out is what gets appended.
    test "finds the closest format whose fields are a subset of the request" do
      assert {:ok, :yMMMd, [{"Q", 1}]} = Match.subset_match(:yMMMdQ, :en)
      assert {:ok, :yMMMd, [{"w", 1}]} = Match.subset_match(:yMMMdw, :en)
    end

    # Ranking is on the fields the two have in common, so a request at
    # `MMM` prefers `yMMMd` over the equally-sized `yMMMMd`.
    test "ranks equally-sized subsets by field width" do
      assert {:ok, :yMMMd, [{"Q", 1}]} = Match.subset_match(:yMMMdQ, :en)
      assert {:ok, :yMMMMd, [{"Q", 1}]} = Match.subset_match(:yMMMMdQ, :en)
    end

    # A subset has to be non-empty, so a single-field skeleton the locale
    # ships no format for has nothing to build on. `subset_match/3` is a
    # fallback: it does not check whether an exact match exists, because
    # the callers only reach it once that has already failed.
    test "a single field the locale has no format for has no subset match" do
      assert :error = Match.subset_match(:Q, :en)
      assert :error = Match.subset_match(:w, :en)
    end
  end

  describe "appending a single field" do
    # en's `:quarter` template is `"{0} ({2}: {1})"` — matched pattern,
    # field display name, then the field itself.
    test "appends the quarter with its display name" do
      assert {:ok, "Jul 6, 2024 (quarter: 3)"} =
               Localize.Date.to_string(@date, format: :yMMMdQ, locale: :en)
    end

    test "appends the week with its display name" do
      assert {:ok, "Jul 6, 2024 (week: 27)"} =
               Localize.Date.to_string(@date, format: :yMMMdw, locale: :en)
    end

    # Each locale brings its own template and its own field display name.
    test "uses the locale's own template and display name" do
      assert {:ok, "6. Juli 2024 (Quartal: 3)"} =
               Localize.Date.to_string(@date, format: :yMMMdQ, locale: :de)

      assert {:ok, "6. Juli 2024 (Woche: 27)"} =
               Localize.Date.to_string(@date, format: :yMMMdw, locale: :de)
    end
  end

  describe "appending several fields" do
    # Each round's output becomes the next round's `{0}`.
    test "appends field by field" do
      assert {:ok, "Jul 6, 2024 (quarter: 3) (week: 27)"} =
               Localize.Date.to_string(@date, format: :yMMMdQw, locale: :en)
    end
  end

  describe "date-time skeletons" do
    # A skeleton spanning both halves splits first, so the time fields are
    # formatted as a time rather than appended as parenthesised items.
    test "splits date and time before appending" do
      assert {:ok, "Jul 6, 2024 (quarter: 3), 2:30 PM"} =
               replace_nbsp(
                 Localize.DateTime.to_string(@datetime, format: :yMMMdQhm, locale: :en)
               )

      assert {:ok, "Jul 6, 2024 (week: 27), 2:30:45 PM"} =
               replace_nbsp(
                 Localize.DateTime.to_string(@datetime, format: :yMMMdwhms, locale: :en)
               )
    end

    # The plain path is untouched: a skeleton the locale can compose from
    # its own date and time formats never reaches the append-item code.
    test "leaves a fully-matched skeleton alone" do
      assert {:ok, "Jul 6, 2024, 2:30 PM"} =
               replace_nbsp(Localize.DateTime.to_string(@datetime, format: :yMMMdhm, locale: :en))
    end
  end

  describe "fields that cannot be appended" do
    # A fraction attaches to a seconds field; it is not an item of its own.
    # Without seconds to attach to the skeleton stays unresolvable rather
    # than gaining a "(second: 34)" suffix.
    test "fractional seconds do not become an append item" do
      assert {:error, %Localize.DateTimeUnresolvedFormatError{}} =
               Localize.Time.to_string(@time, locale: :en, format: :hmSS)
    end

    test "a skeleton with no subset at all stays unresolved" do
      assert :error = AppendItems.augment(:QQQQ, :en, :gregorian)
    end
  end

  describe "display names" do
    # `append_items` and `date_fields` name the same field differently, so
    # the `{2}` lookup bridges `day_of_week` to `weekday` and `timezone` to
    # `zone`.
    test "bridges the append-item field name to the date-field name" do
      assert {:ok, "day of the week"} = Localize.DateTime.Format.field_display_name(:en, :weekday)
      assert {:ok, "time zone"} = Localize.DateTime.Format.field_display_name(:en, :zone)
      assert {:ok, "quarter"} = Localize.DateTime.Format.field_display_name(:en, :quarter)
    end

    test "every append-item field maps to a symbol" do
      assert AppendItems.symbol_to_field("Q") == :quarter
      assert AppendItems.symbol_to_field("w") == :week
      assert AppendItems.symbol_to_field("E") == :day_of_week
      assert AppendItems.symbol_to_field("v") == :timezone
      assert AppendItems.symbol_to_field("S") == nil
    end
  end

  # The formatter emits a narrow no-break space before the day period.
  defp replace_nbsp({:ok, string}), do: {:ok, String.replace(string, " ", " ")}
  defp replace_nbsp(other), do: other
end
