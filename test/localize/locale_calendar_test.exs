defmodule Localize.LocaleCalendarTest do
  @moduledoc """
  A locale's `-u-ca-` names the calendar its dates are written in, so a value
  is converted into that calendar before it is formatted. A CLDR calendar type
  names no module on its own and Localize ships the ISO calendar alone, so the
  module comes from the value's own calendar through the optional
  `calendar_from_cldr_calendar_type/1` the library supplying the calendars
  answers for its family.

  """

  use ExUnit.Case, async: true

  alias Localize.Calendar, as: LocalizeCalendar

  defmodule Buddhist do
    @moduledoc false
    use Localize.Test.StandInCalendar

    def cldr_calendar_type, do: :buddhist
  end

  defmodule Family do
    @moduledoc false
    use Localize.Test.StandInCalendar

    def cldr_calendar_type, do: :gregorian

    def calendar_from_cldr_calendar_type(:buddhist),
      do: {:ok, Localize.LocaleCalendarTest.Buddhist}

    def calendar_from_cldr_calendar_type(_other), do: :error
  end

  defmodule Lonely do
    @moduledoc false
    use Localize.Test.StandInCalendar

    def cldr_calendar_type, do: :gregorian
  end

  @date ~D[2026-05-16]

  test "a locale naming no calendar leaves the value alone" do
    assert {:ok, @date} = LocalizeCalendar.convert_to_locale_calendar(@date, "en")
  end

  test "a value already in the calendar the locale names is left alone" do
    {:ok, buddhist} = Date.convert(@date, Buddhist)

    assert {:ok, ^buddhist} =
             LocalizeCalendar.convert_to_locale_calendar(buddhist, "en-u-ca-buddhist")
  end

  test "a value is converted into the calendar the locale names" do
    {:ok, in_family} = Date.convert(@date, Family)

    assert {:ok, %Date{calendar: Buddhist}} =
             LocalizeCalendar.convert_to_locale_calendar(in_family, "en-u-ca-buddhist")
  end

  # The family answers for the calendars it supplies, and a calendar whose
  # family does not answer leaves the type unknown rather than raising.
  test "a calendar whose family cannot supply the type is an error" do
    {:ok, lonely} = Date.convert(@date, Lonely)

    assert {:error, %Localize.UnknownCalendarError{calendar: :buddhist}} =
             LocalizeCalendar.convert_to_locale_calendar(lonely, "en-u-ca-buddhist")

    {:ok, in_family} = Date.convert(@date, Family)

    assert {:error, %Localize.UnknownCalendarError{calendar: :coptic}} =
             LocalizeCalendar.convert_to_locale_calendar(in_family, "en-u-ca-coptic")
  end

  test "a time has no calendar to write it in" do
    assert {:ok, ~T[11:30:00]} =
             LocalizeCalendar.convert_to_locale_calendar(~T[11:30:00], "en-u-ca-buddhist")
  end

  describe "formatting honours the locale's calendar" do
    test "a date is written as the calendar the locale names writes it" do
      {:ok, in_family} = Date.convert(@date, Family)
      {:ok, converted} = Date.convert(in_family, Buddhist)

      assert Localize.Date.to_string(in_family, locale: "en-u-ca-buddhist", format: :long) ==
               Localize.Date.to_string(converted, locale: "en", format: :long)

      # Not trivially equal: the unconverted value writes something else.
      refute Localize.Date.to_string(in_family, locale: "en-u-ca-buddhist", format: :long) ==
               Localize.Date.to_string(in_family, locale: "en", format: :long)
    end

    test "a locale naming a calendar the value's family cannot supply is an error" do
      {:ok, lonely} = Date.convert(@date, Lonely)

      assert {:error, %Localize.UnknownCalendarError{}} =
               Localize.Date.to_string(lonely, locale: "en-u-ca-buddhist")
    end
  end
end
