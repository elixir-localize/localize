defmodule Localize.DateTime.SemanticSkeletonTest do
  @moduledoc """
  Conformance for TR35 semantic skeletons.

  CLDR ships no semantic-skeleton data — `semanticSkeleton` appears only in
  `common/testData/datetime/datetime.json`, which states the mapping from a
  semantic skeleton to the classical skeleton it resolves to, and the string
  each case should format to.

  This suite checks the mapping across all 240 cases the file carries for
  `en`, `ar-SA`, `ja-JP` and `th-TH` over the Gregorian, Buddhist, Japanese
  and Islamic civil calendars; the formatted output of the Gregorian cases;
  and TR35 §Hour Cycle Pattern Variations in `ja`, where the fixture itself
  cannot tell the clock preferences from the exact cycles.
  """

  use ExUnit.Case, async: true

  doctest Localize.DateTime.SemanticSkeleton

  alias Localize.DateTime.SemanticSkeleton, as: Skeleton

  # Localize has no calendar but `Calendar.ISO`; the others are Calendrical's,
  # which depends on Localize. A calendar selects its CLDR data by naming its
  # CLDR calendar type, which is all these stand-ins do.
  defmodule Japanese do
    @moduledoc false
    use Localize.Test.StandInCalendar
    def cldr_calendar_type, do: :japanese
    def cardinal_month(month), do: month
    def month_of_year(_year, month, _day), do: month
    defdelegate date_to_string(year, month, day), to: Calendar.ISO
  end

  defmodule Buddhist do
    @moduledoc false
    use Localize.Test.StandInCalendar
    def cldr_calendar_type, do: :buddhist
    def cardinal_month(month), do: month
    def month_of_year(_year, month, _day), do: month
    defdelegate date_to_string(year, month, day), to: Calendar.ISO
  end

  defmodule IslamicCivil do
    @moduledoc false
    use Localize.Test.StandInCalendar
    def cldr_calendar_type, do: :islamic_civil
    def cardinal_month(month), do: month
    def month_of_year(_year, month, _day), do: month
    defdelegate date_to_string(year, month, day), to: Calendar.ISO
  end

  defmodule Hebrew do
    @moduledoc false
    use Localize.Test.StandInCalendar
    def cldr_calendar_type, do: :hebrew
    def cardinal_month(month), do: month
    def month_of_year(_year, month, _day), do: month
    defdelegate date_to_string(year, month, day), to: Calendar.ISO
  end

  defmodule Chinese do
    @moduledoc false
    use Localize.Test.StandInCalendar
    def cldr_calendar_type, do: :chinese
    def cardinal_month(month), do: month
    def month_of_year(_year, month, _day), do: month
    defdelegate date_to_string(year, month, day), to: Calendar.ISO
  end

  @calendars %{
    "gregorian" => Calendar.ISO,
    "japanese" => Japanese,
    "buddhist" => Buddhist,
    "islamic-civil" => IslamicCivil
  }

  @data_path Path.join([__DIR__, "..", "..", "support", "data", "date_time_formatting.json"])

  defp conformance_cases do
    @data_path
    |> File.read!()
    |> :json.decode()
    |> Enum.filter(&Map.has_key?(&1, "semanticSkeleton"))
  end

  defp options(test_case) do
    []
    |> put_option(:length, test_case["semanticSkeletonLength"], &String.to_existing_atom/1)
    |> put_option(:zone_style, test_case["zoneStyle"], &String.to_existing_atom/1)
    |> put_option(:year_style, test_case["yearStyle"], fn "with_era" -> :with_era end)
    |> put_option(:hour_cycle, test_case["hourCycle"], &hour_cycle/1)
  end

  # The fixture's hour-cycle labels changed meaning mid-cycle. Up to CLDR 49
  # beta1 it wrote "H12" and "H23" for what TR35 §Hour Cycle Pattern
  # Variations now calls Clock12 and Clock24 — pick the 12- or 24-hour
  # skeleton and take the locale's pattern as it stands. Upstream commit
  # 3cf83276d5 renamed them "Clock12"/"Clock24", after which a literal "H12"
  # names the exact cycle that substitutes `h`. Which reading applies depends
  # on whether the fixture in hand predates the rename.
  defp hour_cycle(label) do
    renamed? = fixture_uses_clock_labels?()

    case {label, renamed?} do
      {"Clock12", _} -> :clock12
      {"Clock24", _} -> :clock24
      {"H12", false} -> :clock12
      {"H23", false} -> :clock24
      {"H11", _} -> :h11
      {"H12", true} -> :h12
      {"H23", true} -> :h23
      {"H24", _} -> :h24
    end
  end

  defp fixture_uses_clock_labels? do
    Enum.any?(conformance_cases(), &(&1["hourCycle"] in ["Clock12", "Clock24"]))
  end

  defp put_option(options, _key, nil, _cast), do: options
  defp put_option(options, key, value, cast), do: Keyword.put(options, key, cast.(value))

  defp calendar(name), do: Map.fetch!(@calendars, name)

  describe "CLDR conformance" do
    test "every semantic skeleton resolves to the classical skeleton CLDR names" do
      failures =
        Enum.reduce(conformance_cases(), [], fn test_case, failures ->
          skeleton = Skeleton.semantic(test_case["semanticSkeleton"], options(test_case))
          expected = test_case["classicalSkeleton"]

          case Skeleton.to_classical_skeleton(skeleton,
                 locale: test_case["locale"],
                 calendar: calendar(test_case["calendar"])
               ) do
            {:ok, resolved} when is_atom(resolved) ->
              if to_string(resolved) == expected do
                failures
              else
                [{test_case, expected, to_string(resolved)} | failures]
              end

            other ->
              [{test_case, expected, inspect(other)} | failures]
          end
        end)

      assert failures == [],
             Enum.map_join(Enum.take(failures, 10), "\n", fn {test_case, expected, got} ->
               "  #{test_case["semanticSkeleton"]}/#{test_case["semanticSkeletonLength"]} " <>
                 "#{test_case["calendar"]}: expected #{expected}, got #{got}"
             end)
    end

    test "the suite is actually running" do
      assert Enum.count(conformance_cases()) == 240
    end

    # The mapping test above checks only which classical skeleton a semantic
    # one resolves to, so it passes whatever the formatter then does with it.
    # These cases also carry the input and the string CLDR expects, and are
    # otherwise routed through their classical skeleton by the parser — so
    # without this, the semantic formatting path, hour cycle included, is
    # never compared with CLDR at all.
    #
    # CLDR's generator joins the date and time halves with the standard
    # pattern rather than TR35's default `atTime` one, as its skeleton suites
    # do, so the cases format with `style: :standard`.
    test "every Gregorian semantic skeleton formats its input as CLDR expects" do
      cases = gregorian_semantic_cases()

      failures =
        Enum.reduce(cases, [], fn test_case, failures ->
          skeleton = Skeleton.semantic(test_case.semantic_skeleton, parsed_options(test_case))

          case Localize.DateTime.to_string(test_case.input,
                 format: skeleton,
                 style: :standard,
                 locale: test_case.locale
               ) do
            {:ok, formatted} when formatted == test_case.expected -> failures
            other -> [{test_case, other} | failures]
          end
        end)

      assert cases != [], "no Gregorian semantic cases found — the fixture shape changed"

      assert failures == [],
             "#{length(failures)} of #{length(cases)} failed:\n" <>
               Enum.map_join(Enum.take(Enum.reverse(failures), 10), "\n", fn {c, got} ->
                 "  ##{c.index} #{c.semantic_skeleton}/#{c.semantic_skeleton_length} " <>
                   "#{c.locale} hc=#{inspect(Map.get(c, :hour_cycle))}: " <>
                   "expected #{inspect(c.expected)}, got #{inspect(got)}"
               end)
    end
  end

  defp gregorian_semantic_cases do
    Localize.DateTime.TestData.parse()
    |> Enum.filter(&(Map.has_key?(&1, :semantic_skeleton) and &1.calendar == :gregorian))
  end

  # The parser keeps these option values as strings, so the same casts apply
  # as for the raw fixture.
  defp parsed_options(test_case) do
    []
    |> put_option(
      :length,
      Map.get(test_case, :semantic_skeleton_length),
      &String.to_existing_atom/1
    )
    |> put_option(:zone_style, Map.get(test_case, :zone_style), &String.to_existing_atom/1)
    |> put_option(:year_style, Map.get(test_case, :year_style), fn "with_era" -> :with_era end)
    |> put_option(:hour_cycle, Map.get(test_case, :hour_cycle), &hour_cycle/1)
  end

  # TR35 §Hour Cycle Pattern Variations, checked where it matters. The CLDR
  # conformance cases above that carry an hour cycle are all `en`, whose
  # 12-hour pattern already uses `h`, so Clock12 and H12 render identically
  # there and those cases cannot tell the two apart.
  #
  # `ja` can: CLDR's `ja` availableFormats give `hms` as "aK:mm:ss" and `Hms`
  # as "H:mm:ss". Applying TR35's rule to those patterns at 00:30:45 — the
  # hour where h, K, H and k all differ — gives the expectations below
  # without consulting the library: Clock12/Clock24 take the pattern as it
  # stands, and H11/H12/H23/H24 substitute K/h/H/k into it.
  describe "hour cycle pattern variations" do
    @midnight ~U[2026-05-23 00:30:45Z]
    @am "午前"

    @expected [
      {:clock12, "#{@am}0:30:45"},
      {:clock24, "0:30:45"},
      {:h11, "#{@am}0:30:45"},
      {:h12, "#{@am}12:30:45"},
      {:h23, "0:30:45"},
      {:h24, "24:30:45"}
    ]

    test "Localize.Time applies each cycle as TR35 specifies" do
      for {cycle, expected} <- @expected do
        skeleton = Skeleton.semantic("T", hour_cycle: cycle)

        assert Localize.Time.to_string(@midnight, format: skeleton, locale: "ja") ==
                 {:ok, expected},
               "hour_cycle #{inspect(cycle)}"
      end
    end

    test "Localize.DateTime applies each cycle to the time half of a joined pattern" do
      for {cycle, expected} <- @expected do
        skeleton = Skeleton.semantic("YMDT", hour_cycle: cycle, length: :short)
        {:ok, formatted} = Localize.DateTime.to_string(@midnight, format: skeleton, locale: "ja")

        assert String.ends_with?(formatted, " " <> expected),
               "hour_cycle #{inspect(cycle)}: got #{inspect(formatted)}"
      end
    end

    test "to_parts carries the substituted hour" do
      skeleton = Skeleton.semantic("T", hour_cycle: :h12)
      {:ok, parts} = Localize.DateTime.to_parts(@midnight, format: skeleton, locale: "ja")

      assert Enum.map_join(parts, & &1.value) == "#{@am}12:30:45"
      assert %{type: :hour, value: "12"} in parts
    end

    test "only the exact cycles substitute; Clock12 keeps the locale's K" do
      clock = Skeleton.semantic("T", hour_cycle: :clock12)
      exact = Skeleton.semantic("T", hour_cycle: :h12)

      refute Localize.Time.to_string(@midnight, format: clock, locale: "ja") ==
               Localize.Time.to_string(@midnight, format: exact, locale: "ja")
    end

    test "a quoted literal hour letter is left alone" do
      assert Skeleton.apply_hour_cycle("h 'h' mm", Skeleton.semantic("T", hour_cycle: :h23)) ==
               "H 'h' mm"
    end
  end

  # TR35 §Alignment: column alignment is for dates and times set in a column,
  # and the most common behaviour is to render the fields it affects with at
  # least two digits — TR35's example is "01/01/2000" for "1/1/2000" in US
  # English. ICU4X, the reference implementation, widens a one-letter month,
  # day, week or hour field of the matched pattern to two letters, and its own
  # example is `en-US` short "1/1/25" becoming "01/01/25".
  #
  # The other expectations apply that rule by hand to CLDR 49's patterns: `en`
  # short "M/d/yy", medium "MMM d, y", full "EEEE, MMMM d, y", `Md` "M/d",
  # `hm` "h:mm a" and `hms` "h:mm:ss a", joined by "{1}, {0}" or, at full
  # length, "{1} 'at' {0}"; `es` short "d/M/yy"; `de` medium "dd.MM.y"; `fi`
  # `Hms` "H.mm.ss"; `ja` `hms` "aK:mm:ss"; `ar` short "d/M/y" with a
  # right-to-left mark after the day and the month; `he` short "d.M.y". ICU4C
  # 78.3 formats the padded `ar` and `he` patterns as below, code point for
  # code point: a decimal numbering system pads with its own zero, and Hebrew
  # numerals have no zero to pad with.
  describe "column alignment" do
    @one_digit ~N[2025-01-05 09:05:07]

    test "TR35's and ICU4X's examples" do
      inline = Skeleton.semantic("YMD", length: :short)

      assert Localize.Date.to_string(~D[2025-01-01], format: inline, locale: :en) ==
               {:ok, "1/1/25"}

      assert column(Localize.Date, ~D[2025-01-01], "YMD", length: :short, locale: :en) ==
               {:ok, "01/01/25"}

      assert column(Localize.Date, ~D[2000-01-01], "YMD",
               length: :short,
               year_style: :full,
               locale: :en
             ) == {:ok, "01/01/2000"}
    end

    test "a one-letter month, day or hour is widened; a spelled-out month and the year are not" do
      assert column(Localize.Date, ~D[2025-01-05], "YMD", length: :short, locale: :es) ==
               {:ok, "05/01/25"}

      assert column(Localize.Date, ~D[2025-01-05], "YMD", locale: :en) ==
               {:ok, "Jan 05, 2025"}

      assert column(Localize.Date, ~D[2025-01-05], "YMD", locale: :de) == {:ok, "05.01.2025"}

      assert column(Localize.Time, ~T[09:05:07], "T", locale: :en, prefer: :ascii) ==
               {:ok, "09:05:07 AM"}

      assert column(Localize.Time, ~T[09:05:07], "T", locale: :fi) == {:ok, "09.05.07"}

      assert column(Localize.Time, ~T[09:05:07], "T", hour_cycle: :clock12, locale: :ja) ==
               {:ok, "午前09:05:07"}

      assert column(Localize.Time, ~T[00:30:45], "T", hour_cycle: :h11, locale: :ja) ==
               {:ok, "午前00:30:45"}
    end

    test "every formatter path pads" do
      # A standard date format on its own and joined to a time by its wrapper.
      assert column(Localize.DateTime, @one_digit, "YMD", length: :short, locale: :en) ==
               {:ok, "01/05/25"}

      assert column(Localize.DateTime, @one_digit, "YMDT",
               length: :short,
               locale: :en,
               prefer: :ascii
             ) == {:ok, "01/05/25, 09:05:07 AM"}

      assert column(Localize.DateTime, @one_digit, "YMDET",
               length: :long,
               locale: :en,
               prefer: :ascii
             ) == {:ok, "Sunday, January 05, 2025 at 09:05:07 AM"}

      # A matched skeleton, and partial dates, times and date-times.
      assert column(Localize.DateTime, @one_digit, "MDT",
               length: :short,
               locale: :en,
               prefer: :ascii
             ) == {:ok, "01/05, 09:05:07 AM"}

      assert column(Localize.Date, %{month: 1, day: 5}, "MD", length: :short, locale: :en) ==
               {:ok, "01/05"}

      assert column(Localize.Time, %{hour: 9, minute: 5}, "T",
               time_precision: :minute,
               locale: :en,
               prefer: :ascii
             ) == {:ok, "09:05 AM"}

      assert column(Localize.DateTime, %{month: 1, day: 5, hour: 9, minute: 5}, "MDT",
               length: :short,
               time_precision: :minute,
               locale: :en,
               prefer: :ascii
             ) == {:ok, "01/05, 09:05 AM"}

      # Semantic date and time formats given separately.
      date = Skeleton.semantic("YMD", length: :short, alignment: :column)
      time = Skeleton.semantic("T", alignment: :column)

      assert Localize.DateTime.to_string(@one_digit,
               date_format: date,
               time_format: time,
               locale: :en,
               prefer: :ascii
             ) == {:ok, "01/05/25, 09:05:07 AM"}
    end

    test "to_parts carries the padded values" do
      skeleton = Skeleton.semantic("YMDT", length: :short, alignment: :column)
      {:ok, parts} = Localize.DateTime.to_parts(@one_digit, format: skeleton, locale: :en)

      assert %{type: :month, value: "01"} in parts
      assert %{type: :day, value: "05"} in parts
      assert %{type: :hour, value: "09"} in parts
    end

    test "a decimal numbering system pads with its own zero; Hebrew numerals are not padded" do
      rlm = <<0x200F::utf8>>

      assert column(Localize.Date, ~D[2025-01-05], "YMD", length: :short, locale: "ar-u-nu-arab") ==
               {:ok, "٠٥#{rlm}/٠١#{rlm}/٢٠٢٥"}

      assert column(Localize.Date, ~D[2025-01-05], "YMD",
               length: :short,
               locale: :he,
               number_system: :hebr
             ) == {:ok, "ה׳.א׳.ב׳כ״ה"}
    end

    test "a quoted literal letter is left alone" do
      skeleton = Skeleton.semantic("YMDT", alignment: :column)

      assert Skeleton.apply_pattern_variations("d 'de' MMMM 'de' y", skeleton) ==
               "dd 'de' MMMM 'de' y"

      assert Skeleton.apply_pattern_variations("h 'o''clock' a", skeleton) == "hh 'o''clock' a"
    end

    test "the classical skeleton is the same" do
      for alignment <- [:inline, :column] do
        skeleton = Skeleton.semantic("YMD", length: :short, alignment: alignment)
        assert Skeleton.to_classical_skeleton(skeleton, locale: :en) == {:ok, :yyMd}
      end
    end

    @sweep_locales ~w(am ar bal be bn cy da de en en-AU es fa fi fr he hi hu it ja ko ky mr my pt ru th uk zh zh-Hant)a

    @instants [~U[2025-01-05 09:05:07Z], ~U[2025-11-15 22:45:56Z]]
    @dates [~D[2025-01-05], ~D[2025-11-15]]
    @times [~T[09:05:07], ~T[22:45:56]]

    # Each field set with the values that take it down every path: whole and
    # partial dates and times through `Localize.Date` and `Localize.Time`, and
    # instants through `Localize.DateTime`'s standard formats, wrappers,
    # matched skeletons and glue.
    @sweep [
      {"D", [], @dates ++ [%{month: 1, day: 5}]},
      {"DE", [], @dates},
      {"MD", [], @dates ++ [%{month: 1, day: 5}]},
      {"MDE", [], @dates},
      {"YMD", [], @dates ++ @instants},
      {"YMDE", [], @dates ++ @instants},
      {"Y", [], @dates ++ [%{year: 2025, month: 1}]},
      {"M", [], @dates ++ [%{year: 2025, month: 1}, %{month: 1, day: 5}]},
      {"YM", [], @dates ++ [%{year: 2025, month: 1}]},
      {"T", [], @times ++ @instants},
      {"T", [time_precision: :minute], [%{hour: 9, minute: 5}, %{hour: 22, minute: 45}]},
      {"DT", [], @instants},
      {"ET", [], @instants},
      {"MDT", [], @instants},
      {"MDT", [time_precision: :minute], [%{month: 1, day: 5, hour: 9, minute: 5}]},
      {"YMDT", [], @instants},
      {"YMDET", [], @instants},
      {"TZ", [], @instants},
      {"MDZ", [], @instants},
      {"YMDTZ", [], @instants},
      {"YMDETZ", [], @instants}
    ]

    # Column alignment changes nothing but the width of a one-digit month, day
    # or hour, whichever path the skeleton takes, so a value's column parts are
    # its inline parts with each one-digit month, day and hour zero-padded, and
    # a value a locale cannot format fails the same way under either. Latin
    # digits keep the comparison to ASCII.
    test "every preloaded locale pads exactly its one-digit months, days and hours" do
      results =
        for locale <- @sweep_locales,
            {code, options} <-
              Enum.flat_map(@sweep, fn {code, options, values} ->
                for length <- [:short, :medium, :long],
                    value <- values,
                    do: {code, [{:length, length}, {:value, value} | options]}
              end) do
          {value, options} = Keyword.pop!(options, :value)
          inline = aligned_parts(value, code, options, :inline, locale)
          column = aligned_parts(value, code, options, :column, locale)
          {{locale, code, options, value}, inline, column}
        end

      assert_padded(results)
    end

    test "every hour cycle pads a one-digit hour" do
      results =
        for locale <- @sweep_locales,
            hour_cycle <- [:auto, :clock12, :clock24, :h11, :h12, :h23, :h24],
            value <- [~T[00:30:45], ~U[2025-01-05 00:30:45Z]] ++ @times ++ @instants do
          options = [hour_cycle: hour_cycle]
          inline = aligned_parts(value, "T", options, :inline, locale)
          column = aligned_parts(value, "T", options, :column, locale)
          {{locale, hour_cycle, value}, inline, column}
        end

      assert_padded(results)
    end
  end

  # Formats `value` with `module` under a column-aligned semantic skeleton,
  # splitting the skeleton's options from the formatter's.
  defp column(module, value, code, options) do
    {skeleton_options, options} =
      Keyword.split(options, [:length, :year_style, :hour_cycle, :time_precision])

    skeleton = Skeleton.semantic(code, [alignment: :column] ++ skeleton_options)
    module.to_string(value, [format: skeleton] ++ options)
  end

  defp aligned_parts(value, code, options, alignment, locale) do
    skeleton = Skeleton.semantic(code, [alignment: alignment] ++ options)
    Localize.DateTime.to_parts(value, format: skeleton, locale: locale, number_system: :latn)
  end

  defp assert_padded(results) do
    failures =
      for {key, inline, column} <- results, column != pad_one_digit_fields(inline) do
        {key, inline, column}
      end

    padded = Enum.count(results, fn {_key, inline, column} -> inline != column end)

    assert failures == [], inspect(Enum.take(failures, 5), pretty: true, limit: :infinity)
    assert padded > 0
  end

  # A one-digit month, day or hour, zero-padded to two.
  defp pad_one_digit_fields({:ok, parts}) do
    {:ok,
     Enum.map(parts, fn
       %{type: type, value: <<digit>>} = part
       when type in [:month, :day, :hour] and digit in ?0..?9 ->
         %{part | value: <<?0, digit>>}

       part ->
         part
     end)}
  end

  defp pad_one_digit_fields({:error, _exception} = error), do: error

  describe "new/2" do
    test "parses a field code" do
      assert {:ok, %Skeleton{fields: [:year, :month, :day, :weekday]}} = Skeleton.new("YMDE")
    end

    test "accepts a field list" do
      assert {:ok, %Skeleton{fields: [:time, :zone]}} = Skeleton.new([:time, :zone])
    end

    test "defaults are medium length, automatic year and zone form, specific zone, seconds, inline" do
      assert {:ok,
              %Skeleton{
                length: :medium,
                year_style: :auto,
                zone_style: :specific,
                zone_length: :auto,
                time_precision: :second,
                alignment: :inline
              }} = Skeleton.new("YMD")
    end

    test "an unknown field code is returned, not raised" do
      assert {:error, %Localize.InvalidValueError{value: "Q"}} = Skeleton.new("YMDQ")
    end

    test "an unknown option value is returned, not raised" do
      assert {:error, %Localize.InvalidValueError{}} = Skeleton.new("YMD", length: :enormous)
      assert {:error, %Localize.InvalidValueError{}} = Skeleton.new("YMDZ", zone_style: :bogus)
      assert {:error, %Localize.InvalidValueError{}} = Skeleton.new("TZ", zone_length: :medium)

      # TR35 names the alignments inline and column.
      assert {:error, %Localize.InvalidValueError{value: :auto}} =
               Skeleton.new("YMD", alignment: :auto)

      for precision <- [
            :fortnight,
            {:fractional_second, 0},
            {:fractional_second, 10},
            {:fractional_second, 1.5}
          ] do
        assert {:error, %Localize.InvalidValueError{value: ^precision}} =
                 Skeleton.new("T", time_precision: precision)
      end
    end

    test "semantic/2 raises where new/2 returns" do
      assert_raise Localize.InvalidValueError, fn -> Skeleton.semantic("YMDQ") end
    end
  end

  # TR35 §Semantic Skeleton Conformance: a field set TR35 does not describe,
  # and an option given for a set holding none of its Required Fields, must
  # be errors. The sets are TR35's tables as it prints them — its date,
  # calendar period, time and zone field sets, then the composites: a date
  # with a time, a zone or both, and a time with a zone. A calendar period
  # joins nothing, since TR35 rules out pairing one with a time.
  describe "TR35 field sets" do
    @tr35_dates ~w(D E DE MD MDE YMD YMDE)

    @tr35_field_sets @tr35_dates ++
                       ~w(M Y YM T Z TZ) ++
                       for(date <- @tr35_dates, joined <- ~w(T Z TZ), do: date <> joined)

    # Each option with a value to give it and the fields of its Required
    # Fields line: alignment "Year, Month, Day, or Hour", year style "Year",
    # hour cycle "Hour", time precision "Time" and zone style "Zone".
    # `:zone_length` is Localize's own form of the zone.
    @required_fields [
      alignment: {:column, ~w(Y M D T)},
      year_style: {:full, ~w(Y)},
      hour_cycle: {:h23, ~w(T)},
      time_precision: {:minute, ~w(T)},
      zone_style: {:generic, ~w(Z)},
      zone_length: {:long, ~w(Z)}
    ]

    test "every TR35 field set builds, whatever the order of its codes" do
      for code <- @tr35_field_sets do
        assert {:ok, skeleton} = Skeleton.new(code)
        assert Skeleton.new(String.reverse(code)) == {:ok, skeleton}, code
      end

      assert {:ok, %Skeleton{fields: [:year, :month, :day]}} = Skeleton.new([:day, :month, :year])
    end

    test "every other set of the six fields is an error" do
      every_set = for subset <- subsets(~c"YMDETZ"), subset != [], do: List.to_string(subset)
      others = every_set -- @tr35_field_sets

      assert {length(every_set), length(@tr35_field_sets), length(others)} == {63, 34, 29}

      for code <- others do
        assert {:error, %Localize.InvalidValueError{value: ^code, expected: :field_set}} =
                 Skeleton.new(code)
      end

      assert {:error, %Localize.InvalidValueError{value: [:year, :day]}} =
               Skeleton.new([:year, :day])
    end

    test "a field given twice, or no field, is an error" do
      for fields <- ["YMDD", "TT", "", [:year, :year], []] do
        assert {:error, %Localize.InvalidValueError{value: ^fields, expected: :field_set}} =
                 Skeleton.new(fields)
      end
    end

    test "an option needs one of the fields TR35 requires for it" do
      for {option, {value, letters}} <- @required_fields, code <- @tr35_field_sets do
        result = Skeleton.new(code, [{option, value}])

        if String.contains?(code, letters) do
          assert {:ok, %Skeleton{}} = result, "#{option} on #{code}"
        else
          assert {:error, %Localize.InvalidValueError{value: ^code}} = result,
                 "#{option} on #{code}"
        end
      end
    end

    test "an option given with its default value is still given" do
      assert {:error, %Localize.InvalidValueError{}} = Skeleton.new("MD", year_style: :auto)
      assert {:error, %Localize.InvalidValueError{}} = Skeleton.new("E", alignment: :inline)
    end

    test "length suits every field set" do
      for code <- @tr35_field_sets, length <- [:short, :medium, :long] do
        assert {:ok, %Skeleton{length: ^length}} = Skeleton.new(code, length: length)
      end
    end

    @hand_built [
      %Skeleton{fields: [:year, :day]},
      %Skeleton{fields: [:year, :month, :time]},
      %Skeleton{fields: [:year, :year, :month, :day]},
      %Skeleton{fields: []},
      %Skeleton{fields: "YMD"},
      %Skeleton{fields: [:quarter]},
      %Skeleton{fields: [:month], length: :long_ish},
      %Skeleton{fields: [:year, :month, :day], year_style: :short},
      %Skeleton{fields: [:time], time_precision: :millisecond},
      %Skeleton{fields: [:time], hour_cycle: :h25},
      %Skeleton{fields: [:time, :zone], zone_style: :daylight},
      %Skeleton{fields: [:time, :zone], zone_length: :medium},
      %Skeleton{fields: [:year, :month, :day], alignment: :right}
    ]

    test "a struct built by hand is checked when it formats, and never raises" do
      values = [
        {Localize.Date, ~D[2025-01-05]},
        {Localize.Time, ~T[09:05:07]},
        {Localize.DateTime, ~U[2025-01-05 09:05:07Z]}
      ]

      for skeleton <- @hand_built,
          {module, value} <- values,
          function <- [:to_string, :to_parts] do
        assert {:error, %Localize.InvalidValueError{}} =
                 apply(module, function, [value, [format: skeleton, locale: :en]]),
               "#{inspect(module)}.#{function}/2 with #{inspect(skeleton)}"
      end

      for skeleton <- @hand_built do
        assert {:error, %Localize.InvalidValueError{}} =
                 Skeleton.to_classical_skeleton(skeleton, locale: :en)
      end
    end

    test "a struct built by hand in another order formats as new/2's does" do
      hand_built = %Skeleton{fields: [:zone, :time, :day, :month, :year], length: :short}
      built = Skeleton.semantic("YMDTZ", length: :short)
      instant = ~U[2025-01-05 09:05:07Z]

      assert Localize.DateTime.to_string(instant, format: hand_built, locale: :en) ==
               Localize.DateTime.to_string(instant, format: built, locale: :en)
    end
  end

  # Every subset of `list`, each in the list's own order.
  defp subsets([]), do: [[]]

  defp subsets([head | tail]) do
    rest = subsets(tail)
    Enum.map(rest, &[head | &1]) ++ rest
  end

  # The expected skeletons are TR35's mapping applied by hand. The year, month
  # and day widths are each locale's `dateSkeletons` in the CLDR JSON's
  # `ca-*.json`: `en` Gregorian short `yyMd`, medium `yMMMd`, long `yMMMMd`;
  # `de` medium `yMMdd`, short `yyMMdd`; `ja` Japanese long `GyMMMd`; `en`
  # Japanese long `GyMMMMd`, short `GGGGGyMd`; `en` Hebrew short `yMMMd`;
  # `en` Chinese medium `rMMMd`. The weekday, time and zone come from TR35's
  # table and its time precision variations.
  describe "to_classical_skeleton/2" do
    test "the year, month and day take the locale's widths" do
      assert classical("YMD", locale: :en) == {:ok, :yMMMd}
      assert classical("YMD", length: :long, locale: :en) == {:ok, :yMMMMd}
      assert classical("YMD", locale: :de) == {:ok, :yMMdd}
      assert classical("YMD", length: :short, locale: :de) == {:ok, :yyMMdd}
      assert classical("MD", locale: :de) == {:ok, :MMdd}
      assert classical("YMD", locale: :zh, calendar: Chinese) == {:ok, :rMMMd}
    end

    test "a calendar's date formats bring its era and month widths" do
      assert classical("YMDE", length: :long, locale: :ja, calendar: Japanese) ==
               {:ok, :GyMMMdEEEE}

      assert classical("YMDE", length: :long, locale: :en, calendar: Japanese) ==
               {:ok, :GyMMMMdEEEE}

      assert classical("YMD", length: :short, locale: :en, calendar: Japanese) ==
               {:ok, :GGGGGyMd}

      # TR35's own example: English has no numeric Hebrew month.
      assert classical("YMD", length: :short, locale: :en, calendar: Hebrew) == {:ok, :yMMMd}
    end

    test "the year style adjusts the locale's year" do
      assert classical("YMDE", length: :short) == {:ok, :yyMdEEE}
      assert classical("YMDE", length: :short, year_style: :full) == {:ok, :yMdEEE}
      assert classical("YMDE", length: :short, year_style: :with_era) == {:ok, :GyMdEEE}

      assert classical("YMD", length: :short, year_style: :with_era, calendar: Japanese) ==
               {:ok, :GGGGGyMd}
    end

    test "a month or weekday on its own takes the standalone form" do
      assert classical("M", length: :long) == {:ok, :LLLL}
      assert classical("M") == {:ok, :LLL}
      assert classical("M", length: :short) == {:ok, :L}
      assert classical("E", length: :long) == {:ok, :EEEE}
      assert classical("E") == {:ok, :EEE}
      assert classical("E", length: :short) == {:ok, :EEEEE}
      assert classical("DE", length: :short) == {:ok, :dEEE}
    end

    test "the time precision sets the time fields" do
      assert classical("T") == {:ok, :jms}
      assert classical("T", time_precision: :hour) == {:ok, :j}
      assert classical("T", time_precision: :minute) == {:ok, :jm}
      assert classical("T", time_precision: {:fractional_second, 3}) == {:ok, :jmsSSS}
      assert classical("T", time_precision: :hour, hour_cycle: :clock24) == {:ok, :H}
      assert classical("T", time_precision: :minute, hour_cycle: :h11) == {:ok, :hm}
      assert classical("YMDT", time_precision: :minute) == {:ok, :yMMMdjm}
    end

    test "an optional minute is shown unless the value's minute is zero" do
      skeleton = Skeleton.semantic("T", time_precision: :minute_optional)

      assert Skeleton.to_classical_skeleton(skeleton, value: ~T[15:00:00]) == {:ok, :j}
      assert Skeleton.to_classical_skeleton(skeleton, value: ~T[15:04:00]) == {:ok, :jm}
      assert Skeleton.to_classical_skeleton(skeleton) == {:ok, :jm}
    end

    test "a zone alone takes the long form except at short length, a trailing zone the short" do
      assert classical("Z") == {:ok, :zzzz}
      assert classical("Z", length: :long) == {:ok, :zzzz}
      assert classical("Z", length: :short) == {:ok, :z}
      assert classical("Z", zone_style: :generic) == {:ok, :vvvv}
      assert classical("Z", length: :short, zone_style: :generic) == {:ok, :v}
      assert classical("Z", length: :long, zone_style: :offset) == {:ok, :O}
      assert classical("MDTZ", length: :long) == {:ok, :MMMMdjmsz}
    end

    test "the zone length chooses the zone's form" do
      assert classical("TZ", zone_length: :long) == {:ok, :jmszzzz}
      assert classical("Z", zone_length: :short) == {:ok, :z}
      assert classical("TZ", zone_style: :generic, zone_length: :long) == {:ok, :jmsvvvv}
      assert classical("TZ", zone_style: :offset) == {:ok, :jmsO}
      assert classical("TZ", zone_style: :offset, zone_length: :long) == {:ok, :jmsOOOO}
      assert classical("TZ", zone_style: :location, zone_length: :short) == {:ok, :jmsVVVV}
    end

    test "a calendar is a module, never a CLDR calendar type" do
      skeleton = Skeleton.semantic("YMD")

      for calendar <- [:japanese, "japanese", :gregorian, nil, 42] do
        assert {:error, %Localize.UnknownCalendarError{}} =
                 Skeleton.to_classical_skeleton(skeleton, calendar: calendar)
      end
    end

    test "invalid input is returned, not raised" do
      skeleton = Skeleton.semantic("YMD")

      assert {:error, %{__exception__: true}} =
               Skeleton.to_classical_skeleton(skeleton, locale: "xx-!!-bogus")

      assert {:error, %Localize.InvalidValueError{}} =
               Skeleton.to_classical_skeleton(skeleton, :gregorian)

      assert {:error, %Localize.InvalidValueError{}} =
               Skeleton.to_classical_skeleton(%Skeleton{fields: []}, locale: :en)
    end
  end

  defp classical(code, options \\ []) do
    {skeleton_options, options} =
      Keyword.split(options, [
        :length,
        :year_style,
        :zone_style,
        :zone_length,
        :hour_cycle,
        :time_precision
      ])

    code
    |> Skeleton.semantic(skeleton_options)
    |> Skeleton.to_classical_skeleton(Keyword.put_new(options, :locale, :en))
  end

  # TR35 counts the standard date formats among the patterns a skeleton is
  # matched against, and a semantic year, month and day resolves to exactly
  # the skeleton of the standard format at its length. The expected strings
  # are CLDR 49's standard patterns: be medium "d MMM y 'г'." (whose
  # own skeleton, `yMMd`, says numeric), da full "EEEE 'den' d. MMMM y", de
  # long "d. MMMM y" joined by "{1} 'um' {0}".
  describe "a date that resolves to a standard format" do
    test "formats with that format" do
      date = ~D[2006-01-02]

      assert Localize.Date.to_string(date, format: Skeleton.semantic("YMD"), locale: :be) ==
               {:ok, "2 сту 2006 г."}

      assert Localize.Date.to_string(date,
               format: Skeleton.semantic("YMDE", length: :long),
               locale: :da
             ) == {:ok, "mandag den 2. januar 2006"}

      datetime = ~N[2006-01-02 15:04:06]
      skeleton = Skeleton.semantic("YMDT", length: :long, time_precision: :minute)

      assert Localize.DateTime.to_string(datetime, format: skeleton, locale: :de) ==
               {:ok, "2. Januar 2006 um 15:04"}
    end

    test "only a year, month and day at the skeleton's length, or a weekday at long" do
      assert Skeleton.standard_date_format(Skeleton.semantic("YMD"), :en, :gregorian) ==
               {:ok, :medium, nil}

      assert Skeleton.standard_date_format(
               Skeleton.semantic("YMDE", length: :long),
               :en,
               :gregorian
             ) ==
               {:ok, :full, nil}

      assert {:ok, :short, %Skeleton{fields: [:time, :zone]}} =
               Skeleton.standard_date_format(
                 Skeleton.semantic("YMDTZ", length: :short),
                 :en,
                 :gregorian
               )

      for code <- ["YMDE", "MD", "YM", "E", "T"] do
        assert Skeleton.standard_date_format(Skeleton.semantic(code), :en, :gregorian) == :error
      end

      with_era = Skeleton.semantic("YMD", year_style: :with_era)
      assert Skeleton.standard_date_format(with_era, :en, :gregorian) == :error

      # en `GyMMMd` "MMM d, y G".
      assert Localize.Date.to_string(~D[2006-01-02], format: with_era, locale: :en) ==
               {:ok, "Jan 2, 2006 AD"}
    end

    test "every length of every preloaded locale" do
      date = ~D[2006-01-02]

      failures =
        for locale <-
              ~w(am ar bal be bn cy da de en en-AU es fa fi fr he hi hu it ja ko ky mr my pt ru th uk zh zh-Hant)a,
            length <- [:short, :medium, :long],
            semantic =
              Localize.Date.to_string(date,
                format: Skeleton.semantic("YMD", length: length),
                locale: locale
              ),
            standard = Localize.Date.to_string(date, format: length, locale: locale),
            semantic != standard do
          {locale, length, semantic, standard}
        end

      assert failures == []
    end
  end

  describe "requested field widths survive the match" do
    # TR35 adjusts the matched format's widths to those requested. `en` ships
    # an `MMM` available format and no `MMMM`, so this is the case that used
    # to render "Jul" for a request that named the full month.
    test "a full month is not narrowed to the matched format's abbreviation" do
      for format <- [:MMMM, :LLLL] do
        assert {:ok, "July"} =
                 Localize.Date.to_string(~D[2024-07-01], format: format, locale: :en)
      end
    end

    test "the same holds through Localize.DateTime" do
      {:ok, datetime, _offset} = DateTime.from_iso8601("2024-07-01T08:50:07Z")

      assert {:ok, "July"} = Localize.DateTime.to_string(datetime, format: :MMMM, locale: :en)
    end

    test "a narrower request is honoured too" do
      assert {:ok, "Jul"} = Localize.Date.to_string(~D[2024-07-01], format: :MMM, locale: :en)
    end
  end

  describe "the :format option accepts the struct" do
    test "for a date" do
      assert {:ok, "Mon, Jul 1, 2024"} =
               Localize.Date.to_string(~D[2024-07-01],
                 format: Skeleton.semantic("YMDE"),
                 locale: :en
               )
    end

    test "for a time" do
      assert {:ok, formatted} =
               Localize.Time.to_string(~T[08:50:07],
                 format: Skeleton.semantic("T", hour_cycle: :h23),
                 locale: :en
               )

      assert formatted =~ "50:07"
    end
  end
end
