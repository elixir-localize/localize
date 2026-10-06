defmodule Localize.DateTime.OffsetZoneTest do
  @moduledoc """
  A date and time at a fixed offset is a `DateTime` whose time zone is the
  offset itself, "-05:00", as ECMA-262 Temporal and RFC 9557 name the zone
  of a fixed offset (user, 2026-10-06). It was carried under `Etc/UTC` with
  the offset as its `utc_offset`, a zone Elixir takes to have no offset:
  `DateTime.shift_zone/3` to UTC returned it unchanged, `DateTime.add/4`
  dropped its offset, and `DateTime.shift/3` kept its wall time and dropped
  the offset, a time five hours out.

  What Elixir's functions answer is theirs to define, and the zone symbols
  are TR35's: `en`'s `gmtFormat` is "GMT{0}" and its `hourFormat`
  "+HH:mm;-HH:mm", the short time zone ID of a zone that has none is "unk",
  and the exemplar city of `Etc/Unknown` is "Unknown Location".
  """

  use ExUnit.Case, async: true

  doctest Localize.TimeZoneDatabase

  alias Localize.DateTime.Timezone

  @written ~N[2026-06-16 10:00:00]
  @instant ~U[2026-06-16 15:00:00Z]

  defp at_minus_five do
    {:ok, datetime} = Localize.DateTime.parse("2026-06-16T10:00:00-05:00", locale: :en)
    datetime
  end

  defp zone_fields(%DateTime{} = datetime),
    do: {datetime.time_zone, datetime.zone_abbr, datetime.utc_offset, datetime.std_offset}

  describe "a date and time read with an offset" do
    test "has the offset as its time zone, and the wall time as written" do
      for {text, zone, offset} <- [
            {"2026-06-16T10:00:00-05:00", "-05:00", -18_000},
            {"2026-06-16T10:00:00+05:30", "+05:30", 19_800},
            {"20260616T100000-0500", "-05:00", -18_000},
            {"6/16/26, 10:00:00 AM GMT-5", "-05:00", -18_000},
            {"June 16, 2026 at 10:00:00 AM GMT+5:30", "+05:30", 19_800}
          ] do
        assert {:ok, %DateTime{} = datetime} = Localize.DateTime.parse(text, locale: :en)
        assert zone_fields(datetime) == {zone, zone, offset, 0}, text
        assert DateTime.to_naive(datetime) == @written, text
      end
    end

    test "has its seconds in the zone where the offset has them" do
      assert {:ok, datetime} = Timezone.resolve("-07:52:58", @written, locale: :en)
      assert zone_fields(datetime) == {"-07:52:58", "-07:52:58", -28_378, 0}
    end

    test "is UTC where there is no offset at all" do
      for text <- ["2026-06-16T10:00:00Z", "2026-06-16T10:00:00+00:00"] do
        assert {:ok, datetime} = Localize.DateTime.parse(text, locale: :en)
        assert zone_fields(datetime) == {"Etc/UTC", "UTC", 0, 0}, text
      end
    end

    test "carries the same fields as a map" do
      assert {:ok, map} =
               Localize.DateTime.parse("2026-06-16T10:00:00-05:00", locale: :en, as: :map)

      assert Map.take(map, [:time_zone, :zone_abbr, :utc_offset, :std_offset]) ==
               %{time_zone: "-05:00", zone_abbr: "-05:00", utc_offset: -18_000, std_offset: 0}
    end

    test "is the offset a name of standard time keeps where the zone keeps another" do
      assert {:ok, datetime} = Timezone.resolve("EST", ~N[2026-07-01 10:00:00], locale: :en)
      assert zone_fields(datetime) == {"-05:00", "-05:00", -18_000, 0}
    end
  end

  describe "Elixir's functions, given such a value" do
    test "take its moment from its offset" do
      datetime = at_minus_five()

      assert DateTime.to_iso8601(datetime) == "2026-06-16T10:00:00-05:00"
      assert DateTime.to_unix(datetime) == DateTime.to_unix(@instant)
      assert DateTime.compare(datetime, @instant) == :eq
      assert DateTime.diff(~U[2026-06-16 18:00:00Z], datetime, :hour) == 3
    end

    # Under `Etc/UTC` the value came back unchanged, 10:00 for 15:00 UTC.
    test "shift it into another zone" do
      datetime = at_minus_five()

      assert DateTime.shift_zone(datetime, "Etc/UTC") == {:ok, @instant}

      assert {:ok, %DateTime{hour: 20, time_zone: "Asia/Karachi", utc_offset: 18_000}} =
               DateTime.shift_zone(datetime, "Asia/Karachi", Tz.TimeZoneDatabase)
    end

    # They look the value's own zone up, and a database of IANA's zones
    # does not have it. Under `Etc/UTC` they answered: `add/4` with the
    # offset dropped, `shift/3` with a time five hours from the right one.
    test "say they do not know its zone where they must look it up" do
      datetime = at_minus_five()

      for database <- [Calendar.UTCOnlyTimeZoneDatabase, Tz.TimeZoneDatabase] do
        assert_raise ArgumentError, fn -> DateTime.add(datetime, 1, :hour, database) end
        assert_raise ArgumentError, fn -> DateTime.shift(datetime, [month: 1], database) end
        assert {:error, _unknown} = DateTime.from_naive(@written, "-05:00", database)
      end
    end
  end

  describe "Localize.TimeZoneDatabase" do
    test "answers for a fixed offset's zone, whose clock never changes" do
      datetime = at_minus_five()

      assert {:ok, later} = {:ok, DateTime.add(datetime, 1, :hour, Localize.TimeZoneDatabase)}
      assert DateTime.to_naive(later) == ~N[2026-06-16 11:00:00]
      assert zone_fields(later) == {"-05:00", "-05:00", -18_000, 0}

      next_month = DateTime.shift(datetime, [month: 1], Localize.TimeZoneDatabase)
      assert DateTime.to_naive(next_month) == ~N[2026-07-16 10:00:00]
      assert zone_fields(next_month) == {"-05:00", "-05:00", -18_000, 0}
      assert DateTime.compare(next_month, ~U[2026-07-16 15:00:00Z]) == :eq

      assert DateTime.from_naive(@written, "-05:00", Localize.TimeZoneDatabase) == {:ok, datetime}

      assert {:ok, %DateTime{time_zone: "+05:30", utc_offset: 19_800} = india} =
               DateTime.shift_zone(datetime, "+05:30", Localize.TimeZoneDatabase)

      assert DateTime.to_naive(india) == ~N[2026-06-16 20:30:00]
    end

    test "asks the database it wraps about every other zone" do
      assert {:ok, %DateTime{zone_abbr: "EST", utc_offset: -18_000}} =
               DateTime.from_naive(
                 ~N[2026-01-15 12:00:00],
                 "America/New_York",
                 Localize.TimeZoneDatabase
               )

      assert DateTime.from_naive(@written, "Middle/Earth", Localize.TimeZoneDatabase) ==
               DateTime.from_naive(@written, "Middle/Earth", Tz.TimeZoneDatabase)
    end

    # A fixed offset's zone is the offset as ISO 8601 writes it between
    # colons, of hours a day has. Anything else is the wrapped database's
    # to know.
    test "takes only an offset written as Localize writes one for a fixed offset's zone" do
      for zone <- ["+0530", "+5:30", "+05", "05:30", "GMT+5", "+24:00", "+05:60", "", "-05:00 "] do
        assert Timezone.zone_offset(zone) == :error, inspect(zone)

        assert {:error, _unknown} = DateTime.from_naive(@written, zone, Localize.TimeZoneDatabase),
               inspect(zone)
      end

      for {zone, offset} <- [
            {"+05:30", 19_800},
            {"-05:00", -18_000},
            {"+00:00", 0},
            {"-07:52:58", -28_378},
            {"+23:59", 86_340}
          ] do
        assert Timezone.zone_offset(zone) == {:ok, offset}
        assert Timezone.offset_zone(offset) == zone or offset == 0
      end

      for not_a_zone <- [nil, :"+05:30", 19_800, ~c"+05:30"] do
        assert Timezone.zone_offset(not_a_zone) == :error
      end
    end
  end

  describe "a value at a fixed offset, written" do
    test "is its offset in every form of a zone" do
      datetime = at_minus_five()

      for {pattern, written} <- [
            {"z", "GMT-5"},
            {"zzzz", "GMT-05:00"},
            {"O", "GMT-5"},
            {"OOOO", "GMT-05:00"},
            {"v", "GMT-5"},
            {"vvvv", "GMT-05:00"},
            {"VVVV", "GMT-05:00"},
            {"Z", "-0500"},
            {"ZZZZ", "GMT-05:00"},
            {"ZZZZZ", "-05:00"},
            {"x", "-05"},
            {"xx", "-0500"},
            {"xxx", "-05:00"},
            {"X", "-05"},
            {"XXX", "-05:00"}
          ] do
        assert Localize.DateTime.to_string(datetime, format: pattern, locale: :en) ==
                 {:ok, written},
               pattern
      end
    end

    # It has no short ID and is in no place, and its long ID is its own.
    # Under `Etc/UTC` it was written as UTC's: "utc" and "Etc/UTC".
    test "has the zone IDs of a zone CLDR does not know" do
      datetime = at_minus_five()

      for {pattern, written} <- [{"V", "unk"}, {"VV", "-05:00"}, {"VVV", "Unknown Location"}] do
        assert Localize.DateTime.to_string(datetime, format: pattern, locale: :en) ==
                 {:ok, written},
               pattern
      end
    end

    test "reads back as the value it was written from" do
      for text <- ["2026-06-16T10:00:00-05:00", "2026-06-16T10:00:00+05:30"],
          format <- [:long, :full] do
        {:ok, datetime} = Localize.DateTime.parse(text, locale: :en)
        {:ok, written} = Localize.DateTime.to_string(datetime, format: format, locale: :en)

        assert Localize.DateTime.parse(written, locale: :en) == {:ok, datetime},
               "#{format} #{inspect(written)}"
      end
    end
  end

  describe "a value at a fixed offset, measured" do
    test "is its own moment in a duration and in relative time" do
      datetime = at_minus_five()

      assert {:ok, %Localize.Duration{day: 0, hour: 3, minute: 0}} =
               Localize.Duration.new(datetime, ~U[2026-06-16 18:00:00Z])

      assert Localize.DateTime.Relative.to_string(datetime,
               relative_to: ~U[2026-06-16 12:00:00Z],
               locale: :en
             ) == {:ok, "in 3 hours"}
    end

    # A message converts it to the zone it asks for as it converts the same
    # moment given in UTC.
    test "is converted by a message's timeZone option as its moment in UTC is" do
      message = "{$when :datetime timeZone=UTC}"
      {:ok, utc} = Localize.Message.format(message, %{"when" => @instant}, locale: :en)

      assert Localize.Message.format(message, %{"when" => at_minus_five()}, locale: :en) ==
               {:ok, utc}
    end
  end

  # A caller may still build one as Localize carried it, and it is the same
  # fixed offset wherever Localize reads it.
  describe "a fixed offset under Etc/UTC, as it was carried" do
    setup do
      fields = %{time_zone: "Etc/UTC", zone_abbr: "-05:00", utc_offset: -18_000, std_offset: 0}
      %{carried: struct(DateTime, Map.merge(Map.from_struct(@written), fields))}
    end

    test "is written as its offset", %{carried: carried} do
      for {pattern, written} <- [{"z", "GMT-5"}, {"OOOO", "GMT-05:00"}, {"xxx", "-05:00"}] do
        assert Localize.DateTime.to_string(carried, format: pattern, locale: :en) ==
                 {:ok, written}
      end
    end

    test "is measured and converted as its moment", %{carried: carried} do
      assert {:ok, %Localize.Duration{day: 0, hour: 3, minute: 0}} =
               Localize.Duration.new(carried, ~U[2026-06-16 18:00:00Z])

      message = "{$when :datetime timeZone=UTC}"
      {:ok, utc} = Localize.Message.format(message, %{"when" => @instant}, locale: :en)
      assert Localize.Message.format(message, %{"when" => carried}, locale: :en) == {:ok, utc}
    end
  end
