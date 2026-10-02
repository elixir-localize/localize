defmodule Localize.TimeCalendarParseTest do
  @moduledoc """
  A time is read in the time formats of the calendar it is written for, as
  the formatter writes it, and then in the Gregorian calendar's.

  The patterns are CLDR's: in `de` the Chinese calendar's `Bh` is root's
  "h B", so ten in the morning is "10 vorm.", where `de`'s Gregorian `Bh`
  is "h 'Uhr' B", "10 Uhr vorm." (`common/main/root.xml` and `de.xml`).

  """

  use ExUnit.Case, async: true

  # Stands in for Calendrical's Chinese calendar: its time formats are the
  # CLDR Chinese calendar's.
  defmodule Chinese do
    @moduledoc false
    use Localize.Test.StandInCalendar

    def cldr_calendar_type, do: :chinese
  end

  describe "a time written for a calendar" do
    test "is read in that calendar's time formats" do
      assert Localize.Time.parse("10 vorm.", locale: :de, calendar: Chinese) ==
               {:ok, ~T[10:00:00]}

      assert Localize.Time.parse("10 vorm.", locale: :de, calendar: Chinese, as: :map) ==
               {:ok, %{hour: 10}}
    end

    test "is read in the Gregorian calendar's time formats too" do
      assert Localize.Time.parse("10 Uhr vorm.", locale: :de, calendar: Chinese) ==
               {:ok, ~T[10:00:00]}

      assert Localize.Time.parse("10 Uhr vorm.", locale: :de) == {:ok, ~T[10:00:00]}
    end

    test "is read in the Gregorian calendar's alone where no calendar is given" do
      assert {:error, _no_pattern} = Localize.Time.parse("10 vorm.", locale: :de)
    end
  end

  describe "the :calendar option" do
    test "is a calendar module, not a CLDR calendar type" do
      for calendar <- [:chinese, "chinese", String] do
        assert {:error, %Localize.UnknownCalendarError{}} =
                 Localize.Time.parse("10:05", locale: :de, calendar: calendar)
      end
    end
  end
end
