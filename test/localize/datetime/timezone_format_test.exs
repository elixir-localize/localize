defmodule Localize.DateTime.TimezoneFormatTest do
  use ExUnit.Case, async: true

  alias Localize.DateTime.Timezone

  @new_york_standard %{time_zone: "America/New_York", utc_offset: -18_000, std_offset: 0}
  @new_york_daylight %{time_zone: "America/New_York", utc_offset: -18_000, std_offset: 3600}
  @paris %{time_zone: "Europe/Paris", utc_offset: 3600, std_offset: 0}

  describe "timezone data lookups" do
    test "timezones_for_territory/1 returns zones for a known territory" do
      assert {:ok, zones} = Timezone.timezones_for_territory(:AU)
      assert Enum.any?(zones, &(&1.short_zone == "ausyd"))
    end

    test "timezones_for_territory/1 returns an error for an unknown territory" do
      assert {:error, %Localize.UnknownTerritoryError{territory: :XX}} =
               Timezone.timezones_for_territory(:XX)
    end

    test "timezone_count_for_territory/1 counts zones" do
      assert {:ok, count} = Timezone.timezone_count_for_territory(:US)
      assert count > 0
    end

    test "timezone_count_for_territory/1 propagates unknown-territory errors" do
      assert {:error, %Localize.UnknownTerritoryError{territory: :ZZ}} =
               Timezone.timezone_count_for_territory(:ZZ)
    end

    test "get_short_zone/2 returns the default for unknown codes" do
      assert Timezone.get_short_zone("nope") == nil
      assert Timezone.get_short_zone("nope", :missing) == :missing
      assert %{territory: :AU} = Timezone.get_short_zone("ausyd")
    end

    test "fetch_short_zone/1 and validate_short_zone/1 error on unknown codes" do
      assert {:error, %Localize.UnknownTimezoneError{timezone: "nope"}} =
               Timezone.fetch_short_zone("nope")

      assert {:ok, "Australia/Sydney"} = Timezone.validate_short_zone("ausyd")

      assert {:error, %Localize.UnknownTimezoneError{timezone: "nope"}} =
               Timezone.validate_short_zone("nope")
    end

    test "territories_by_timezone/0 maps IANA names to territories" do
      territories = Timezone.territories_by_timezone()
      assert territories["Australia/Sydney"] == :AU
      assert territories["America/New_York"] == :US
    end
  end

  describe "non_location_format/3" do
    test "specific type selects standard or daylight from std_offset" do
      assert {:ok, "Eastern Standard Time"} =
               Timezone.non_location_format(@new_york_standard, :en)

      assert {:ok, "Eastern Daylight Time"} =
               Timezone.non_location_format(@new_york_daylight, :en)
    end

    test "explicit :standard and :daylight types override std_offset" do
      assert {:ok, "Central European Standard Time"} =
               Timezone.non_location_format(@paris, :en, type: :standard)

      assert {:ok, "Central European Summer Time"} =
               Timezone.non_location_format(@paris, :en, type: :daylight)
    end

    test ":generic type ignores daylight saving" do
      assert {:ok, "Eastern Time"} =
               Timezone.non_location_format(@new_york_standard, :en, type: :generic)

      assert {:ok, "Eastern Time"} =
               Timezone.non_location_format(@new_york_daylight, :en, type: :generic)
    end

    test "short format returns the abbreviation" do
      assert {:ok, "EST"} =
               Timezone.non_location_format(@new_york_standard, :en, format: :short)

      assert {:ok, "EDT"} =
               Timezone.non_location_format(@new_york_daylight, :en, format: :short)
    end

    test "unknown zone falls back to the GMT format" do
      unknown_zone = %{time_zone: "Mars/Olympus", utc_offset: 7200, std_offset: 0}

      assert {:ok, "GMT+02:00"} = Timezone.non_location_format(unknown_zone, :en)
    end

    test "localized names come from the requested locale" do
      assert {:ok, name} = Timezone.non_location_format(@new_york_standard, :fr)
      assert name =~ "Est"
    end
  end

  describe "gmt_format/3" do
    test "zero offset renders the locale's GMT-zero pattern" do
      assert {:ok, "GMT"} = Timezone.gmt_format(%{utc_offset: 0, std_offset: 0}, :en)

      assert {:ok, "GMT"} =
               Timezone.gmt_format(%{utc_offset: 0, std_offset: 0}, :en, format: :short)
    end

    test "zero_format: :offset forces the numeric pattern at zero" do
      assert {:ok, "GMT+00:00"} =
               Timezone.gmt_format(%{utc_offset: 0, std_offset: 0}, :en, zero_format: :offset)
    end

    test "long format includes minutes for fractional-hour offsets" do
      assert {:ok, "GMT-05:30"} =
               Timezone.gmt_format(%{utc_offset: -19_800, std_offset: 0}, :en)

      assert {:ok, "GMT+01:00"} = Timezone.gmt_format(%{utc_offset: 3600, std_offset: 0}, :en)
    end

    test "short format drops zero minutes and leading hour zero" do
      assert {:ok, "GMT-8"} =
               Timezone.gmt_format(%{utc_offset: -28_800, std_offset: 0}, :en, format: :short)
    end

    test "std_offset is added to the base offset" do
      assert {:ok, "GMT-04:00"} = Timezone.gmt_format(@new_york_daylight, :en)
    end

    test "locale-specific GMT patterns are honoured" do
      # French uses "UTC" with a minus sign (U+2212) for negative offsets.
      assert {:ok, "UTC−05"} =
               Timezone.gmt_format(%{utc_offset: -18_000, std_offset: 0}, :fr, format: :short)
    end
  end

  describe "iso_format/2" do
    test "zero offset renders Z by default" do
      assert {:ok, "Z"} = Timezone.iso_format(%{utc_offset: 0, std_offset: 0})
    end

    test "z_for_zero: false renders the numeric zero offset" do
      assert {:ok, "+0000"} =
               Timezone.iso_format(%{utc_offset: 0, std_offset: 0}, z_for_zero: false)
    end

    test "basic and extended types differ by separator" do
      assert {:ok, "+0500"} = Timezone.iso_format(%{utc_offset: 18_000, std_offset: 0})

      assert {:ok, "+05:30"} =
               Timezone.iso_format(%{utc_offset: 19_800, std_offset: 0}, type: :extended)
    end

    test "short format drops zero minutes" do
      assert {:ok, "+05"} =
               Timezone.iso_format(%{utc_offset: 18_000, std_offset: 0}, format: :short)

      assert {:ok, "+0530"} =
               Timezone.iso_format(%{utc_offset: 19_800, std_offset: 0}, format: :short)
    end

    test "full format appends seconds when the offset has them" do
      assert {:ok, "+05:45:20"} =
               Timezone.iso_format(%{utc_offset: 20_720, std_offset: 0},
                 format: :full,
                 type: :extended
               )

      assert {:ok, "+010020"} =
               Timezone.iso_format(%{utc_offset: 3620, std_offset: 0},
                 format: :full,
                 type: :basic,
                 z_for_zero: false
               )
    end

    test "full format omits seconds when the offset is whole minutes" do
      assert {:ok, "-04:00"} =
               Timezone.iso_format(@new_york_daylight, format: :full, type: :extended)
    end

    test "a map with only utc_offset is accepted" do
      assert {:ok, "+0100"} = Timezone.iso_format(%{utc_offset: 3600})
    end
  end
end
