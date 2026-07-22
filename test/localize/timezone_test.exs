defmodule Localize.DateTime.TimezoneTest do
  use ExUnit.Case, async: true

  doctest Localize.DateTime.Timezone

  describe "known_timezones/0" do
    test "returns sorted canonical IANA names without duplicates" do
      zones = Localize.DateTime.Timezone.known_timezones()

      assert zones == Enum.sort(zones)
      assert zones == Enum.uniq(zones)
      assert length(zones) > 400
    end

    test "contains canonical names, not non-primary aliases" do
      zones = Localize.DateTime.Timezone.known_timezones()

      assert "Australia/Sydney" in zones
      refute "Australia/NSW" in zones
    end

    test "is re-exported on Localize" do
      assert Localize.known_timezones() == Localize.DateTime.Timezone.known_timezones()
    end
  end
end
