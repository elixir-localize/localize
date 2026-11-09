defmodule Localize.DateTime.StrptimeTest do
  use ExUnit.Case, async: true

  doctest Localize.DateTime.Strptime

  alias Localize.DateTime.Strptime

  describe "pattern/2" do
    test "translates every directive Calendar.strftime/3 writes, and the C ones that read the same" do
      assert Strptime.pattern("%a %A %b %h %B") == {:ok, "EEE EEEE MMM MMM MMMM"}
      assert Strptime.pattern("%d %e %j %m %q %y %Y") == {:ok, "dd d DDD MM Q yy y"}
      assert Strptime.pattern("%H %k %I %l %M %S %f %p %P") == {:ok, "HH H hh h mm ss SSSSSS a a"}
      assert Strptime.pattern("%z %Z") == {:ok, "xx zzzz"}
      assert Strptime.pattern("%D %F %T %R") == {:ok, "MM/dd/yy y-MM-dd HH:mm:ss HH:mm"}
    end

    test "quotes literal letters, keeps other text, and writes a literal percent sign" do
      assert Strptime.pattern("%Y-%m-%dT%H:%M") == {:ok, "y-MM-dd'T'HH:mm"}
      assert Strptime.pattern("Week of %d") == {:ok, "'Week of' dd"}
      assert Strptime.pattern("100%% on %d") == {:ok, "100% 'on' dd"}
      assert Strptime.pattern("%d o'clock") == {:ok, "dd 'o''clock'"}
    end

    test "ignores padding and width modifiers" do
      assert Strptime.pattern("%-d/%_m/%05Y %-H") == {:ok, "dd/MM/y HH"}
    end

    test "%n and %t are whitespace" do
      assert Strptime.pattern("%d%n%m%t%Y") == {:ok, "dd MM y"}
    end

    test "%c, %x and %X take the preferred formats, with Calendar.strftime/3's defaults" do
      assert Strptime.pattern("%c") == {:ok, "y-MM-dd HH:mm:ss"}
      assert Strptime.pattern("%x") == {:ok, "y-MM-dd"}
      assert Strptime.pattern("%X") == {:ok, "HH:mm:ss"}

      assert Strptime.pattern("%c", preferred_datetime: "%a %d %b %Y %T") ==
               {:ok, "EEE dd MMM y HH:mm:ss"}
    end

    test "a preferred format may not contain %c, %x or %X" do
      assert {:error,
              %Localize.DateTimeFormatError{
                reason: :unsupported_directive,
                detail: "%c inside a preferred format"
              }} = Strptime.pattern("%c", preferred_datetime: "%c")

      assert {:error, %Localize.DateTimeFormatError{detail: "%x inside a preferred format"}} =
               Strptime.pattern("%c", preferred_datetime: "%x %X")
    end

    test "directives Localize does not read are errors naming the directive" do
      for directive <- ~w(%s %u %w %U %W %V %G %g %C %Ey %Od %Q %!) do
        assert {:error,
                %Localize.DateTimeFormatError{
                  format: format,
                  reason: :unsupported_directive,
                  detail: detail
                }} = Strptime.pattern("%Y " <> directive)

        assert format == "%Y " <> directive
        assert String.starts_with?(directive, detail)
      end

      assert Strptime.pattern("%Y %") ==
               {:error,
                %Localize.DateTimeFormatError{
                  format: "%Y %",
                  reason: :unsupported_directive,
                  detail: "%"
                }}
    end

    test "invalid arguments are errors, not raises" do
      assert {:error, %Localize.InvalidValueError{}} = Strptime.pattern(nil)
      assert {:error, %Localize.InvalidValueError{}} = Strptime.pattern("%Y", :bogus)
      assert {:error, %Localize.InvalidValueError{}} = Strptime.pattern(<<0xFF>>)
      assert {:error, %Localize.InvalidValueError{}} = Strptime.pattern("%Y" <> <<0xC3>>)

      assert {:error, %Localize.InvalidValueError{}} =
               Strptime.pattern("%c", preferred_datetime: 42)

      assert {:error, %Localize.InvalidValueError{}} =
               Strptime.pattern("%c", preferred_datetime: <<0xFF>>)
    end

    test "parse_options/2 returns the options for parse/2, or an error" do
      assert Strptime.parse_options([locale: :de, preferred_date: "%d.%m.%Y"], "dd.MM.y") ==
               {:ok, [format: "dd.MM.y", locale: :de]}

      assert {:error, %Localize.InvalidValueError{}} = Strptime.parse_options(nil, "y")
      assert {:error, %Localize.InvalidValueError{}} = Strptime.parse_options([1, 2], "y")
      assert {:error, %Localize.InvalidValueError{}} = Strptime.parse_options([], nil)
    end
  end

  describe "strptime/3" do
    test "reads what Calendar.strftime/3 writes with Localize's names, in each locale" do
      date_time = ~N[2026-03-04 19:05:09]

      formats = [
        "%A, %d %B %Y %I:%M:%S %p",
        "%a %d %b %Y %H:%M:%S",
        "%Y-%m-%dT%H:%M:%S",
        "%c",
        "%x %X"
      ]

      for locale <- [:en, :de, :fr, :es, :ja], format <- formats do
        options = Localize.Calendar.strftime_options!(locale: locale)
        written = Calendar.strftime(date_time, format, options)

        assert Localize.DateTime.strptime(written, format, locale: locale) == {:ok, date_time},
               "#{locale} #{format}: #{inspect(written)}"
      end
    end

    test "reads dates and times alone" do
      assert Localize.Date.strptime("04/03/2026", "%d/%m/%Y", locale: :en) ==
               {:ok, ~D[2026-03-04]}

      assert Localize.Date.strptime("03/04/26", "%D", locale: :en) == {:ok, ~D[2026-03-04]}
      assert Localize.Date.strptime("2026-03-04", "%F", locale: :en) == {:ok, ~D[2026-03-04]}
      assert Localize.Time.strptime("19:05:09", "%T", locale: :en) == {:ok, ~T[19:05:09]}
      assert Localize.Time.strptime("19:05", "%R", locale: :en) == {:ok, ~T[19:05:00]}
      assert Localize.Time.strptime("7:05 pm", "%I:%M %p", locale: :en) == {:ok, ~T[19:05:00]}
    end

    test "reads unpadded fields and runs of whitespace, as strptime(3) does" do
      assert Localize.DateTime.strptime("2026-3-4   7:05", "%Y-%m-%d %H:%M", locale: :en) ==
               {:ok, ~N[2026-03-04 07:05:00]}
    end

    test "reads either width of a name and either case of a day period, as strptime(3) does" do
      assert Localize.Date.strptime("4 March 2026", "%d %b %Y", locale: :en) ==
               {:ok, ~D[2026-03-04]}

      assert Localize.Date.strptime("4 Mar 2026", "%d %B %Y", locale: :en) ==
               {:ok, ~D[2026-03-04]}

      assert Localize.Time.strptime("7:05 PM", "%I:%M %P", locale: :en) == {:ok, ~T[19:05:00]}
    end

    test "reads an offset in either form" do
      expected = DateTime.new!(~D[2026-03-04], ~T[07:05:00], "+05:30", Localize.TimeZoneDatabase)

      assert Localize.DateTime.strptime("2026-03-04 07:05 +0530", "%Y-%m-%d %H:%M %z",
               locale: :en
             ) ==
               {:ok, expected}

      assert Localize.DateTime.strptime("2026-03-04 07:05 +05:30", "%Y-%m-%d %H:%M %z",
               locale: :en
             ) ==
               {:ok, expected}
    end

    test "a zone name resolves through the configured time zone database" do
      assert {:ok, %DateTime{time_zone: "America/Los_Angeles"}} =
               Localize.DateTime.strptime("2026-03-04 07:05 PST", "%Y-%m-%d %H:%M %Z",
                 locale: :en
               )
    end

    test "the whole string must match, where strptime(3) stops at the end of the format" do
      assert {:error, %Localize.DateTimeParseError{}} =
               Localize.DateTime.strptime("2026-03-04 07:05 and more", "%Y-%m-%d %H:%M",
                 locale: :en
               )
    end

    test "a two-digit year falls in the parser's window around the reference date, not at POSIX's pivot" do
      options = [locale: :en, reference_date: ~D[2026-03-04]]

      assert Localize.Date.strptime("69-03-04", "%y-%m-%d", options) == {:ok, ~D[1969-03-04]}
      assert Localize.Date.strptime("26-03-04", "%y-%m-%d", options) == {:ok, ~D[2026-03-04]}
      assert Localize.Date.strptime("50-03-04", "%y-%m-%d", options) == {:ok, ~D[1950-03-04]}
    end

    test "returns the fields read with as: :map" do
      assert Localize.Date.strptime("2026-03", "%Y-%m", locale: :en, as: :map) ==
               {:ok, %{calendar: Calendar.ISO, year: 2026, month: 3}}
    end

    test "a format that is not UTF-8 is an error, not a raise" do
      assert {:error, %Localize.InvalidValueError{}} =
               Localize.Date.strptime("2026", <<0xFF>>, locale: :en)

      assert {:error, %Localize.InvalidValueError{}} =
               Localize.DateTime.strptime("2026", "%Y" <> <<0xC3>>, locale: :en)
    end

    test "a tab in the text reads where the format has one, not for a space, %t or %n" do
      assert Localize.DateTime.strptime("2026-03-04\t07:05", "%F\t%R", locale: :en) ==
               {:ok, ~N[2026-03-04 07:05:00]}

      assert {:error, %Localize.DateTimeParseError{}} =
               Localize.DateTime.strptime("2026-03-04\t07:05", "%F %R", locale: :en)

      assert {:error, %Localize.DateTimeParseError{}} =
               Localize.DateTime.strptime("2026-03-04\t07:05", "%F%t%R", locale: :en)
    end

    test "an unsupported directive is an error before any parsing" do
      assert {:error, %Localize.DateTimeFormatError{reason: :unsupported_directive, detail: "%s"}} =
               Localize.DateTime.strptime("1762000000", "%s", locale: :en)
    end
  end
end
