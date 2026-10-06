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

  # Localize has no calendar but `Calendar.ISO`; the others are
  # Calendrical's, which depends on Localize. A calendar selects its CLDR
  # data by naming its CLDR calendar type, which is what these stand-ins are
  # for: each answers a fixed week, quarter and day of the week, so that
  # what a skeleton writes for its dates is known from CLDR's data alone.
  defmodule Hebrew do
    @moduledoc false
    use Localize.Test.StandInCalendar

    def cldr_calendar_type, do: :hebrew
    def year_of_era(year, _month, _day), do: {year, 0}
    def week_of_year(year, _month, _day), do: {year, 39}
    def week_of_month(_year, month, _day), do: {month, 1}
    def quarter_of_year(_year, _month, _day), do: 4
    def day_of_week(_year, _month, _day, _starting_on), do: {2, 1, 7}
  end

  defmodule Buddhist do
    @moduledoc false
    use Localize.Test.StandInCalendar

    def cldr_calendar_type, do: :buddhist
    def year_of_era(year, _month, _day), do: {year, 0}
    def week_of_year(year, _month, _day), do: {year, 25}
    def week_of_month(_year, month, _day), do: {month, 3}
    def quarter_of_year(_year, _month, _day), do: 2
    def day_of_week(_year, _month, _day, _starting_on), do: {2, 1, 7}
  end

  # The year that began in 2026 is the forty-third of its sixty-year cycle,
  # bing-wu, in the Chinese calendar and in the Korean.
  defmodule Chinese do
    @moduledoc false
    use Localize.Test.StandInCalendar

    def cldr_calendar_type, do: :chinese
    def cyclic_year(_year, _month, _day), do: 43
    def related_gregorian_year(_year, _month, _day), do: 2026
    def week_of_year(year, _month, _day), do: {year, 18}
    def week_of_month(_year, month, _day), do: {month, 1}
    def quarter_of_year(_year, _month, _day), do: 2
    def day_of_week(_year, _month, _day, _starting_on), do: {2, 1, 7}
  end

  defmodule Dangi do
    @moduledoc false
    use Localize.Test.StandInCalendar

    def cldr_calendar_type, do: :dangi
    def cyclic_year(_year, _month, _day), do: 43
    def related_gregorian_year(_year, _month, _day), do: 2026
    def week_of_year(year, _month, _day), do: {year, 18}
    def week_of_month(_year, month, _day), do: {month, 1}
    def quarter_of_year(_year, _month, _day), do: 2
    def day_of_week(_year, _month, _day, _starting_on), do: {2, 1, 7}
  end

  @hebrew %{calendar: Hebrew, year: 5786, month: 11, day: 1}
  @buddhist %{calendar: Buddhist, year: 2569, month: 6, day: 16}
  @chinese %{calendar: Chinese, year: 4663, month: 5, day: 2}
  @dangi %{calendar: Dangi, year: 4359, month: 5, day: 2}

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

  # TR35, Calendar Elements: "Most non-Gregorian calendars (other than
  # Chinese and Dangi) inherit general date format data (in the
  # `<dateFormats>` and `<dateTimeFormats>` elements) from the "generic"
  # calendar format data in the same locale, which in turn inherits from
  # Gregorian." So a skeleton is matched against the calendar's own formats
  # and then the Gregorian calendar's, and Missing Skeleton Fields takes
  # "the one with the greatest number of matching fields (but no extra
  # fields)" among them all, where the append step was reached for the
  # Gregorian calendar alone and each of these was an error (user,
  # 2026-10-06).
  #
  # The patterns are CLDR's `en`: the Hebrew calendar's own `yMMMd` "d MMM
  # y" and `GyMMMd` "d MMM y G", the generic calendar's `yyyyMMMd` "MMM d, y
  # G", which the Buddhist calendar takes, the Gregorian `yw` "'week' w 'of'
  # Y", and the append items "{0} ({2}: {1})" for a week and a quarter and
  # "{1}, {0}" for a day of the week.
  describe "a calendar that inherits the Gregorian calendar's formats" do
    test "appends a field to its own format, where both have one of the other fields" do
      for {skeleton, written} <- [
            {:yMMMd, "1 Tamuz 5786"},
            {:yMMMdw, "1 Tamuz 5786 (week: 39)"},
            {:yMMMdQ, "1 Tamuz 5786 (quarter: 4)"},
            {:yMMMdQw, "1 Tamuz 5786 (quarter: 4) (week: 39)"},
            {:GyMMMdw, "1 Tamuz 5786 AM (week: 39)"}
          ] do
        assert Localize.Date.to_string(@hebrew, format: skeleton, locale: :en) == {:ok, written},
               inspect(skeleton)
      end

      for {skeleton, written} <- [
            {:yMMMd, "Jun 16, 2569 BE"},
            {:yMMMdw, "Jun 16, 2569 BE (week: 25)"},
            {:yMMMdQ, "Jun 16, 2569 BE (quarter: 2)"}
          ] do
        assert Localize.Date.to_string(@buddhist, format: skeleton, locale: :en) ==
                 {:ok, written},
               inspect(skeleton)
      end
    end

    # The Gregorian `yw` is the only format of a year and a week, so it is
    # the format of that name, the closest to `Yw`, and the one with the
    # most fields of `ywE`, before a format of the year alone.
    test "takes the Gregorian format that carries more of the fields, and appends to it" do
      for {skeleton, hebrew, buddhist} <- [
            {:yw, "week 39 of 5786", "week 25 of 2569"},
            {:Yw, "week 39 of 5786", "week 25 of 2569"},
            {:ywE, "Tue, week 39 of 5786", "Tue, week 25 of 2569"},
            {:w, "39", "25"}
          ] do
        assert Localize.Date.to_string(@hebrew, format: skeleton, locale: :en) == {:ok, hebrew},
               inspect(skeleton)

        assert Localize.Date.to_string(@buddhist, format: skeleton, locale: :en) ==
                 {:ok, buddhist},
               inspect(skeleton)
      end
    end

    test "writes a date and time's date as the date alone is written" do
      for value <- [@hebrew, @buddhist], skeleton <- [:yw, :ywE, :yMMMdw, :yMMMdQ] do
        {:ok, date} = Localize.Date.to_string(value, format: skeleton, locale: :en)
        datetime = Map.merge(value, %{hour: 10, minute: 30, second: 0})
        format = String.to_atom(Atom.to_string(skeleton) <> "Hm")

        assert Localize.DateTime.to_string(datetime, format: format, locale: :en) ==
                 {:ok, date <> ", 10:30"},
               "#{inspect(value.calendar)} #{format}"
      end
    end

    test "resolves the same pattern wherever a skeleton is resolved" do
      for {calendar, skeleton, pattern} <- [
            {:hebrew, :yw, "'week' w 'of' Y"},
            {:hebrew, :yMMMdw, "d MMM y ('week': w)"},
            {:buddhist, :yMMMdw, "MMM d, y G ('week': w)"},
            {:gregorian, :yMMMdw, "MMM d, y ('week': w)"}
          ] do
        assert AppendItems.resolve_pattern(skeleton, :en, calendar) == {:ok, pattern},
               "#{calendar} #{skeleton}"
      end
    end
  end

  # TR35 excepts the Chinese and Dangi calendars from the calendars that
  # inherit their date formats, and does not say what theirs inherit, so a
  # skeleton of date fields is matched against their own formats alone
  # (user, 2026-10-06): `en`'s `y` is "r(U)" and its `yyyyMMMd` "MMM d, r".
  # A year and a week took the Gregorian `yw`, whose `Y` wrote the year by a
  # number no format of these calendars writes, "week 18 of 4663".
  describe "the Chinese and Dangi calendars" do
    test "append a field to their own formats alone" do
      for value <- [@chinese, @dangi],
          {skeleton, written} <- [
            {:y, "2026(bing-wu)"},
            {:yw, "2026(bing-wu) (week: 18)"},
            {:yMMMdw, "Mo5 2, 2026 (week: 18)"},
            {:yMMMdQ, "Mo5 2, 2026 (quarter: 2)"},
            {:MMMMW, "Fifth Month (week: 1)"},
            {:w, "18"}
          ] do
        assert Localize.Date.to_string(value, format: skeleton, locale: :en) == {:ok, written},
               "#{inspect(value.calendar)} #{skeleton}"
      end
    end

    # A calendar's times are the Gregorian calendar's in every calendar, so
    # a skeleton of time fields is matched against the Gregorian formats
    # where the calendar has none of its own.
    test "match a skeleton of time fields against the Gregorian formats too" do
      assert AppendItems.format_calendars(:Hm, :chinese) == [:chinese, :gregorian]
      assert AppendItems.format_calendars(:yw, :chinese) == [:chinese]
      assert AppendItems.format_calendars(:yMMMdHm, :dangi) == [:dangi]
      assert AppendItems.format_calendars(:yw, :hebrew) == [:hebrew, :gregorian]
      assert AppendItems.format_calendars(:yw, :gregorian) == [:gregorian]
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

    # With no subset to build on, CLDR's reference generator starts from the
    # field itself; a symbol that is no field stays unresolvable.
    test "a skeleton with no subset starts from its first field" do
      assert {:ok, "QQQQ"} = AppendItems.augment(:QQQQ, :en, :gregorian)
      assert :error = AppendItems.augment(:QQQQo, :en, :gregorian)
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