end

defmodule Localize.DateTime.OffsetZoneDatabaseTest do
  @moduledoc """
  The database `Localize.TimeZoneDatabase` wraps is the application's to
  name, which is set for the whole VM, so these are not run beside others.
  """

  use ExUnit.Case, async: false

  setup do
    on_exit(fn -> Application.delete_env(:localize, :time_zone_database) end)
  end

  test "wraps the database the application names" do
    Application.put_env(:localize, :time_zone_database, Calendar.UTCOnlyTimeZoneDatabase)
    assert Localize.TimeZoneDatabase.wrapped() == Calendar.UTCOnlyTimeZoneDatabase

    assert DateTime.from_naive(
             ~N[2026-01-15 12:00:00],
             "America/New_York",
             Localize.TimeZoneDatabase
           ) == {:error, :utc_only_time_zone_database}

    assert {:ok, %DateTime{time_zone: "+05:30"}} =
             DateTime.from_naive(~N[2026-01-15 12:00:00], "+05:30", Localize.TimeZoneDatabase)

    assert DateTime.from_naive(~N[2026-01-15 12:00:00], "Etc/UTC", Localize.TimeZoneDatabase) ==
             {:ok, ~U[2026-01-15 12:00:00Z]}
  end

  test "wraps a database that is loaded where none is named, and never itself" do
    assert Localize.TimeZoneDatabase.wrapped() == Tz.TimeZoneDatabase

    Application.put_env(:localize, :time_zone_database, Localize.TimeZoneDatabase)
    assert Localize.TimeZoneDatabase.wrapped() == Tz.TimeZoneDatabase
  end
end
