defmodule Localize.DateTime.Week do
  @moduledoc false

  # Locale week rules shared by the formatter and the parser. Per TR35,
  # weeks begin on the locale's first day of the week, and week 1 is the
  # first week holding at least the locale's minimum number of days of the
  # new year. Days are numbered as in ISO 8601, from 1 (Monday) to 7
  # (Sunday).

  @doc """
  Returns the week configuration for a locale.

  ### Arguments

  * `locale` is a locale identifier or a `t:Localize.LanguageTag.t/0`.

  ### Returns

  * `{first_day, min_days}`, where `first_day` is the day the week starts
    on and `min_days` is the minimum number of days of the new year that
    week 1 holds. The CLDR world default, `{1, 1}`, applies when the
    locale's territory cannot be resolved.

  ### Examples

      iex> Localize.DateTime.Week.config(:en)
      {7, 1}

      iex> Localize.DateTime.Week.config(:de)
      {1, 4}

  """
  @spec config(Localize.LanguageTag.t() | atom() | String.t()) :: {1..7, 1..7}
  def config(locale) do
    first_day =
      case Localize.Calendar.first_day_for_locale(locale) do
        day when is_integer(day) -> day
        _ -> 1
      end

    min_days =
      case Localize.Calendar.min_days_for_locale(locale) do
        days when is_integer(days) -> days
        _ -> 1
      end

    {first_day, min_days}
  end

  @doc """
  Returns the Gregorian day number on which week 1 of a year starts.

  ### Arguments

  * `year` is the week-based year.

  * `first_day` is the day the week starts on, from 1 (Monday) to 7.

  * `min_days` is the minimum number of days of the new year that week 1
    holds.

  ### Returns

  * The day number, as counted by `:calendar.date_to_gregorian_days/1`.

  ### Examples

      iex> 2027
      ...> |> Localize.DateTime.Week.week_one_start(7, 1)
      ...> |> :calendar.gregorian_days_to_date()
      {2026, 12, 27}

  """
  @spec week_one_start(non_neg_integer(), 1..7, 1..7) :: integer()
  def week_one_start(year, first_day, min_days) do
    jan1 = :calendar.date_to_gregorian_days({year, 1, 1})
    offset = rem(:calendar.day_of_the_week({year, 1, 1}) - first_day + 7, 7)

    if 7 - offset >= min_days do
      jan1 - offset
    else
      jan1 - offset + 7
    end
  end

  @doc """
  Returns the date of a day in a week of a week-based year.

  ### Arguments

  * `week_year` is the week-based year.

  * `week` is the week number, from 1 to 53.

  * `day_of_week` is the day, from 1 (Monday) to 7, or `nil` for the first
    day of the week.

  * `config` is a `{first_day, min_days}` week configuration, as returned
    by `config/1`.

  ### Returns

  * `{:ok, date}`, a `t:Date.t/0` in `Calendar.ISO`, or

  * `:error` when an argument is out of range.

  ### Examples

      iex> Localize.DateTime.Week.date_from_week(2027, 1, nil, {7, 1})
      {:ok, ~D[2026-12-27]}

      iex> Localize.DateTime.Week.date_from_week(2027, 1, nil, {1, 4})
      {:ok, ~D[2027-01-04]}

  """
  @spec date_from_week(integer(), integer(), 1..7 | nil, {1..7, 1..7}) ::
          {:ok, Date.t()} | :error
  def date_from_week(week_year, week, day_of_week, {first_day, min_days})
      when is_integer(week_year) and week_year >= 1 and week in 1..53 and
             (is_nil(day_of_week) or day_of_week in 1..7) do
    offset = if day_of_week, do: rem(day_of_week - first_day + 7, 7), else: 0
    days = week_one_start(week_year, first_day, min_days) + (week - 1) * 7 + offset
    {year, month, day} = :calendar.gregorian_days_to_date(days)

    case Date.new(year, month, day) do
      {:ok, date} -> {:ok, date}
      {:error, _reason} -> :error
    end
  end

  def date_from_week(_week_year, _week, _day_of_week, _config), do: :error

  @doc """
  Converts a locale-relative day-of-week number to the ISO day number.

  CLDR's numeric local day of week (the `e` and `c` fields) counts from
  the locale's first day of the week, so in `en`, where weeks start on
  Sunday, 1 is Sunday.

  ### Arguments

  * `local_day` is the locale-relative day, from 1 to 7.

  * `first_day` is the day the locale's week starts on, from 1 (Monday)
    to 7.

  ### Returns

  * The day, from 1 (Monday) to 7 (Sunday).

  ### Examples

      iex> Localize.DateTime.Week.iso_day_of_week(1, 7)
      7

      iex> Localize.DateTime.Week.iso_day_of_week(2, 7)
      1

  """
  @spec iso_day_of_week(1..7, 1..7) :: 1..7
  def iso_day_of_week(local_day, first_day) when local_day in 1..7 and first_day in 1..7 do
    rem(first_day + local_day - 2, 7) + 1
  end

  @doc """
  Converts an ISO day number to the locale-relative day-of-week number.

  This is the inverse of `iso_day_of_week/2`.

  ### Arguments

  * `iso_day` is the day, from 1 (Monday) to 7 (Sunday).

  * `first_day` is the day the locale's week starts on, from 1 (Monday)
    to 7.

  ### Returns

  * The locale-relative day, from 1 to 7.

  ### Examples

      iex> Localize.DateTime.Week.local_day_of_week(6, 7)
      7

      iex> Localize.DateTime.Week.local_day_of_week(6, 1)
      6

  """
  @spec local_day_of_week(1..7, 1..7) :: 1..7
  def local_day_of_week(iso_day, first_day) when iso_day in 1..7 and first_day in 1..7 do
    rem(iso_day - first_day + 7, 7) + 1
  end
end
