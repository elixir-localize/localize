defmodule Localize.DateTime.Week do
  @moduledoc false

  # The locale's week data where TR35 still asks for it: the numeric local
  # day of the week (`e`, `c`) and relative time's weeks count from the
  # locale's first day. Week numbers (`Y`, `w`, `W`) are the calendar's,
  # never the locale's. Days are numbered as in ISO 8601, from 1 (Monday)
  # to 7 (Sunday).

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
