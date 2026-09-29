defmodule Localize.Message.DateTimeOptionsTest do
  @moduledoc """
  TR35's `:date`, `:time` and `:datetime` functions.

  Their options are semantic skeleton choices, so each expected string is the
  CLDR 49 pattern TR35's mapping selects, applied by hand: `{$d :date
  fields=month-day}` in `en-AU` is the medium month and day, `MMMd`, whose
  pattern is "d MMM", so June 14 is "14 Jun". The patterns are quoted beside
  the cases. A year, month and day at one length is the locale's standard
  date format at that length, since TR35 takes its widths from that format's
  own skeleton. Where ICU 77 gives the same string, through
  `Intl.DateTimeFormat` with the matching `dateStyle` or components, the case
  says so. The reference instant is the MF2 working group's, 2006-01-02
  15:04:06, a Monday.

  """

  use ExUnit.Case, async: true

  @zoned DateTime.new!(~D[2006-01-02], ~T[15:04:06], "America/New_York")

  defp format(message, bindings \\ %{}, locale \\ "en-US") do
    Localize.Message.format(message, bindings, locale: locale)
  end

  describe ":date" do
    test "defaults to the medium year, month and day, the locale's medium date" do
      # en medium date "MMM d, y"; ICU `dateStyle: "medium"` agrees.
      assert format("{|2006-01-02| :date}") == {:ok, "Jan 2, 2006"}
      assert format("{|2006-01-02T15:04:06| :date}") == {:ok, "Jan 2, 2006"}
      assert format("{$d :date}", %{"d" => ~D[2006-01-02]}) == {:ok, "Jan 2, 2006"}
    end

    test "length chooses the locale's date format of that length" do
      # en short "M/d/yy", long "MMMM d, y".
      assert format("{|2006-01-02| :date length=short}") == {:ok, "1/2/06"}
      assert format("{|2006-01-02| :date length=long}") == {:ok, "January 2, 2006"}
    end

    test "fields chooses the fields" do
      # en `MMMd` "MMM d"; `Ed` "d E"; `MMMEd` "E, MMM d" at long widths;
      # full date "EEEE, MMMM d, y".
      assert format("{|2006-01-02| :date fields=month-day}") == {:ok, "Jan 2"}
      assert format("{|2006-01-02| :date fields=day-weekday}") == {:ok, "2 Mon"}

      assert format("{|2006-01-02| :date fields=month-day-weekday length=long}") ==
               {:ok, "Monday, January 2"}

      assert format("{|2006-01-02| :date fields=year-month-day-weekday length=long}") ==
               {:ok, "Monday, January 2, 2006"}
    end

    test "a weekday on its own is narrow at short length" do
      # en `E` "ccc", standalone; TR35 makes it `EEEEE` at short length.
      assert format("{|2006-01-02| :date fields=weekday length=short}") == {:ok, "M"}
      assert format("{|2006-01-02| :date fields=weekday}") == {:ok, "Mon"}
      assert format("{|2006-01-02| :date fields=weekday length=long}") == {:ok, "Monday"}
    end

    test "the month and day of en-AU, medium and long" do
      # en-AU `MMMd` "d MMM" and `MMMMd` "d MMMM".
      assert format("{|2026-06-14| :date fields=month-day}", %{}, "en-AU") == {:ok, "14 Jun"}

      assert format("{|2026-06-14| :date fields=month-day length=long}", %{}, "en-AU") ==
               {:ok, "14 June"}
    end

    test "a locale's own date formats, even where CLDR misdescribes them" do
      # de medium "dd.MM.y". be medium "d MMM y 'г'.", whose CLDR
      # skeleton `yMMd` says numeric; da full "EEEE 'den' d. MMMM y". ICU's
      # `dateStyle` gives each of these, be's with CLDR 47's plain space.
      assert format("{|2006-01-02| :date}", %{}, "de") == {:ok, "02.01.2006"}
      assert format("{|2006-01-02| :date}", %{}, "be") == {:ok, "2 сту 2006 г."}

      assert format("{|2006-01-02| :date fields=year-month-day-weekday length=long}", %{}, "da") ==
               {:ok, "mandag den 2. januar 2006"}
    end
  end

  describe ":time" do
    test "defaults to the minute" do
      # en `hm` "h:mm a".
      assert format("{|2006-01-02T15:04:06| :time}") == {:ok, "3:04 PM"}
      assert format("{$t :time}", %{"t" => ~N[2006-01-02 15:04:06]}) == {:ok, "3:04 PM"}
      assert format("{$t :time}", %{"t" => ~T[15:04:06]}) == {:ok, "3:04 PM"}
    end

    test "precision chooses the hour, minute or second" do
      # en `h` "h a" and `hms` "h:mm:ss a".
      assert format("{|2006-01-02T15:04:06| :time precision=hour}") == {:ok, "3 PM"}

      assert format("{|2006-01-02T15:04:06| :time precision=second}") ==
               {:ok, "3:04:06 PM"}
    end

    test "hour12 chooses the clock the locale writes for it" do
      # en `Hm` "HH:mm"; de `hm` "h:mm a"; ja `hm` "aK:mm", ja's
      # 24-hour `Hm` "H:mm".
      assert format("{|2006-01-02T15:04:06| :time hour12=false}") == {:ok, "15:04"}
      assert format("{|2006-01-02T15:04:06| :time hour12=true}", %{}, "de") == {:ok, "3:04 PM"}
      assert format("{|2006-01-02T15:04:06| :time hour12=true}", %{}, "ja") == {:ok, "午後3:04"}
      assert format("{|2006-01-02T15:04:06| :time}", %{}, "ja") == {:ok, "15:04"}
    end

    test "timeZoneStyle adds the specific zone, short or long" do
      # en `hmv` "h:mm a v" with the zone asked for; America_Eastern
      # "EST" and "Eastern Standard Time". ICU agrees.
      assert format("{$t :time timeZoneStyle=short}", %{"t" => @zoned}) ==
               {:ok, "3:04 PM EST"}

      assert format("{$t :time timeZoneStyle=long precision=second}", %{"t" => @zoned}) ==
               {:ok, "3:04:06 PM Eastern Standard Time"}
    end

    test "an offset has no zone name, so it takes the GMT format" do
      # ICU renders a `-05:00` time zone the same way.
      assert format("{|2006-01-02T15:04:06-05:00| :time timeZoneStyle=short}") ==
               {:ok, "3:04 PM GMT-5"}

      assert format("{|2006-01-02T15:04:06-05:00| :time timeZoneStyle=long}") ==
               {:ok, "3:04 PM GMT-05:00"}
    end

    test "a floating time has no zone to show" do
      assert format("{|2006-01-02T15:04:06| :time timeZoneStyle=short}") == {:ok, "3:04 PM"}
    end
  end

  describe ":datetime" do
    test "defaults to the medium date and the minute" do
      # en medium date and `hm`, joined by the medium "{1}, {0}". ICU agrees.
      assert format("{|2006-01-02T15:04:06| :datetime}") == {:ok, "Jan 2, 2006, 3:04 PM"}

      assert format("{$d :datetime}", %{"d" => ~D[2006-01-02]}) ==
               {:ok, "Jan 2, 2006, 12:00 AM"}
    end

    test "a long or full date joins its time with the locale's at-time pattern" do
      # en long and full at-time "{1} 'at' {0}"; de "{1} 'um' {0}". ICU agrees.
      assert format("{|2006-01-02T15:04:06| :datetime dateLength=long}") ==
               {:ok, "January 2, 2006 at 3:04 PM"}

      assert format(
               "{|2006-01-02T15:04:06| :datetime dateFields=year-month-day-weekday dateLength=long timePrecision=second}"
             ) == {:ok, "Monday, January 2, 2006 at 3:04:06 PM"}

      assert format("{|2006-01-02T15:04:06| :datetime dateLength=long}", %{}, "de") ==
               {:ok, "2. Januar 2006 um 15:04"}
    end

    test "the date fields and time precision combine" do
      # en `MMMd` "MMM d" and `h` "h a", joined by the medium pattern
      # for an abbreviated month; ICU agrees. `Ehm` "E h:mm a".
      assert format("{|2006-01-02T15:04:06| :datetime dateFields=month-day timePrecision=hour}") ==
               {:ok, "Jan 2, 3 PM"}

      assert format("{|2006-01-02T15:04:06| :datetime dateFields=weekday}") ==
               {:ok, "Mon 3:04 PM"}
    end

    test "timePrecision=second is the spec's second, not a style" do
      assert format("{|2006-01-02T15:04:06| :datetime timePrecision=second}") ==
               {:ok, "Jan 2, 2006, 3:04:06 PM"}
    end
  end

  describe "timeZone" do
    test "converts a zoned or offset value into the zone" do
      assert format(
               "{|2006-01-02T15:04:06Z| :datetime timeZone=|America/New_York| timeZoneStyle=long}"
             ) == {:ok, "Jan 2, 2006, 10:04 AM Eastern Standard Time"}

      assert format("{|2006-01-02T15:04:06-05:00| :time timeZone=UTC timeZoneStyle=short}") ==
               {:ok, "8:04 PM UTC"}
    end

    test "a conversion can move the date" do
      assert format("{|2006-01-02T23:30:00-05:00| :date timeZone=UTC}") == {:ok, "Jan 3, 2006"}
    end

    test "places a floating time in the zone" do
      assert format(
               "{|2006-01-02T15:04:06| :datetime timeZone=|America/New_York| timeZoneStyle=short}"
             ) == {:ok, "Jan 2, 2006, 3:04 PM EST"}
    end

    # Temporal's `compatible` disambiguation: 02:30 on 8 March 2026 does not
    # happen in New York and is read with the offset before it, so 03:30 EDT;
    # 01:30 on 1 November happens twice and is the earlier, EDT.
    test "a skipped or repeated wall time resolves as Temporal's compatible does" do
      assert format(
               "{|2026-03-08T02:30:00| :time timeZone=|America/New_York| timeZoneStyle=short}"
             ) ==
               {:ok, "3:30 AM EDT"}

      assert format(
               "{|2026-11-01T01:30:00| :time timeZone=|America/New_York| timeZoneStyle=short}"
             ) ==
               {:ok, "1:30 AM EDT"}
    end

    test "input keeps the operand's zone, which a floating time lacks" do
      assert format("{|2006-01-02T15:04:06-05:00| :time timeZone=input timeZoneStyle=short}") ==
               {:ok, "3:04 PM GMT-5"}

      assert {:error, %Localize.FormatError{detail: detail}} =
               format("{|2006-01-02T15:04:06| :time timeZone=input}")

      assert detail =~ "needs an operand with a time zone or offset"
    end

    test "may be set by a variable" do
      bindings = %{"d" => ~U[2006-01-02 20:04:06Z], "zone" => "America/Los_Angeles"}

      assert format("{$d :time timeZone=$zone timeZoneStyle=short}", bindings) ==
               {:ok, "12:04 PM PST"}
    end

    test "a zone the database does not know is an error" do
      assert {:error, %Localize.FormatError{detail: detail}} =
               format("{|2006-01-02T15:04:06Z| :time timeZone=|Mars/Olympus|}")

      assert detail =~ "Mars/Olympus"
    end
  end

  describe "declarations" do
    test "a re-annotation inherits the override options and nothing else" do
      message =
        ".local $d = {|2006-01-02T15:04:06Z| :datetime timeZone=|America/New_York| dateLength=long} " <>
          "{{{$d :time timeZoneStyle=short}}}"

      assert format(message) == {:ok, "10:04 AM EST"}

      assert format(
               ".local $d = {|2006-01-02| :datetime dateLength=long timePrecision=second} {{{$d :date}}}"
             ) == {:ok, "Jan 2, 2006"}
    end

    test "a declared value formats with its own options" do
      assert format(".local $d = {|2006-01-02| :date length=long} {{{$d}}}") ==
               {:ok, "January 2, 2006"}

      assert format(".local $t = {|2006-01-02T15:04:06| :time precision=second} {{{$t}}}") ==
               {:ok, "3:04:06 PM"}
    end
  end

  describe "invalid options" do
    test "an option other than an override option must be a literal" do
      for message <- [
            "{$d :date fields=$x}",
            "{$d :date length=$x}",
            "{$d :time precision=$x}",
            "{$d :datetime dateFields=$x}",
            "{$d :datetime timeZoneStyle=$x}"
          ] do
        assert {:error, %Localize.FormatError{detail: detail}} =
                 format(message, %{"d" => ~D[2006-01-02], "x" => "short"})

        assert detail =~ "must be set by a literal value", message
      end
    end

    test "a value the option does not take is an error" do
      for message <- [
            "{|2006-01-02| :date fields=bogus}",
            "{|2006-01-02| :date length=huge}",
            "{|2006-01-02T15:04:06| :time precision=minutes}",
            "{|2006-01-02T15:04:06| :time timeZoneStyle=medium}",
            "{|2006-01-02T15:04:06| :time hour12=maybe}",
            "{|2006-01-02T15:04:06| :datetime dateLength=5}"
          ] do
        assert {:error, %Localize.FormatError{}} = format(message), message
      end
    end

    test "calendar needs Calendrical, which provides the calendars" do
      assert {:error, %Localize.FormatError{cause: %Localize.DependencyRequiredError{}}} =
               format("{|2006-01-02| :date calendar=hebrew}")
    end
  end

  describe "invalid operands" do
    test "are errors, not exceptions" do
      for {message, value} <- [
            {"{$x :date}", 42},
            {"{$x :date}", "not-a-date"},
            {"{$x :date}", ~T[15:04:06]},
            {"{$x :date}", <<255>>},
            {"{$x :datetime}", ~T[15:04:06]},
            {"{$x :datetime}", <<"2006-01-02T15:04", 255>>},
            {"{$x :time}", %{year: 2006}}
          ] do
        assert {:error, %Localize.FormatError{}} = format(message, %{"x" => value}),
               "#{message} with #{inspect(value)}"
      end
    end
  end

  # The `style`, `dateStyle` and `timeStyle` options of earlier drafts, which
  # ICU's MessageFormat still takes, keep choosing the standard formats.
  describe "earlier drafts' styles" do
    test "choose the locale's standard formats" do
      assert format("{|2006-01-02| :date style=short}") == {:ok, "1/2/06"}
      assert format("{|2006-01-02| :date length=full}") == {:ok, "Monday, January 2, 2006"}
      assert format("{|2006-01-02T15:04:06| :time style=short}") == {:ok, "3:04 PM"}
      assert format("{|2006-01-02T15:04:06| :time style=medium}") == {:ok, "3:04:06 PM"}

      assert format("{|2006-01-02T15:04:06| :datetime dateStyle=long timeStyle=short}") ==
               {:ok, "January 2, 2006 at 3:04 PM"}

      assert format("{|2006-01-02T15:04:06| :datetime style=short}") ==
               {:ok, "1/2/06, 3:04 PM"}
    end

    test "take hour12 as the locale's hour cycle" do
      assert format("{|2006-01-02T15:04:06| :time style=short hour12=false}") == {:ok, "15:04"}
    end
  end
end
