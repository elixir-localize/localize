defmodule Localize.DateTime.GenericZoneFormatTest do
  @moduledoc """
  The generic non-location zone format (`v`, `vvvv`), as TR35's steps give
  it and CLDR's own `TimezoneFormatter` implements them: a metazone name is
  qualified by the zone's country or city unless the zone is the metazone's
  preferred zone for the locale's country.

  The expected strings are TR35's worked examples ("Pacific Time (Canada)"
  for Vancouver in `en_MX`, "Mountain Time (Phoenix)", "Pacific Time
  (Whitehorse)"), and ICU4C 78.3's where it agrees; where it does not, the
  divergence is recorded in the ICU divergences guide. This suite configures
  `:tz` as the time zone database.

  """

  use ExUnit.Case, async: true

  defp generic(zone, naive, locale, format \\ "vvvv") do
    datetime = DateTime.from_naive!(naive, zone)
    {:ok, text} = Localize.DateTime.to_string(datetime, locale: locale, format: format)
    text
  end

  describe "TR35's worked examples" do
    test "the metazone's preferred zone for the locale's country is unqualified" do
      assert generic("America/Vancouver", ~N[2023-01-15 10:00:00], :"en-CA") == "Pacific Time"
      assert generic("America/Los_Angeles", ~N[2023-01-15 10:00:00], :"en-US") == "Pacific Time"
    end

    test "a country's preferred zone is qualified by its country" do
      assert generic("America/Vancouver", ~N[2023-01-15 10:00:00], :"en-MX") ==
               "Pacific Time (Canada)"
    end

    # Whitehorse kept Pacific time until 2020.
    test "any other zone is qualified by its city" do
      assert generic("America/Phoenix", ~N[2023-07-15 10:00:00], :en) ==
               "Mountain Time (Phoenix)"

      assert generic("America/Whitehorse", ~N[2019-01-15 10:00:00], :en) ==
               "Pacific Time (Whitehorse)"

      assert generic("America/Whitehorse", ~N[2019-01-15 10:00:00], :en, "v") ==
               "PT (Whitehorse)"
    end
  end

  describe "a zone's country or city" do
    # ICU4C 78.3 writes these too, the first in summer only.
    test "where ICU qualifies them as well" do
      assert generic("America/New_York", ~N[2023-07-15 10:00:00], :"en-JM") ==
               "Eastern Time (United States)"

      assert generic("Europe/Paris", ~N[2023-07-15 10:00:00], :"ar-TN") ==
               "توقيت وسط أوروبا (فرنسا)"
    end

    # ICU4C 78.3 writes these unqualified, as the zone keeps the preferred
    # zone's offset at that moment (a recorded divergence).
    test "where ICU does not" do
      assert generic("America/New_York", ~N[2023-01-15 10:00:00], :"en-JM") ==
               "Eastern Time (United States)"

      assert generic("Europe/Berlin", ~N[2023-07-15 10:00:00], :en) ==
               "Central European Time (Germany)"

      assert generic("America/Toronto", ~N[2023-07-15 10:00:00], :en) ==
               "Eastern Time (Canada)"
    end

    test "the locale's own country's zone is unqualified" do
      assert generic("Europe/Berlin", ~N[2023-07-15 10:00:00], :de) == "Mitteleuropäische Zeit"
      assert generic("Europe/Paris", ~N[2023-07-15 10:00:00], :en) == "Central European Time"
    end
  end

  describe "the locale's fallback format" do
    # `el.xml` writes the fallback format "[{1} ({0})]", and names Canada
    # "Καναδάς" and Pacific time "Ώρα Ειρηνικού".
    test "in the locale's own shape" do
      assert generic("America/Vancouver", ~N[2023-07-15 10:00:00], :el) ==
               "[Ώρα Ειρηνικού (Καναδάς)]"
    end

    # `su.xml` names Pacific time "Waktu Pasifik" and no Canada, so TR35's
    # composition writes the country's code.
    test "with a country the locale does not name" do
      assert generic("America/Vancouver", ~N[2023-07-15 10:00:00], :su) ==
               "Waktu Pasifik (CA)"
    end
  end

  describe "a standard name in the generic format" do
    # CLDR's conformance data writes `Etc/GMT` this way; India keeps one
    # offset and `en` names only its standard time.
    test "for a zone that keeps one offset" do
      assert generic("Etc/GMT", ~N[2000-01-01 00:00:00], :en) == "Greenwich Mean Time"
      assert generic("Asia/Kolkata", ~N[2023-07-15 10:00:00], :en) == "India Standard Time"
    end

    # `raj` names the British metazone's standard time only; London keeps
    # summer time, so its generic name is its location, as ICU4C writes it
    # too, never the standard name.
    test "not for a zone that changes offset" do
      for naive <- [~N[2023-07-15 10:00:00], ~N[2023-01-15 10:00:00]] do
        assert generic("Europe/London", naive, :raj) ==
                 elem(
                   Localize.DateTime.Timezone.generic_location_format("Europe/London", :raj),
                   1
                 )
      end
    end
  end

  describe "a generic name read back" do
    test "is the same instant" do
      for {zone, naive, locale} <- [
            {"America/Phoenix", ~N[2023-07-15 10:05:00], :en},
            {"America/Vancouver", ~N[2023-07-15 10:05:00], :en},
            {"America/New_York", ~N[2023-07-15 10:05:00], :"en-JM"},
            {"Europe/Berlin", ~N[2023-07-15 10:05:00], :en},
            {"Europe/London", ~N[2023-07-15 10:05:00], :raj},
            {"America/Vancouver", ~N[2023-07-15 10:05:00], :el},
            {"America/Vancouver", ~N[2023-07-15 10:05:00], :su}
          ] do
        datetime = DateTime.from_naive!(naive, zone)

        {:ok, text} =
          Localize.DateTime.to_string(datetime, locale: locale, format: :yMMMdjmsvvvv)

        assert {:ok, %DateTime{} = parsed} = Localize.DateTime.parse(text, locale: locale)
        assert DateTime.compare(parsed, datetime) == :eq, "#{locale} #{zone}: #{text}"
      end
    end
  end
end

defmodule Localize.DateTime.GenericZoneFormatWithoutDatabaseTest do
  @moduledoc """
  Without a time zone database to say whether a zone keeps one offset, the
  generic format takes TR35's own test: names with no daylight time are for
  a zone that keeps none. The database is set for the whole node, so these
  tests run apart from the asynchronous ones.

  """

  use ExUnit.Case, async: false

  setup do
    database = Calendar.get_time_zone_database()
    on_exit(fn -> Calendar.put_time_zone_database(database) end)
    {:ok, database: database}
  end

  test "a name with no daylight time is the standard one", %{database: database} do
    kolkata = DateTime.from_naive!(~N[2023-07-15 10:00:00], "Asia/Kolkata", database)
    Calendar.put_time_zone_database(Calendar.UTCOnlyTimeZoneDatabase)

    assert Localize.DateTime.to_string(kolkata, locale: :en, format: "vvvv") ==
             {:ok, "India Standard Time"}
  end
end
