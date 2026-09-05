defmodule Localize.DateTime.SemanticSkeletonTest do
  @moduledoc """
  Conformance for TR35 semantic skeletons.

  CLDR ships no semantic-skeleton data — `semanticSkeleton` appears only in
  `common/testData/datetime/datetime.json`, which states the mapping from a
  semantic skeleton to the classical skeleton it resolves to. That mapping is
  what this suite checks, across the 240 cases the file carries for `en`,
  `ar-SA`, `ja-JP` and `th-TH` over the Gregorian, Buddhist, Japanese and
  Islamic civil calendars.
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
    |> put_option(:hour_cycle, test_case["hourCycle"], fn
      "H12" -> :h12
      "H23" -> :h23
    end)
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
