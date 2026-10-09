defmodule Localize.Test.CountedMonthCalendar do
  @moduledoc false

  # A calendar whose months are counted from the year's first day, 25 March,
  # as `Calendrical.Julian.March25` counts them: its month 1 day 1 is the day
  # the Julian calendar names 25 March, so a date's month and day fields are
  # its place in the counted month and not the month and day that name it.
  # Thirteen counted months hold the year, with March at each end of it:
  # month 1 is 25 to 31 March, months 2 to 12 are April to February, and
  # month 13 is 1 to 24 March.
  #
  # `cardinal_month/1` and `cardinal_day/3` give the name, which the
  # formatter's `M` and `d` write, and `date_from_julian_date/3` reads a name
  # back, which the parser asks of a calendar that exports it. Localize does
  # not depend on Calendrical, so this stands in for one of its calendars.

  use Localize.Test.StandInCalendar

  @named_month %{
    1 => 3,
    2 => 4,
    3 => 5,
    4 => 6,
    5 => 7,
    6 => 8,
    7 => 9,
    8 => 10,
    9 => 11,
    10 => 12,
    11 => 1,
    12 => 2,
    13 => 3
  }

  @months_after_the_year_turns [11, 12, 13]

  def months_in_year(_year), do: 13

  def cardinal_month(month), do: Map.fetch!(@named_month, month)

  # The day the Julian calendar names: month 1 counts from its 25th, month 13
  # from its 1st, and the months between hold the named month whole.
  def cardinal_day(_year, 1, day), do: day + 24
  def cardinal_day(_year, _month, day), do: day

  # The inverse of `cardinal_month/1` and `cardinal_day/3` together: the date
  # named by a month and day of the Julian calendar in a year of this one.
  #
  # The year is this calendar's own and is not shifted. A date is written with
  # the year it belongs to here — 5 January of the year that began in March
  # 1750 is written "January 5, 1750", as Old Style numbering has it — so the
  # year reaches this callback as the calendar's own while the month and day
  # reach it as the names `cardinal_month/1` and `cardinal_day/3` gave.
  def date_from_julian_date(year, 3, day) when day >= 25, do: {year, 1, day - 24}
  def date_from_julian_date(year, 3, day), do: {year, 13, day}
  def date_from_julian_date(year, month, day) when month >= 4, do: {year, month - 2, day}
  def date_from_julian_date(year, month, day), do: {year, month + 10, day}

  def days_in_month(_year, 1), do: 7
  def days_in_month(_year, 13), do: 24

  def days_in_month(year, month),
    do: Calendar.ISO.days_in_month(named_year(year, month), cardinal_month(month))

  def valid_date?(year, month, day)
      when is_integer(year) and is_integer(month) and is_integer(day) and month in 1..13 and
             day >= 1,
      do: day <= days_in_month(year, month)

  def valid_date?(_year, _month, _day), do: false

  def naive_datetime_to_iso_days(year, month, day, hour, minute, second, microsecond) do
    {named_year, named_month, named_day} = named_date(year, month, day)

    Calendar.ISO.naive_datetime_to_iso_days(
      named_year,
      named_month,
      named_day,
      hour,
      minute,
      second,
      microsecond
    )
  end

  def naive_datetime_from_iso_days(iso_days) do
    {named_year, named_month, named_day, hour, minute, second, microsecond} =
      Calendar.ISO.naive_datetime_from_iso_days(iso_days)

    {year, month, day} = date_from_julian_date(named_year, named_month, named_day)
    {year, month, day, hour, minute, second, microsecond}
  end

  # The Gregorian year a counted month falls in: January, February and the
  # March that closes the year fall in the year after the one the counted
  # year is named for.
  defp named_year(year, month) when month in @months_after_the_year_turns, do: year + 1
  defp named_year(year, _month), do: year

  defp named_date(year, month, day),
    do: {named_year(year, month), cardinal_month(month), cardinal_day(year, month, day)}
end
