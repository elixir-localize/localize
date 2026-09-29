defmodule Localize.DateTime.PartialDateEraTest do
  @moduledoc """
  The era of a partial date, and the year it shows.

  A partial date could be any day of its month, or of its year when it has
  no month, so it shows the era and the year those days agree on. Where a
  calendar's eras begin with its years they always agree, and a partial
  date must render as every whole date inside it does; the Gregorian sweep
  below checks exactly that, with the whole dates as the reference.

  Where an era begins mid-year they need not agree. The stand-in Japanese
  calendar takes its eras from CLDR's supplemental `calendarData` — Shōwa
  from 1926-12-25, Heisei from 1989-01-08, Reiwa from 2019-05-01 — and the
  expected strings apply `en`'s `ca-japanese` data by hand: `Gy` is "y G",
  `GyMMM` "MMM y G", and the abbreviated eras are "Shōwa", "Heisei" and
  "Reiwa". The stand-in Buddhist calendar has CLDR's one era, "BE".
  """

  use ExUnit.Case, async: true

  # Localize cannot load Calendrical's calendars, which depend on it. These
  # stand-ins name their CLDR calendar and answer `year_of_era/3` as CLDR's
  # era data does, taking the rest of their arithmetic from `Calendar.ISO`.
  defmodule Japanese do
    @moduledoc false

    @eras [{~D[2019-05-01], 236}, {~D[1989-01-08], 235}, {~D[1926-12-25], 234}]

    def cldr_calendar_type, do: :japanese

    def year_of_era(year, month, day) do
      date = Date.new!(year, month, day)
      {start, era} = Enum.find(@eras, fn {start, _era} -> Date.compare(date, start) != :lt end)
      {year - start.year + 1, era}
    end

    def calendar_year(year, month, day), do: year |> year_of_era(month, day) |> elem(0)

    defdelegate valid_date?(year, month, day), to: Calendar.ISO
    defdelegate days_in_month(year, month), to: Calendar.ISO
    defdelegate months_in_year(year), to: Calendar.ISO
    defdelegate date_to_string(year, month, day), to: Calendar.ISO
  end

  defmodule Buddhist do
    @moduledoc false

    def cldr_calendar_type, do: :buddhist
    def year_of_era(year, _month, _day), do: {year, 0}

    defdelegate valid_date?(year, month, day), to: Calendar.ISO
    defdelegate days_in_month(year, month), to: Calendar.ISO
    defdelegate months_in_year(year), to: Calendar.ISO
    defdelegate date_to_string(year, month, day), to: Calendar.ISO
  end

  @locales ~w(am ar bal be bn cy da de en en-AU es fa fi fr he hi hu it ja ko ky mr my pt ru th uk zh zh-Hant)a

  describe "a Gregorian partial date" do
    # Each format with the partial dates it can fill: a year alone, or a
    # year and a month. `th`'s long year carries its era.
    @formats [
      {:Gy, [:year, :year_and_month]},
      {:GyMMM, [:year_and_month]},
      {:GyMMMM, [:year_and_month]},
      {Localize.DateTime.SemanticSkeleton.semantic("Y", year_style: :with_era),
       [:year, :year_and_month]},
      {Localize.DateTime.SemanticSkeleton.semantic("YM", year_style: :with_era),
       [:year_and_month]},
      {Localize.DateTime.SemanticSkeleton.semantic("YM", length: :long), [:year_and_month]}
    ]

    # CLDR's `pt` gives `GyMMMM` as "MMMM 'de' Y G", with the week-based year
    # `Y` that only a whole date has, where every sibling format has `y`.
    test "renders its era and year as a whole date inside it does" do
      failures =
        for locale <- @locales,
            {format, shapes} <- @formats,
            {locale, format} != {:pt, :GyMMMM},
            shape <- shapes,
            year <- [2025, 1, 0, -1, -44],
            {partial, whole} = partial_and_whole(shape, year),
            partial_result = Localize.Date.to_string(partial, format: format, locale: locale),
            whole_result = Localize.Date.to_string(whole, format: format, locale: locale),
            not match?({:ok, _}, whole_result) or partial_result != whole_result do
          {locale, format, partial, partial_result, whole_result}
        end

      assert failures == [], inspect(Enum.take(failures, 5), pretty: true)
    end

    test "counts a year before the first as TR35 does" do
      assert Localize.Date.to_string(%{year: 0}, format: :y, locale: :en) == {:ok, "1"}
      assert Localize.Date.to_string(%{year: -1}, format: :y, locale: :en) == {:ok, "2"}
      assert Localize.Date.to_string(%{year: 0}, format: :Gy, locale: :en) == {:ok, "1 BC"}

      assert Localize.Date.to_string(%{year: -1, month: 3}, format: :GyMMM, locale: :en) ==
               {:ok, "Mar 2 BC"}
    end

    test "the era part names it" do
      {:ok, parts} = Localize.Date.to_parts(%{year: 2025, month: 1}, format: :GyMMM, locale: :en)
      assert %{type: :era, value: "AD"} in parts
    end
  end

  describe "an era that begins mid-year" do
    test "is settled by the fields of a date inside one era" do
      assert format(%{year: 2020}, :Gy) == {:ok, "2 Reiwa"}
      assert format(%{year: 2019, month: 4}, :GyMMM) == {:ok, "Apr 31 Heisei"}
      assert format(%{year: 2019, month: 5}, :GyMMM) == {:ok, "May 1 Reiwa"}
      assert format(%{year: 1989, month: 1, day: 7}, "MMM d, y G") == {:ok, "Jan 7, 64 Shōwa"}
      assert format(%{year: 1989, month: 1, day: 8}, "MMM d, y G") == {:ok, "Jan 8, 1 Heisei"}
    end

    test "asks for the fields that settle a date spanning two" do
      assert {:error, %Localize.DateTimeInvalidInputError{missing: [:month, :day]}} =
               format(%{year: 2019}, :Gy)

      assert {:error, %Localize.DateTimeInvalidInputError{missing: [:day]}} =
               format(%{year: 1989, month: 1}, :GyMMM)
    end

    # A literal pattern, since CLDR's Japanese `y` format is "y G".
    test "asks the same of the year of era it shows, era or not" do
      assert format(%{year: 2020}, "y") == {:ok, "2"}

      assert {:error, %Localize.DateTimeInvalidInputError{missing: [:month, :day]}} =
               format(%{year: 2019}, "y")
    end
  end

  describe "a calendar whose eras begin with its years" do
    test "shows its own era for a partial date" do
      date = %{year: 2568, month: 1, calendar: Buddhist}

      assert Localize.Date.to_string(date, format: :GyMMM, locale: :en) ==
               {:ok, "Jan 2568 BE"}
    end
  end

  describe "Localize.Calendar.localize/3" do
    test "names the era of a partial date" do
      assert Localize.Calendar.localize(%{year: 2025}, :era) == {:ok, "Anno Domini"}
      assert Localize.Calendar.localize(%{year: 0}, :era) == {:ok, "Before Christ"}

      assert Localize.Calendar.localize(%{year: 2019, month: 5, calendar: Japanese}, :era,
               locale: :en
             ) == {:ok, "Reiwa"}
    end

    test "returns an error for a partial date whose days span two eras" do
      assert {:error, %Localize.DateTimeInvalidInputError{format: "G", missing: [:month, :day]}} =
               Localize.Calendar.localize(%{year: 2019, calendar: Japanese}, :era)
    end
  end

  defp partial_and_whole(:year, year), do: {%{year: year}, Date.new!(year, 6, 15)}

  defp partial_and_whole(:year_and_month, year),
    do: {%{year: year, month: 3}, Date.new!(year, 3, 15)}

  defp format(date, format) do
    Localize.Date.to_string(Map.put(date, :calendar, Japanese), format: format, locale: :en)
  end
end
