defmodule Localize.CalendarEraNamesTest do
  @moduledoc """
  A calendar names its own eras where CLDR's data names none of its own:
  Calendrical's Bangla calendar takes its months from CLDR's Indian
  calendar but counts its years in another era. Localize asks the
  calendar's `era_names/1` for the era's names, in the shape
  `Localize.Calendar.eras/2` gives them, and takes CLDR's where the
  calendar answers `:cldr` or has no `era_names/1`. These stand-ins answer
  as the Gregorian calendar does but for their eras.

  """

  use ExUnit.Case, async: true

  # A Gregorian calendar that names its own era, the one its years are in,
  # given the locale as a language tag.
  defmodule OwnEra do
    @moduledoc false
    use Localize.Test.StandInCalendar

    def era_names(%Localize.LanguageTag{language: language}) do
      if language == :fr do
        {:ok, %{wide: %{1 => "ère d'essai"}, abbreviated: %{1 => "EE"}, narrow: %{1 => "E"}}}
      else
        {:ok, %{wide: %{1 => "Test Era"}, abbreviated: %{1 => "TE"}, narrow: %{1 => "T"}}}
      end
    end
  end

  # A Gregorian calendar that answers `era_names/1` and leaves its eras to CLDR.
  defmodule CldrEra do
    @moduledoc false
    use Localize.Test.StandInCalendar

    def era_names(_locale) do
      :cldr
    end
  end

  defp written(date, format, locale \\ :en) do
    Localize.Date.to_string(date, format: format, locale: locale)
  end

  describe "a calendar that names its eras" do
    test "is written with its own names, at each width" do
      date = Date.new!(2026, 6, 15, OwnEra)

      assert written(date, "y G") == {:ok, "2026 TE"}
      assert written(date, "y GGGG") == {:ok, "2026 Test Era"}
      assert written(date, "y GGGGG") == {:ok, "2026 T"}
    end

    test "is named for the locale it is written in" do
      assert written(Date.new!(2026, 6, 15, OwnEra), "y GGGG", :fr) == {:ok, "2026 ère d'essai"}
    end

    test "is read back by its own names" do
      assert Localize.Date.parse("2026 TE 6 15", locale: :en, calendar: OwnEra, format: "y G M d") ==
               {:ok, Date.new!(2026, 6, 15, OwnEra)}
    end

    test "gives its names as eras/2 gives CLDR's" do
      assert {:ok, %{wide: %{1 => "Test Era"}}} = Localize.Calendar.calendar_eras(OwnEra, :en)
    end
  end

  describe "a calendar that leaves its eras to CLDR" do
    test "is written with CLDR's names" do
      assert written(Date.new!(2026, 6, 15, CldrEra), "y G") == {:ok, "2026 AD"}
      assert written(~D[2026-06-15], "y G") == {:ok, "2026 AD"}
    end

    test "has CLDR's names, as has a calendar without era_names/1" do
      assert Localize.Calendar.calendar_eras(CldrEra, :en) ==
               Localize.Calendar.eras(:en, :gregorian)

      assert Localize.Calendar.calendar_eras(Calendar.ISO, :en) ==
               Localize.Calendar.eras(:en, :gregorian)
    end
  end
end
