defmodule Localize.Calendar.Gregorian do
  @moduledoc """
  A proleptic Gregorian calendar intended to be plug-compatible
  with `Calendar.ISO` but with additional CLDR calendar metadata.

  When `Localize.Calendar.localize/3` receives a date using
  `Calendar.ISO`, it treats it as equivalent to this calendar
  for localisation purposes.

  This module delegates all `Calendar` behaviour callbacks to
  `Calendar.ISO` and adds `cldr_calendar_type/0` so that
  locale data lookups resolve to the `:gregorian` calendar.

  """

  @behaviour Calendar

  @doc """
  Returns the CLDR calendar type.

  ### Returns

  * `:gregorian`

  """
  @spec cldr_calendar_type() :: :gregorian
  def cldr_calendar_type, do: :gregorian

  @doc """
  Returns the calendar base type.

  ### Returns

  * `:month`

  """
  @spec calendar_base() :: :month
  def calendar_base, do: :month

  # ── Calendar behaviour callbacks ────────────────────────────────

  @impl Calendar
  defdelegate date_to_string(year, month, day), to: Calendar.ISO

  @impl Calendar
  defdelegate datetime_to_string(
                year,
                month,
                day,
                hour,
                minute,
                second,
                microsecond,
                time_zone,
                zone_abbr,
                utc_offset,
                std_offset
              ),
              to: Calendar.ISO

  @impl Calendar
  defdelegate day_of_era(year, month, day), to: Calendar.ISO

  @impl Calendar
  defdelegate day_of_week(year, month, day, starting_on), to: Calendar.ISO

  @impl Calendar
  defdelegate day_of_year(year, month, day), to: Calendar.ISO

  @impl Calendar
  defdelegate day_rollover_relative_to_midnight_utc(), to: Calendar.ISO

  @impl Calendar
  defdelegate days_in_month(year, month), to: Calendar.ISO

  @impl Calendar
  defdelegate iso_days_to_beginning_of_day(iso_days), to: Calendar.ISO

  @impl Calendar
  defdelegate iso_days_to_end_of_day(iso_days), to: Calendar.ISO

  @impl Calendar
  defdelegate leap_year?(year), to: Calendar.ISO

  @impl Calendar
  defdelegate months_in_year(year), to: Calendar.ISO

  @impl Calendar
  defdelegate naive_datetime_from_iso_days(iso_days), to: Calendar.ISO

  @impl Calendar
  defdelegate naive_datetime_to_iso_days(year, month, day, hour, minute, second, microsecond),
    to: Calendar.ISO

  @impl Calendar
  defdelegate naive_datetime_to_string(year, month, day, hour, minute, second, microsecond),
    to: Calendar.ISO

  @impl Calendar
  defdelegate parse_date(string), to: Calendar.ISO

  @impl Calendar
  defdelegate parse_naive_datetime(string), to: Calendar.ISO

  @impl Calendar
  defdelegate parse_time(string), to: Calendar.ISO

  @impl Calendar
  defdelegate parse_utc_datetime(string), to: Calendar.ISO

  @impl Calendar
  defdelegate quarter_of_year(year, month, day), to: Calendar.ISO

  @impl Calendar
  defdelegate shift_date(year, month, day, duration), to: Calendar.ISO

  @impl Calendar
  defdelegate shift_naive_datetime(
                year,
                month,
                day,
                hour,
                minute,
                second,
                microsecond,
                duration
              ),
              to: Calendar.ISO

  @impl Calendar
  defdelegate shift_time(hour, minute, second, microsecond, duration), to: Calendar.ISO

  @impl Calendar
  defdelegate time_from_day_fraction(day_fraction), to: Calendar.ISO

  @impl Calendar
  defdelegate time_to_day_fraction(hour, minute, second, microsecond), to: Calendar.ISO

  @impl Calendar
  defdelegate time_to_string(hour, minute, second, microsecond), to: Calendar.ISO

  @impl Calendar
  defdelegate valid_date?(year, month, day), to: Calendar.ISO

  @impl Calendar
  defdelegate valid_time?(hour, minute, second, microsecond), to: Calendar.ISO

  @impl Calendar
  defdelegate year_of_era(year, month, day), to: Calendar.ISO

  # ── Date range helpers ──────────────────────────────────────────

  @doc """
  Returns a `Date.Range` spanning the given year.

  ### Arguments

  * `year` is an integer year.

  ### Returns

  * A `Date.Range` from January 1 to December 31.

  ### Examples

      iex> Localize.Calendar.Gregorian.year(2024)
      Date.range(~D[2024-01-01], ~D[2024-12-31])

  """
  @spec year(Calendar.year()) :: Date.Range.t()
  def year(year) do
    first = %Date{year: year, month: 1, day: 1, calendar: __MODULE__}
    last_day = if leap_year?(year), do: 366, else: 365
    last = Date.add(first, last_day - 1)
    Date.range(first, last)
  end

  @doc """
  Returns a `Date.Range` spanning the given quarter.

  ### Arguments

  * `year` is an integer year.

  * `quarter` is an integer from 1 to 4.

  ### Returns

  * A `Date.Range` for the quarter.

  ### Examples

      iex> Localize.Calendar.Gregorian.quarter(2024, 2)
      Date.range(~D[2024-04-01], ~D[2024-06-30])

  """
  @spec quarter(Calendar.year(), 1..4) :: Date.Range.t()
  def quarter(year, quarter) when quarter in 1..4 do
    first_month = (quarter - 1) * 3 + 1
    last_month = first_month + 2
    first = %Date{year: year, month: first_month, day: 1, calendar: __MODULE__}
    last_day = days_in_month(year, last_month)
    last = %Date{year: year, month: last_month, day: last_day, calendar: __MODULE__}
    Date.range(first, last)
  end

  @doc """
  Returns a `Date.Range` spanning the given month.

  ### Arguments

  * `year` is an integer year.

  * `month` is an integer from 1 to 12.

  ### Returns

  * A `Date.Range` for the month.

  ### Examples

      iex> Localize.Calendar.Gregorian.month(2024, 2)
      Date.range(~D[2024-02-01], ~D[2024-02-29])

  """
  @spec month(Calendar.year(), Calendar.month()) :: Date.Range.t()
  def month(year, month) when month in 1..12 do
    first = %Date{year: year, month: month, day: 1, calendar: __MODULE__}
    last_day = days_in_month(year, month)
    last = %Date{year: year, month: month, day: last_day, calendar: __MODULE__}
    Date.range(first, last)
  end

  @doc """
  Returns the number of days in the given year.

  ### Arguments

  * `year` is an integer year.

  ### Returns

  * 365 for a normal year or 366 for a leap year.

  ### Examples

      iex> Localize.Calendar.Gregorian.days_in_year(2024)
      366

      iex> Localize.Calendar.Gregorian.days_in_year(2023)
      365

  """
  @spec days_in_year(Calendar.year()) :: 365 | 366
  def days_in_year(year) do
    if leap_year?(year), do: 366, else: 365
  end
end
