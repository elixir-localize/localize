defmodule Localize.IntervalStandardFormatTest do
  @moduledoc """
  An interval at a standard format writes its dates and times as the
  single value is written at that format (user, 2026-10-04: "the
  pattern").

  CLDR gives each standard format a pattern and a `datetimeSkeleton`,
  which TR35 calls "derived from the pattern". In many locales it is not:
  one of the two is the locale's own and the other inherited, or the
  pattern changed and the skeleton did not. An interval takes the fields
  of the pattern, at the pattern's widths, and CLDR's interval item for
  them. Each expected string is that item's pattern in CLDR 49's XML
  (`common/main`), at the widths of the standard format's pattern there,
  applied by hand; the patterns are quoted beside the cases.

  """

  use ExUnit.Case, async: true

  alias Localize.DateTime.Format.Match

  @from ~D[2023-04-01]
  @day ~D[2023-04-10]
  @year ~D[2024-05-10]

  defp single(value, locale, format) do
    module = if is_struct(value, Date), do: Localize.Date, else: Localize.Time
    module.to_string(value, locale: locale, format: format)
  end

  defp interval(from, to, locale, format),
    do: Localize.Interval.to_string(from, to, locale: locale, format: format)

  describe "a date interval at a standard format" do
    # `vi.xml`: short date "d/M/yy", its `datetimeSkeleton` inherited from
    # root (`yMMdd`); `yMd` interval "d/M/y – d/M/y", thin spaces about the
    # dash. The interval was "01/04/2023 – 10/04/2023".
    test "takes the widths of the pattern where the skeleton is inherited" do
      assert single(@from, :vi, :short) == {:ok, "1/4/23"}
      assert interval(@from, @day, :vi, :short) == {:ok, "1/4/23 – 10/4/23"}
      assert interval(@from, @year, :vi, :short) == {:ok, "1/4/23 – 10/5/24"}
    end

    # `en_CA.xml`: short date "y-MM-dd" beside `en`'s skeleton `yyMd`, and a
    # `yMd` interval of "M/d/y–M/d/y". `zu.xml`: its own skeleton `yyMd`
    # beside root's pattern "y-MM-dd" and root's interval "y-MM-dd – y-MM-dd".
    # They were "4/1/23–4/10/23" and "23-04-01 – 23-04-10".
    test "takes the widths of the pattern where the pattern is inherited or the skeleton is" do
      assert single(@from, :"en-CA", :short) == {:ok, "2023-04-01"}
      assert interval(@from, @day, :"en-CA", :short) == {:ok, "04/01/2023–04/10/2023"}

      assert single(@from, :zu, :short) == {:ok, "2023-04-01"}

      assert interval(@from, @day, :zu, :short) ==
               {:ok, "2023-04-01 – 2023-04-10"}
    end

    # `id.xml`: short date "d/M/yy" beside `yyMMdd`, `yMd` interval
    # "d/M/y–d/M/y". `sr.xml`: medium date "d. M. y." beside `yMMdd`, `yMd`
    # interval "d. M. y. – d. M. y.".
    test "takes the widths of the pattern where the skeleton was left behind" do
      assert single(@from, :id, :short) == {:ok, "1/4/23"}
      assert interval(@from, @day, :id, :short) == {:ok, "1/4/23–10/4/23"}

      assert single(@from, :sr, :medium) == {:ok, "1. 4. 2023."}
      assert interval(@from, @day, :sr, :medium) == {:ok, "1. 4. 2023. – 10. 4. 2023."}
    end

    # `be.xml`: medium date "d MMM y 'г'." beside a skeleton of a numeric
    # month, `yMMd`; `yMMMd` interval "d–d MMM y". `en_IN.xml`: its own
    # skeleton `yMMMdd` beside `en_001`'s pattern "d MMM y" and interval
    # "d–d MMM y". They were "1.04.2023 – 10.04.2023" and "01 – 10 Apr 2023".
    test "takes the month and the day as the pattern writes them" do
      assert single(@from, :be, :medium) == {:ok, "1 кра 2023 г."}
      assert interval(@from, @day, :be, :medium) == {:ok, "1–10 кра 2023"}

      assert single(@from, :"en-IN", :medium) == {:ok, "1 Apr 2023"}
      assert interval(@from, @day, :"en-IN", :medium) == {:ok, "1–10 Apr 2023"}
    end

    # A month a pattern writes as a number beside a word is the month's
    # name as the locale writes it: `ja.xml`'s long date is "y年M月d日"
    # beside `yMMMd`, whose interval is "y年M月d日～d日". ECMA-402's
    # `formatRange` takes the pattern's letters as they stand, a numeric
    # month, and writes "2023/04/01～2023/04/10" (Node 24, ICU 77).
    test "keeps the month a name where the pattern numbers it beside a word" do
      assert single(@from, :ja, :long) == {:ok, "2023年4月1日"}
      assert interval(@from, @day, :ja, :long) == {:ok, "2023年4月1日～10日"}
      assert interval(@from, @year, :ja, :long) == {:ok, "2023年4月1日～2024年5月10日"}

      assert single(@from, :zh, :long) == {:ok, "2023年4月1日"}
      assert {:ok, zh} = interval(@from, @year, :zh, :long)
      assert String.starts_with?(zh, "2023年4月1日")
    end

    # Where the skeleton is the pattern's, nothing changes: `en.xml`'s
    # medium date "MMM d, y" beside `yMMMd`, interval "MMM d – d, y".
    test "is as it was where the skeleton is the pattern's" do
      assert interval(@from, @day, :en, :medium) == {:ok, "Apr 1 – 10, 2023"}
      assert interval(@from, @day, :en, :short) == {:ok, "4/1/23 – 4/10/23"}
      assert interval(@from, @day, :de, :medium) == {:ok, "01.–10.04.2023"}
    end

    # The contract itself, in locales whose interval item writes both dates
    # in the order and the text of the standard format: the first date of an
    # interval across years is the date as it is written alone.
    test "writes its first date as the date alone is written" do
      for {locale, format} <- [
            {:vi, :short},
            {:id, :short},
            {:te, :short},
            {:qu, :short},
            {:om, :short},
            {:om, :medium},
            {:sr, :short},
            {:sr, :medium},
            {:sl, :short},
            {:"sv-FI", :short},
            {:"en-NZ", :short},
            {:"en-IN", :medium},
            {:eo, :short},
            {:zu, :short},
            {:ja, :long},
            {:ko, :long}
          ] do
        assert {:ok, alone} = single(@from, locale, format)
        assert {:ok, range} = interval(@from, @year, locale, format)
        assert String.starts_with?(range, alone), "#{locale} #{format}: #{range} beside #{alone}"
      end
    end

    # `kek.xml`'s fallback pattern is "{1} – {0}", which TR35 makes the order
    # of its interval formats, so the date written first is the later one,
    # and each is still the date as it is written alone.
    test "writes the later date first where the locale's fallback pattern does" do
      assert {:ok, earlier} = single(@from, :kek, :short)
      assert {:ok, later} = single(@year, :kek, :short)
      assert {:ok, range} = interval(@from, @year, :kek, :short)

      assert String.starts_with?(range, later), "#{range} beside #{later}"
      assert String.ends_with?(range, earlier), "#{range} beside #{earlier}"
    end
  end

  describe "a time interval at the short format" do
    # `ady` has no time format of its own, so its short time is root's
    # "HH:mm", while Jordan prefers a 12-hour clock (`supplementalData.xml`,
    # `hours preferred="h"`). The interval takes root's `Hm` item,
    # "HH:mm–HH:mm", where it took the preferred cycle's and was
    # "10:05–11:30 AM".
    test "is in the clock of the short time pattern" do
      assert single(~T[10:05:00], :"ady-JO", :short) == {:ok, "10:05"}
      assert interval(~T[10:05:00], ~T[11:30:00], :"ady-JO", :short) == {:ok, "10:05–11:30"}
      assert interval(~T[10:05:00], ~T[14:30:00], :"ady-JO", :short) == {:ok, "10:05–14:30"}
    end

    # `en.xml`: short time "h:mm a", `hm` interval "h:mm – h:mm a" within a
    # day period and "h:mm a – h:mm a" across noon. `de.xml`: short time
    # "HH:mm", `Hm` interval "HH:mm–HH:mm 'Uhr'".
    test "is as it was where the pattern is in the locale's clock" do
      assert interval(~T[10:05:00], ~T[11:30:00], :en, :short) ==
               {:ok, "10:05 – 11:30 AM"}

      assert interval(~T[10:05:00], ~T[14:30:00], :en, :short) ==
               {:ok, "10:05 AM – 2:30 PM"}

      assert interval(~T[10:05:00], ~T[14:30:00], :de, :short) == {:ok, "10:05–14:30 Uhr"}
    end

    # A `-u-hc-` hour cycle is in the pattern the time is written with:
    # `en`'s `Hm` interval is "HH:mm – HH:mm".
    test "takes a locale's hour cycle override" do
      assert single(~T[10:05:00], "en-u-hc-h23", :short) == {:ok, "10:05"}

      assert interval(~T[10:05:00], ~T[14:30:00], "en-u-hc-h23", :short) ==
               {:ok, "10:05 – 14:30"}
    end

    # `zh_Hant.xml`'s short time is "Bh:mm", a flexible day period, so its
    # interval is the `Bhm` item's and names the period the time alone does.
    test "takes the day period the pattern writes" do
      assert single(~T[02:05:00], :"zh-Hant", :short) == {:ok, "凌晨2:05"}
      assert {:ok, range} = interval(~T[02:05:00], ~T[03:30:00], :"zh-Hant", :short)
      assert String.starts_with?(range, "凌晨2:05")
    end

    # A time without one of its fields has no standard pattern; its interval
    # is as it was.
    test "of a time without its seconds is as it was" do
      assert Localize.Interval.to_string(%{hour: 9, minute: 5}, %{hour: 17, minute: 30},
               locale: :en,
               format: :short
             ) == {:ok, "9:05 AM – 5:30 PM"}
    end
  end

  describe "a date and time interval at a standard format" do
    # `bo.xml` has a time skeleton of its own, `ahmm`, beside root's pattern
    # "HH:mm", so the time alone is 24-hour and the range was 12-hour, with
    # day periods. It takes root's `Hm` item now, "HH:mm–HH:mm".
    test "writes its times in the clock of the time pattern" do
      from = ~N[2023-04-01 10:05:00]
      to = ~N[2023-04-01 14:30:00]

      assert Localize.DateTime.to_string(from, locale: :bo, format: :short) ==
               {:ok, "2023-04-01 10:05"}

      assert Localize.Interval.to_string(from, to, locale: :bo, format: :short) ==
               {:ok, "2023-04-01 10:05–14:30"}
    end

    test "is as it was where the skeleton is the pattern's" do
      from = ~N[2023-04-01 10:05:00]

      assert Localize.Interval.to_string(from, ~N[2023-04-01 14:30:00],
               locale: :en,
               format: :short
             ) == {:ok, "4/1/23, 10:05 AM – 2:30 PM"}
    end
  end

  describe "the fields of a pattern" do
    test "are its letters at their widths, in a skeleton's order" do
      for {pattern, skeleton} <- [
            {"d/M/yy", "yyMd"},
            {"y-MM-dd", "yMMdd"},
            {"EEEE, MMMM d, y", "yMMMMEEEEd"},
            {"y年M月d日", "yMd"},
            {"h:mm a", "ahmm"},
            {"Bh:mm", "Bhmm"},
            {"HH:mm:ss zzzz", "HHmmsszzzz"},
            {"d MMM y G", "GyMMMd"}
          ] do
        assert Match.pattern_skeleton(pattern) == skeleton, pattern
      end
    end

    # Quoted text is no field, a doubled quote within it is a quote, and a
    # quote closed before a combining mark is still closed: `nnh`'s long date
    # puts U+030C after one.
    test "are not its quoted text" do
      assert Match.pattern_skeleton("d MMM y 'г'.") == "yMMMd"
      assert Match.pattern_skeleton("HH 'h' mm") == "HHmm"
      assert Match.pattern_skeleton("h 'o''clock' a") == "ah"
      assert Match.pattern_skeleton("'Ngày' dd 'tháng' M 'năm' y G") == "GyMdd"
      assert Match.pattern_skeleton("'lyɛ'̌ʼ d 'na' MMMM, y") == "yMMMMd"
      assert Match.pattern_skeleton("") == ""
      assert Match.pattern_skeleton("'no fields'") == ""
    end
  end
end
