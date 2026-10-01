defmodule Localize.NativeDigitsParseTest do
  @moduledoc """
  Dates, times and date-times written in the digits of the locale's number
  system parse as their Latin-digit forms do.

  The expected values are ICU4C 78.3's readings of the same text with the
  locale's standard format, except where a test says otherwise.

  """

  use ExUnit.Case, async: true

  # Localize cannot load Calendrical's calendars, which depend on it. This
  # stand-in names the Japanese calendar and answers `year_of_era/3` as
  # CLDR's era data does for Kanpō, from 1741-02-27, and Enkyō, from
  # 1744-02-21, taking the rest of its arithmetic from `Calendar.ISO`.
  defmodule Japanese do
    @moduledoc false
    use Localize.Test.StandInCalendar

    @eras [{~D[1744-02-21], 214}, {~D[1741-02-27], 213}]

    def cldr_calendar_type, do: :japanese
    def cardinal_month(month), do: month
    def month_of_year(_year, month, _day), do: month

    def year_of_era(year, month, day) do
      date = Date.new!(year, month, day)
      {start, era} = Enum.find(@eras, fn {start, _era} -> Date.compare(date, start) != :lt end)
      {year - start.year + 1, era}
    end

    def calendar_year(year, month, day), do: year |> year_of_era(month, day) |> elem(0)

    defdelegate valid_date?(year, month, day), to: Calendar.ISO
    defdelegate days_in_month(year, month), to: Calendar.ISO
    defdelegate months_in_year(year), to: Calendar.ISO
    defdelegate date_to_string(year, month, day), to: Calendar.ISO
  end

  describe "a time" do
    test "in the locale's digits" do
      assert Localize.Time.parse("১০:০৫ AM", locale: :bn) == {:ok, ~T[10:05:00]}
      assert Localize.Time.parse("۱۰:۰۵", locale: :fa) == {:ok, ~T[10:05:00]}
      assert Localize.Time.parse("१०:०५ AM", locale: :mr) == {:ok, ~T[10:05:00]}
    end

    test "in Latin digits in a locale that writes its own" do
      assert Localize.Time.parse("10:05 AM", locale: :bn) == {:ok, ~T[10:05:00]}
    end

    # ICU4C's long times at 10:05 in New York: TR35 writes the localized
    # GMT format's offset in the locale's digits too.
    test "with a GMT offset in the locale's digits" do
      assert {:ok, %{hour: 10, minute: 5, second: 0, utc_offset: -14_400}} =
               Localize.Time.parse("१०:०५:०० GMT-४", locale: :ne, as: :map)

      assert {:ok, %{hour: 10, minute: 5, second: 0, utc_offset: -14_400}} =
               Localize.Time.parse("GMT-၄ ၁၀:၀၅:၀၀", locale: :my, as: :map)
    end
  end

  describe "a date-time" do
    # `bn`'s short date-time is "d/M/yy, h:mm a" in Bengali digits.
    test "in the locale's digits" do
      assert Localize.DateTime.parse("১/৪/২৩, ১০:০৫ AM", locale: :bn) ==
               {:ok, ~N[2023-04-01 10:05:00]}
    end
  end

  describe "a name written in the locale's digits" do
    # `dz`'s abbreviated months are Tibetan numbers ("༤" is April), and its
    # medium date is "སྤྱི་ལོ་y ཟླ་MMM ཚེས་dd".
    test "a month" do
      assert Localize.Date.parse("སྤྱི་ལོ་༢༠༢༣ ཟླ་༤ ཚེས་༠༡", locale: :dz) ==
               {:ok, ~D[2023-04-01]}
    end

    # CLDR names `bn`'s second quarter "২য় ত্রৈমাসিক"; ICU4C 78.3 does not
    # read quarter names back.
    test "a quarter" do
      assert Localize.Date.parse("২য় ত্রৈমাসিক ২০২৩", locale: :bn, as: :map) ==
               {:ok, %{calendar: Calendar.ISO, year: 2023, quarter: 2}}
    end

    # `ckb`'s short weekday names are Arabic-Indic numbers ("٢ش" is Monday),
    # which ICU4C 78.3 reads in place of `yMEd`'s "EEE، d/M/y".
    test "a weekday" do
      assert Localize.Date.parse("٢ش، ٣/٤/٢٠٢٣", locale: :ckb) == {:ok, ~D[2023-04-03]}
    end

    # ICU4C 78.3's `GyMMMd` for 1742-06-01 in its Japanese calendar, the
    # second year of Kanpō, whose name carries the era's years in the
    # locale's digits; `ar-EG`'s ends with a right-to-left mark.
    test "an era" do
      rlm = <<0x200F::utf8>>

      for {locale, text} <- [
            {:"ff-Adlm", "𞥑 𞤑𞤮𞤪𞤧𞤮⹁ 𞥒 𞤑𞤢𞤥𞤨𞤮𞥅 (𞥑𞥗𞥔𞥑-𞥑𞥗𞥔𞥔)"},
            {:"ar-EG", "١ يونيو ٢ كنبو (١٧٤١–١٧٤٤)" <> rlm}
          ] do
        assert Localize.Date.parse(text, locale: locale, calendar: Japanese) ==
                 {:ok, Date.new!(1742, 6, 1, Japanese)}
      end
    end
  end
end
