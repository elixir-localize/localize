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

  defp calendar(name) do
    name |> String.replace("-", "_") |> Localize.Utils.Helpers.existing_atom() || :gregorian
  end

  describe "CLDR conformance" do
    test "every semantic skeleton resolves to the classical skeleton CLDR names" do
      failures =
        Enum.reduce(conformance_cases(), [], fn test_case, failures ->
          skeleton = Skeleton.semantic(test_case["semanticSkeleton"], options(test_case))
          expected = test_case["classicalSkeleton"]

          case Skeleton.to_classical_skeleton(skeleton, calendar(test_case["calendar"])) do
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
      assert length(conformance_cases()) == 240
    end

    # The mapping test above checks only which classical skeleton a semantic
    # one resolves to, so it passes whatever the formatter then does with it.
    # These cases also carry the input and the string CLDR expects, and are
    # otherwise routed through their classical skeleton by the parser — so
    # without this, the semantic formatting path, hour cycle included, is
    # never compared with CLDR at all.
    test "every Gregorian semantic skeleton formats its input as CLDR expects" do
      cases = gregorian_semantic_cases()

      failures =
        Enum.reduce(cases, [], fn test_case, failures ->
          skeleton = Skeleton.semantic(test_case.semantic_skeleton, parsed_options(test_case))

          case Localize.DateTime.to_string(test_case.input,
                 format: skeleton,
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

  describe "new/2" do
    test "parses a field code" do
      assert {:ok, %Skeleton{fields: [:year, :month, :day, :weekday]}} = Skeleton.new("YMDE")
    end

    test "accepts a field list" do
      assert {:ok, %Skeleton{fields: [:time, :zone]}} = Skeleton.new([:time, :zone])
    end

    test "defaults are medium length, automatic year, specific zone" do
      assert {:ok, %Skeleton{length: :medium, year_style: :auto, zone_style: :specific}} =
               Skeleton.new("YMD")
    end

    test "an unknown field code is returned, not raised" do
      assert {:error, %Localize.InvalidValueError{value: "Q"}} = Skeleton.new("YMDQ")
    end

    test "an unknown option value is returned, not raised" do
      assert {:error, %Localize.InvalidValueError{}} = Skeleton.new("YMD", length: :enormous)
      assert {:error, %Localize.InvalidValueError{}} = Skeleton.new("YMDZ", zone_style: :bogus)
    end

    test "semantic/2 raises where new/2 returns" do
      assert_raise Localize.InvalidValueError, fn -> Skeleton.semantic("YMDQ") end
    end
  end

  describe "to_classical_skeleton/2" do
    test "a two-digit year appears only where no era does" do
      assert {:ok, :yyMdEEE} =
               Skeleton.to_classical_skeleton(
                 Skeleton.semantic("YMDE", length: :short),
                 :gregorian
               )

      assert {:ok, :GyMdEEE} =
               Skeleton.to_classical_skeleton(
                 Skeleton.semantic("YMDE", length: :short, year_style: :with_era),
                 :gregorian
               )
    end

    test "calendars whose year count restarts always carry an era" do
      assert {:ok, :GGGGGyMdEEE} =
               Skeleton.to_classical_skeleton(
                 Skeleton.semantic("YMDE", length: :short),
                 :japanese
               )

      assert {:ok, :GyMMMdEEEE} =
               Skeleton.to_classical_skeleton(Skeleton.semantic("YMDE", length: :long), :japanese)
    end

    test "a zone alone takes the long form, a trailing zone the short" do
      assert {:ok, :zzzz} = Skeleton.to_classical_skeleton(Skeleton.semantic("Z"), :gregorian)

      assert {:ok, :MMMMdjmsz} =
               Skeleton.to_classical_skeleton(
                 Skeleton.semantic("MDTZ", length: :long),
                 :gregorian
               )
    end

    test "a skeleton naming no fields is an error" do
      assert {:error, %Localize.InvalidValueError{}} =
               Skeleton.to_classical_skeleton(%Skeleton{fields: []}, :gregorian)
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
