defmodule Localize.Test.LadyDayCalendar do
  @moduledoc false

  # A calendar whose year turns on 25 March, as the Julian calendar's did in
  # England until 1752: within a month, and after the year's first. Its
  # months and days are `Calendar.ISO`'s, and a day before 25 March carries
  # the number of the year that began the March before. So the fields of two
  # dates do not say which is the earlier: 31 December 2024 is the day before
  # 1 January 2024, and 24 March 2024 the day before 25 March 2025. Quarters
  # are three months from the start of the year, the last running from
  # December to 24 March. Calendrical's `Calendrical.Julian.March25` is such
  # a calendar, and Localize cannot load it.
  use Localize.Test.StandInCalendar

  def valid_date?(year, month, day)
      when is_integer(year) and is_integer(month) and is_integer(day),
      do: Calendar.ISO.valid_date?(iso_year(year, month, day), month, day)

  def valid_date?(_year, _month, _day), do: false

  def naive_datetime_to_iso_days(year, month, day, hour, minute, second, microsecond) do
    Calendar.ISO.naive_datetime_to_iso_days(
      iso_year(year, month, day),
      month,
      day,
      hour,
      minute,
      second,
      microsecond
    )
  end

  def naive_datetime_from_iso_days(iso_days) do
    {iso_year, month, day, hour, minute, second, microsecond} =
      Calendar.ISO.naive_datetime_from_iso_days(iso_days)

    {numbered(iso_year, month, day), month, day, hour, minute, second, microsecond}
  end

  def shift_date(year, month, day, duration) do
    {iso_year, month, day} =
      Calendar.ISO.shift_date(iso_year(year, month, day), month, day, duration)

    {numbered(iso_year, month, day), month, day}
  end

  def day_of_week(year, month, day, starting_on),
    do: Calendar.ISO.day_of_week(iso_year(year, month, day), month, day, starting_on)

  # A month's days after the year has turned: March has 31 either side of it.
  def days_in_month(year, month), do: Calendar.ISO.days_in_month(iso_year(year, month, 25), month)

  def quarter_of_year(_year, 3, day) when day < 25, do: 4
  def quarter_of_year(_year, month, _day), do: div(Integer.mod(month - 3, 12), 3) + 1

  def year(year) do
    Date.range(
      %Date{year: year, month: 3, day: 25, calendar: __MODULE__},
      %Date{year: year, month: 3, day: 24, calendar: __MODULE__}
    )
  end

  defp iso_year(year, month, day) when {month, day} < {3, 25}, do: year + 1
  defp iso_year(year, _month, _day), do: year

  defp numbered(iso_year, month, day) when {month, day} < {3, 25}, do: iso_year - 1
  defp numbered(iso_year, _month, _day), do: iso_year
end

defmodule Localize.Test.NoYearZeroCalendar do
  @moduledoc false

  # `Calendar.ISO` with its years numbered as the Julian calendar numbers
  # them, with no year 0: the year before year 1 is year -1, ISO's year 0. A
  # year's number is then not always one more than the year before's.
  # Calendrical's `Calendrical.Julian` numbers its years this way, and
  # Localize cannot load it.
  use Localize.Test.StandInCalendar

  def valid_date?(year, month, day)
      when is_integer(year) and year != 0 and is_integer(month) and is_integer(day),
      do: Calendar.ISO.valid_date?(iso_year(year), month, day)

  def valid_date?(_year, _month, _day), do: false

  def naive_datetime_to_iso_days(year, month, day, hour, minute, second, microsecond) do
    Calendar.ISO.naive_datetime_to_iso_days(
      iso_year(year),
      month,
      day,
      hour,
      minute,
      second,
      microsecond
    )
  end

  def naive_datetime_from_iso_days(iso_days) do
    {iso_year, month, day, hour, minute, second, microsecond} =
      Calendar.ISO.naive_datetime_from_iso_days(iso_days)

    {numbered(iso_year), month, day, hour, minute, second, microsecond}
  end

  def shift_date(year, month, day, duration) do
    {iso_year, month, day} = Calendar.ISO.shift_date(iso_year(year), month, day, duration)
    {numbered(iso_year), month, day}
  end

  def day_of_week(year, month, day, starting_on),
    do: Calendar.ISO.day_of_week(iso_year(year), month, day, starting_on)

  def days_in_month(year, month), do: Calendar.ISO.days_in_month(iso_year(year), month)

  defp iso_year(year) when year < 0, do: year + 1
  defp iso_year(year), do: year

  defp numbered(iso_year) when iso_year <= 0, do: iso_year - 1
  defp numbered(iso_year), do: iso_year
end
