defmodule Localize.Test.ThirteenMonthCalendar do
  @moduledoc false

  # A calendar whose every year has thirteen months of 28 days, 364 days in
  # all, counted on from an arbitrary day: a year is not twelve of its
  # months, as a Hebrew leap year is not. Localize cannot load Calendrical's
  # calendars, so this stands in for one.
  use Localize.Test.StandInCalendar

  @epoch 730_000
  @months_in_year 13
  @days_in_month 28
  @days_in_year @months_in_year * @days_in_month

  def months_in_year(_year), do: @months_in_year
  def days_in_month(_year, _month), do: @days_in_month

  def valid_date?(year, month, day)
      when is_integer(year) and is_integer(month) and is_integer(day),
      do: month in 1..@months_in_year and day in 1..@days_in_month

  def valid_date?(_year, _month, _day), do: false

  def naive_datetime_to_iso_days(year, month, day, hour, minute, second, microsecond) do
    {days(year, month, day), Calendar.ISO.time_to_day_fraction(hour, minute, second, microsecond)}
  end

  def naive_datetime_from_iso_days({days, fraction}) do
    {year, month, day} = date(days)
    {hour, minute, second, microsecond} = Calendar.ISO.time_from_day_fraction(fraction)
    {year, month, day, hour, minute, second, microsecond}
  end

  # Years and months move the month, thirteen to a year, and every month has
  # the day; weeks and days are then counted on.
  def shift_date(year, month, day, %Duration{year: years, month: months, week: weeks, day: days}) do
    months_on = (year + years) * @months_in_year + month - 1 + months
    year_on = Integer.floor_div(months_on, @months_in_year)
    month_on = Integer.mod(months_on, @months_in_year) + 1

    date(days(year_on, month_on, day) + weeks * 7 + days)
  end

  def day_of_week(year, month, day, starting_on) do
    {iso_year, iso_month, iso_day} = Calendar.ISO.date_from_iso_days(days(year, month, day))
    Calendar.ISO.day_of_week(iso_year, iso_month, iso_day, starting_on)
  end

  def quarter_of_year(_year, month, _day), do: min(div(month - 1, 3) + 1, 4)

  defp days(year, month, day),
    do: @epoch + (year - 1) * @days_in_year + (month - 1) * @days_in_month + day - 1

  defp date(days) do
    days = days - @epoch
    day_of_year = Integer.mod(days, @days_in_year)

    {Integer.floor_div(days, @days_in_year) + 1, div(day_of_year, @days_in_month) + 1,
     rem(day_of_year, @days_in_month) + 1}
  end
end
