defmodule Localize.DateTime.StringSkeletonTest do
  @moduledoc """
  A skeleton given as text, `format: {:skeleton, "yMMMd"}`, formats as the
  skeleton atom `:yMMMd` does, in every locale and calendar, and makes no
  atom of the text.

  A string alone stays a pattern (`"yMMMd"` writes "2026Oct27"), so a
  skeleton that arrives as text, as the argument of ICU MessageFormat's
  `{d, date, ::yMMMd}` does, could not be used without making an atom from
  it. The equivalence with the atom form is the test's oracle for the
  sweep; the expected strings of the first test are CLDR's own patterns
  for those skeletons.

  Not `async`: one test reads the VM's atom count, which a test running
  beside it would move.

  """

  use ExUnit.Case, async: false

  alias Localize.Utils.Helpers

  @date_skeletons ~w(y yMd yMMMd yMMMMd yMMMEd yMMMMEEEEd GyMMMd yMMM yMMMM MMMd MEd Md yQQQ yw MMMMW yMMMdQ)
  @time_skeletons ~w(hm Hm jm jms hms Hms Bhm Jm Cm jmsSSS)
  @datetime_skeletons ~w(yMMMdjm yMdHms yMMMMEEEEdjms MMMdjm yMMMdQhm Ehm MdJm yMMMdjmsSSS)

  @hour_cycle_locales [
    :"en-u-hc-h23",
    :"en-u-hc-h11",
    :"ja-u-hc-h11",
    :"de-u-hc-h12",
    :"fr-u-hc-h24"
  ]

  @calendar_locales [:en, :he, :ar, :fa, :zh, :ko, :ja, :th, :de]

  # Localize does not depend on Calendrical, so a stand-in answers for a
  # calendar of each CLDR type, whose formats and month names are that
  # type's. Its arithmetic is the Gregorian calendar's, so its eras are
  # too: the era a stand-in answers is no era of a calendar with one.
  @cldr_calendar_types [
    hebrew: Hebrew,
    islamic: Islamic,
    persian: Persian,
    chinese: Chinese,
    dangi: Dangi,
    buddhist: Buddhist,
    japanese: Japanese,
    generic: Generic
  ]

  for {cldr_type, name} <- @cldr_calendar_types do
    defmodule Module.concat(__MODULE__, name) do
      @moduledoc false
      use Localize.Test.StandInCalendar

      def cldr_calendar_type, do: unquote(cldr_type)
      def era_calendar_type, do: :gregorian
    end
  end

  # A calendar of two CLDR types, as a reform calendar is of the calendar
  # before its change and the one after.
  defmodule Reform do
    @moduledoc false
    use Localize.Test.StandInCalendar

    def cldr_calendar_type, do: :gregorian
    def era_calendar_type, do: :gregorian
    def cldr_calendar_type(year, _month, _day) when year < 2000, do: :generic
    def cldr_calendar_type(_year, _month, _day), do: :gregorian
  end

  @date ~D[2026-10-27]
  @time ~T[14:30:45.123456]
  @naive ~N[2026-10-27 14:30:45.123456]

  defp calendars do
    stand_ins =
      for {_cldr_type, name} <- @cldr_calendar_types, do: Module.concat(__MODULE__, name)

    [Calendar.ISO, Localize.Test.FiscalCalendar, Reform | stand_ins]
  end

  defp date_in(calendar, year \\ 2026) do
    %Date{year: year, month: 10, day: 27, calendar: calendar}
  end

  defp naive_in(calendar) do
    %{@naive | calendar: calendar}
  end

  defp zoned do
    DateTime.from_naive!(@naive, "Etc/UTC")
  end

  # The atom form is the oracle: the atom is made here, in the test, from
  # a skeleton the test itself lists.
  defp as_atom(skeleton), do: String.to_atom(skeleton)

  defp assert_same(module, function, value, skeleton, options) do
    from_text = apply(module, function, [value, [format: {:skeleton, skeleton}] ++ options])
    from_atom = apply(module, function, [value, [format: as_atom(skeleton)] ++ options])

    assert from_text == from_atom,
           "#{inspect(module)}.#{function} #{skeleton} #{inspect(options)}: " <>
             "text #{inspect(from_text)}, atom #{inspect(from_atom)}"

    from_text
  end

  describe "a skeleton given as text" do
    test "writes CLDR's pattern for the skeleton" do
      # en `yMMMd` is "MMM d, y", fr `yMMMd` "d MMM y", de `yMd` "d.M.y",
      # en `Hm` "HH:mm" and en `yMMMd` with `Hm` joined by "{1}, {0}".
      assert Localize.Date.to_string(@date, format: {:skeleton, "yMMMd"}, locale: :en) ==
               {:ok, "Oct 27, 2026"}

      assert Localize.Date.to_string(@date, format: {:skeleton, "yMMMd"}, locale: :fr) ==
               {:ok, "27 oct. 2026"}

      assert Localize.Date.to_string(@date, format: {:skeleton, "yMd"}, locale: :de) ==
               {:ok, "27.10.2026"}

      assert Localize.Time.to_string(@time, format: {:skeleton, "Hm"}, locale: :en) ==
               {:ok, "14:30"}

      assert Localize.DateTime.to_string(@naive, format: {:skeleton, "yMMMdHm"}, locale: :en) ==
               {:ok, "Oct 27, 2026, 14:30"}
    end

    test "is not the pattern the same string is" do
      assert Localize.Date.to_string(@date, format: "yMMMd", locale: :en) == {:ok, "2026Oct27"}

      assert Localize.Date.to_string(@date, format: {:skeleton, "yMMMd"}, locale: :en) ==
               {:ok, "Oct 27, 2026"}
    end
  end

  describe "a skeleton given as text formats as its atom does" do
    test "for a date in every installed locale" do
      for locale <- Localize.Test.InstalledLocales.all(), skeleton <- @date_skeletons do
        assert {:ok, _written} =
                 assert_same(Localize.Date, :to_string, @date, skeleton, locale: locale)
      end
    end

    test "for a time in every installed locale" do
      for locale <- Localize.Test.InstalledLocales.all(), skeleton <- @time_skeletons do
        assert {:ok, _written} =
                 assert_same(Localize.Time, :to_string, @time, skeleton, locale: locale)
      end
    end

    test "for a date-time in every installed locale, with a zone and without" do
      for locale <- Localize.Test.InstalledLocales.all(),
          skeleton <- @datetime_skeletons ++ ~w(yMMMdjmz jmv vvvv),
          value <- [@naive, zoned()] do
        assert {:ok, _written} =
                 assert_same(Localize.DateTime, :to_string, value, skeleton, locale: locale)
      end
    end

    test "for a date and a date-time in every calendar" do
      for calendar <- calendars(), locale <- @calendar_locales do
        for skeleton <- @date_skeletons do
          assert {:ok, _written} =
                   assert_same(Localize.Date, :to_string, date_in(calendar), skeleton,
                     locale: locale
                   )
        end

        for skeleton <- @datetime_skeletons do
          assert_same(Localize.DateTime, :to_string, naive_in(calendar), skeleton, locale: locale)
        end
      end
    end

    test "for a reform calendar's date before its change" do
      for locale <- @calendar_locales, skeleton <- @date_skeletons do
        assert_same(Localize.Date, :to_string, date_in(Reform, 1999), skeleton, locale: locale)
      end
    end

    test "under a locale's hour cycle" do
      for locale <- @hour_cycle_locales do
        for skeleton <- @time_skeletons do
          assert_same(Localize.Time, :to_string, @time, skeleton, locale: locale)
        end

        for skeleton <- @datetime_skeletons do
          assert_same(Localize.DateTime, :to_string, @naive, skeleton, locale: locale)
        end
      end
    end

    test "in parts" do
      for locale <- [:en, :fr, :ja, :ar, :"en-u-hc-h23"] do
        for skeleton <- @date_skeletons do
          assert_same(Localize.Date, :to_parts, @date, skeleton, locale: locale)
        end

        for skeleton <- @time_skeletons do
          assert_same(Localize.Time, :to_parts, @time, skeleton, locale: locale)
        end

        for skeleton <- @datetime_skeletons do
          assert_same(Localize.DateTime, :to_parts, @naive, skeleton, locale: locale)
        end
      end
    end

    test "for a value holding only some of its fields" do
      for locale <- [:en, :fr, :ja, :de] do
        assert_same(Localize.Date, :to_string, %{year: 2026, month: 3}, "yMMM", locale: locale)
        assert_same(Localize.Date, :to_string, %{month: 3, day: 9}, "MMMd", locale: locale)
        assert_same(Localize.Time, :to_string, %{hour: 14, minute: 30}, "jm", locale: locale)

        partial = %{year: 2026, month: 6, hour: 14}
        assert_same(Localize.DateTime, :to_string, partial, "yMMMj", locale: locale)
      end
    end

    test "where the value lacks a field the skeleton asks for" do
      assert {:error, %Localize.DateTimeInvalidInputError{}} =
               assert_same(Localize.Date, :to_string, %{year: 2026}, "yMMMd", locale: :en)

      assert {:error, %Localize.DateTimeInvalidInputError{}} =
               assert_same(Localize.Time, :to_string, %{hour: 14}, "jms", locale: :en)
    end

    test "as the date half and the time half of a date-time" do
      for locale <- [:en, :fr, :ja, :ar], {date_half, time_half} <- halves() do
        from_text =
          Localize.DateTime.to_string(@naive,
            date_format: {:skeleton, date_half},
            time_format: {:skeleton, time_half},
            locale: locale
          )

        from_atom =
          Localize.DateTime.to_string(@naive,
            date_format: as_atom(date_half),
            time_format: as_atom(time_half),
            locale: locale
          )

        assert {:ok, _written} = from_text
        assert from_text == from_atom, "#{locale} #{date_half} #{time_half}"
      end
    end
  end

  describe "text written with a skeleton given as text" do
    test "is read back with it, as with its atom" do
      for locale <- [:en, :fr, :ja, :de, :ar, :he, :ko, :th] do
        for skeleton <- ~w(yMd yMMMd yMMMMd yMMMMEEEEd) do
          assert_reads_back(Localize.Date, @date, skeleton, locale)
        end

        for skeleton <- ~w(Hm Hms jm jms) do
          assert_reads_back(Localize.Time, ~T[14:30:45], skeleton, locale)
        end

        for skeleton <- ~w(yMMMdjm yMdHms yMMMMEEEEdjms) do
          assert_reads_back(Localize.DateTime, ~N[2026-10-27 14:30:45], skeleton, locale)
        end
      end
    end

    test "is read by the halves of a date-time given as text" do
      assert Localize.DateTime.parse("Oct 27, 2026, 2:30 PM",
               date_format: {:skeleton, "yMMMd"},
               time_format: {:skeleton, "jm"},
               locale: :en
             ) == {:ok, ~N[2026-10-27 14:30:00]}
    end

    test "is not read with text that is no skeleton" do
      for module <- [Localize.Date, Localize.Time, Localize.DateTime] do
        assert {:error, %Localize.DateTimeFormatError{reason: :invalid_format}} =
                 module.parse("Oct 27, 2026", format: {:skeleton, "bogus"}, locale: :en)
      end
    end
  end

  describe "a skeleton no atom names" do
    test "formats as the atom does once the atom is made" do
      for {module, value, skeleton} <- unnamed_cases(), locale <- [:en, :fr, :ja] do
        assert is_nil(Helpers.existing_atom(skeleton)), "#{skeleton} is an atom already"

        from_text = module.to_string(value, format: {:skeleton, skeleton}, locale: locale)
        assert {:ok, _written} = from_text
        assert is_nil(Helpers.existing_atom(skeleton)), "#{skeleton} was made an atom"
      end

      # The atoms are made only now, so every text result above took the
      # path of a skeleton no atom names.
      for {module, value, skeleton} <- unnamed_cases(), locale <- [:en, :fr, :ja] do
        from_text = module.to_string(value, format: {:skeleton, skeleton}, locale: locale)
        from_atom = module.to_string(value, format: as_atom(skeleton), locale: locale)
        assert from_text == from_atom, "#{inspect(module)} #{skeleton} #{locale}"
      end
    end

    test "adds no atom to the VM" do
      skeletons = Enum.filter(generated_skeletons(), &is_nil(Helpers.existing_atom(&1)))
      {warm_up, measured} = Enum.split(skeletons, 4)
      assert match?([_, _, _, _, _, _, _, _, _, _ | _], measured)

      # The first calls load what the locales need, atoms included.
      format_all(warm_up)
      before = :erlang.system_info(:atom_count)
      format_all(measured)

      assert :erlang.system_info(:atom_count) == before
      assert Enum.all?(measured, &is_nil(Helpers.existing_atom(&1)))
    end
  end

  describe "text that is no skeleton" do
    test "is an error for a date, a time and a date-time" do
      for skeleton <- invalid_skeletons() do
        for {module, value} <- [
              {Localize.Date, @date},
              {Localize.Time, @time},
              {Localize.DateTime, @naive}
            ] do
          assert {:error, %Localize.DateTimeFormatError{reason: :invalid_format}} =
                   module.to_string(value, format: {:skeleton, skeleton}, locale: :en),
                 "#{inspect(module)} #{inspect(skeleton)}"

          assert {:error, %Localize.DateTimeFormatError{reason: :invalid_format}} =
                   module.to_parts(value, format: {:skeleton, skeleton}, locale: :en),
                 "#{inspect(module)} #{inspect(skeleton)}"
        end
      end
    end

    test "is an error as the date half or the time half of a date-time" do
      assert {:error, %Localize.DateTimeFormatError{reason: :invalid_format}} =
               Localize.DateTime.to_string(@naive,
                 date_format: {:skeleton, "bogus"},
                 time_format: {:skeleton, "jm"},
                 locale: :en
               )

      assert {:error, %Localize.DateTimeFormatError{reason: :invalid_format}} =
               Localize.DateTime.to_string(@naive,
                 date_format: {:skeleton, "yMd"},
                 time_format: {:skeleton, "bogus"},
                 locale: :en
               )
    end

    test "has a message naming it" do
      {:error, exception} = Localize.Date.to_string(@date, format: {:skeleton, "bogus"})
      assert Exception.message(exception) =~ "bogus"
    end
  end

  defp assert_reads_back(module, value, skeleton, locale) do
    {:ok, written} = module.to_string(value, format: {:skeleton, skeleton}, locale: locale)

    from_text = module.parse(written, format: {:skeleton, skeleton}, locale: locale)
    from_atom = module.parse(written, format: as_atom(skeleton), locale: locale)

    assert {:ok, _read} = from_text, "#{inspect(module)} #{skeleton} #{locale} #{written}"
    assert from_text == from_atom, "#{inspect(module)} #{skeleton} #{locale} #{written}"
  end

  defp halves do
    [{"yMMMMEEEEd", "jm"}, {"yMd", "Hms"}, {"yMMMd", "jms"}, {"MMMd", "Bhm"}]
  end

  # Widths no format id has, so no atom names them until the test makes
  # one.
  defp unnamed_cases do
    [
      {Localize.Date, @date, "yyyyyMMMMMdd"},
      {Localize.Date, @date, "GGGGGyyyyMMMMEEEEEEd"},
      {Localize.Date, @date, "yyyyQQQQQ"},
      {Localize.Time, @time, "HHmmssSSSSS"},
      {Localize.Time, @time, "hhmmssSSSSSSa"},
      {Localize.DateTime, @naive, "yyyyyMMMMMddHHmmss"},
      {Localize.DateTime, @naive, "GGGGyyyMMMMEEEEEdjjmmssSSSS"}
    ]
  end

  defp generated_skeletons do
    for year <- 3..6, month <- 1..5, day <- 1..2 do
      String.duplicate("y", year) <> String.duplicate("M", month) <> String.duplicate("d", day)
    end
  end

  defp format_all(skeletons) do
    for skeleton <- skeletons, locale <- [:en, :fr] do
      assert {:ok, _date} =
               Localize.Date.to_string(@date, format: {:skeleton, skeleton}, locale: locale)

      assert {:ok, _datetime} =
               Localize.DateTime.to_string(@naive,
                 format: {:skeleton, skeleton <> "jms"},
                 locale: locale
               )

      assert {:ok, _time} =
               Localize.Time.to_string(@time,
                 format: {:skeleton, "jms" <> String.duplicate("S", String.length(skeleton))},
                 locale: locale
               )
    end
  end

  defp invalid_skeletons do
    [
      "",
      "bogus",
      "y M d",
      "yMMMd'",
      "yMd-",
      "年",
      String.duplicate("y", 65),
      :yMd,
      ~c"yMd",
      123,
      nil,
      {:skeleton, "yMd"}
    ]
  end
end
