defmodule Localize.Calendar do
  @moduledoc """
  Calendar localization functions for retrieving locale-specific
  names for eras, months, days, quarters, and day periods.

  Also provides territory-based week preferences (first day of week,
  weekend days) and functions to produce localized date part strings
  from `Date`, `DateTime`, and `NaiveDateTime` structs.

  Calendar locale data is accessed via `Localize.Locale.get/2` using
  the path `[:dates, :calendars, calendar_type]`.

  """

  @default_calendar_type :gregorian

  @acceptable_calendars [
    :gregorian,
    :persian,
    :coptic,
    :ethiopic,
    :ethiopic_amete_alem,
    :chinese,
    :japanese,
    :dangi
  ]

  @type part :: :era | :quarter | :month | :day_of_week | :days_of_week | :am_pm | :day_periods
  @type format :: :wide | :abbreviated | :narrow
  @type type :: :format | :stand_alone

  @days 1..7 |> Enum.to_list()
  @the_world :"001"

  # ── Locale data access ─────────────────────────────────────────

  @doc """
  Returns the era names for a locale and calendar type.

  ### Arguments

  * `locale` is a locale identifier atom, string, or
    `t:Localize.LanguageTag.t/0`.

  * `calendar_type` is a CLDR calendar type atom. The default
    is `:gregorian`.

  ### Returns

  * `{:ok, era_data}` where `era_data` is a map keyed by format
    (`:abbreviated`, `:wide`, `:narrow`) and era index.

  * `{:error, exception}` if the locale or calendar is not found.

  ### Examples

      iex> {:ok, eras} = Localize.Calendar.eras(:en)
      iex> get_in(eras, [:abbreviated, 1])
      "AD"

  """
  @spec eras(Localize.locale(), atom()) :: {:ok, map()} | {:error, Exception.t()}
  def eras(locale, calendar_type \\ @default_calendar_type) do
    get_calendar_data(locale, calendar_type, :eras)
  end

  @doc """
  Returns the quarter names for a locale and calendar type.

  ### Arguments

  * `locale` is a locale identifier atom, string, or
    `t:Localize.LanguageTag.t/0`.

  * `calendar_type` is a CLDR calendar type atom. The default
    is `:gregorian`.

  ### Returns

  * `{:ok, quarter_data}` where `quarter_data` is a map keyed
    by type (`:format`, `:stand_alone`), then format, then quarter
    number.

  * `{:error, exception}` if the locale or calendar is not found.

  ### Examples

      iex> {:ok, quarters} = Localize.Calendar.quarters(:en)
      iex> get_in(quarters, [:format, :abbreviated, 2])
      "Q2"

  """
  @spec quarters(Localize.locale(), atom()) :: {:ok, map()} | {:error, Exception.t()}
  def quarters(locale, calendar_type \\ @default_calendar_type) do
    get_calendar_data(locale, calendar_type, :quarters)
  end

  @doc """
  Returns the month names for a locale and calendar type.

  ### Arguments

  * `locale` is a locale identifier atom, string, or
    `t:Localize.LanguageTag.t/0`.

  * `calendar_type` is a CLDR calendar type atom. The default
    is `:gregorian`.

  ### Returns

  * `{:ok, month_data}` where `month_data` is a map keyed by
    type (`:format`, `:stand_alone`), then format, then month
    number.

  * `{:error, exception}` if the locale or calendar is not found.

  ### Examples

      iex> {:ok, months} = Localize.Calendar.months(:en)
      iex> get_in(months, [:format, :wide, 6])
      "June"

  """
  @spec months(Localize.locale(), atom()) :: {:ok, map()} | {:error, Exception.t()}
  def months(locale, calendar_type \\ @default_calendar_type) do
    get_calendar_data(locale, calendar_type, :months)
  end

  @doc """
  Returns the day names for a locale and calendar type.

  ### Arguments

  * `locale` is a locale identifier atom, string, or
    `t:Localize.LanguageTag.t/0`.

  * `calendar_type` is a CLDR calendar type atom. The default
    is `:gregorian`.

  ### Returns

  * `{:ok, day_data}` where `day_data` is a map keyed by type
    (`:format`, `:stand_alone`), then format, then ISO day number
    (1 = Monday through 7 = Sunday).

  * `{:error, exception}` if the locale or calendar is not found.

  ### Examples

      iex> {:ok, days} = Localize.Calendar.days(:en)
      iex> get_in(days, [:format, :wide, 6])
      "Saturday"

  """
  @spec days(Localize.locale(), atom()) :: {:ok, map()} | {:error, Exception.t()}
  def days(locale, calendar_type \\ @default_calendar_type) do
    get_calendar_data(locale, calendar_type, :days)
  end

  @doc """
  Returns the day period names for a locale and calendar type.

  Day periods include AM/PM indicators and may include
  additional periods like noon, midnight, morning, afternoon,
  evening, and night.

  ### Arguments

  * `locale` is a locale identifier atom, string, or
    `t:Localize.LanguageTag.t/0`.

  * `calendar_type` is a CLDR calendar type atom. The default
    is `:gregorian`.

  ### Returns

  * `{:ok, day_period_data}` where `day_period_data` is a map
    keyed by type, format, period, and variant.

  * `{:error, exception}` if the locale or calendar is not found.

  ### Examples

      iex> {:ok, periods} = Localize.Calendar.day_periods(:en)
      iex> get_in(periods, [:format, :abbreviated, :am, :default])
      "AM"

  """
  @spec day_periods(Localize.locale(), atom()) :: {:ok, map()} | {:error, Exception.t()}
  def day_periods(locale, calendar_type \\ @default_calendar_type) do
    get_calendar_data(locale, calendar_type, :day_periods)
  end

  @doc """
  Returns the acceptable CLDR calendar types.

  ### Returns

  * A list of atoms.

  """
  @spec acceptable_calendars() :: [atom()]
  def acceptable_calendars, do: @acceptable_calendars

  # ── Localize date parts ─────────────────────────────────────────

  @doc """
  Returns a localized string for a part of a date or time.

  ### Arguments

  * `datetime` is any `t:Date.t/0`, `t:DateTime.t/0`, or
    `t:NaiveDateTime.t/0`.

  * `part` is one of `:era`, `:quarter`, `:month`,
    `:day_of_week`, `:days_of_week`, or `:am_pm`.

  * `options` is a keyword list of options. The default is `[]`.

  ### Options

  * `:locale` is a locale identifier. The default is `:en`.

  * `:format` is one of `:wide`, `:abbreviated`, or `:narrow`.
    The default is `:abbreviated`.

  * `:type` is one of `:format` or `:stand_alone`. The default
    is `:format`.

  * `:era` — if set to `:variant`, uses variant era names
    (e.g., "CE" instead of "AD" in English).

  * `:am_pm` — if set to `:variant`, uses variant AM/PM names
    (e.g., "am"/"pm" instead of "AM"/"PM" in English).

  ### Returns

  * A string representing the localized date part.

  * A list of `{day_number, day_name}` tuples when `part`
    is `:days_of_week`.

  * `{:error, exception}` if the part cannot be localized.

  ### Examples

      iex> Localize.Calendar.localize(~D[2019-06-01], :month)
      "Jun"

      iex> Localize.Calendar.localize(~D[2019-06-01], :month, format: :wide)
      "June"

      iex> Localize.Calendar.localize(~D[2019-06-01], :day_of_week)
      "Sat"

      iex> Localize.Calendar.localize(~D[2019-01-01], :era)
      "AD"

      iex> Localize.Calendar.localize(~D[2019-01-01], :era, era: :variant)
      "CE"

      iex> Localize.Calendar.localize(~D[2019-01-01], :quarter)
      "Q1"

  """
  def localize(datetime, part, options \\ [])

  def localize(datetime, part, options) do
    locale = Keyword.get(options, :locale, :en)
    type = Keyword.get(options, :type, :format)
    format = Keyword.get(options, :format, :abbreviated)
    calendar_type = calendar_type_from(datetime)

    with {:ok, locale_id} <- resolve_locale_id(locale) do
      do_localize(datetime, part, type, format, locale_id, calendar_type, options)
    end
  end

  defp do_localize(datetime, :era, _type, format, locale_id, calendar_type, options) do
    variant? = options[:era] == :variant

    with {:ok, eras} <- get_calendar_data_raw(locale_id, calendar_type, :eras) do
      {_, era} = day_of_era(datetime)
      era_key = if variant?, do: -era - 1, else: era
      get_in(eras, [format, era_key])
    end
  end

  defp do_localize(datetime, :quarter, type, format, locale_id, calendar_type, _options) do
    with {:ok, quarters} <- get_calendar_data_raw(locale_id, calendar_type, :quarters) do
      quarter = quarter_of_year(datetime)
      get_in(quarters, [type, format, quarter])
    end
  end

  defp do_localize(datetime, :month, type, format, locale_id, calendar_type, _options) do
    with {:ok, months} <- get_calendar_data_raw(locale_id, calendar_type, :months) do
      month = month_of_year(datetime)
      get_in(months, [type, format, month])
    end
  end

  defp do_localize(datetime, :day_of_week, type, format, locale_id, calendar_type, _options) do
    with {:ok, days} <- get_calendar_data_raw(locale_id, calendar_type, :days) do
      day = iso_day_of_week(datetime)
      get_in(days, [type, format, day])
    end
  end

  defp do_localize(datetime, :days_of_week, type, format, locale_id, calendar_type, _options) do
    with {:ok, days} <- get_calendar_data_raw(locale_id, calendar_type, :days) do
      for day <- @days do
        day_name = get_in(days, [type, format, day])
        {day, day_name}
      end
    end
  end

  defp do_localize(%{hour: hour} = _time, :am_pm, type, format, locale_id, calendar_type, options) do
    with {:ok, periods} <- get_calendar_data_raw(locale_id, calendar_type, :day_periods) do
      am_pm = if hour < 12 or rem(hour, 24) < 12, do: :am, else: :pm
      preference = options[:am_pm] || options[:period]
      default_or_variant = if preference == :variant, do: :variant, else: :default
      am_pm_data = get_in(periods, [type, format, am_pm])

      if is_map(am_pm_data) do
        Map.get(am_pm_data, default_or_variant) || Map.get(am_pm_data, :default)
      else
        am_pm_data
      end
    end
  end

  defp do_localize(_datetime, :am_pm, _type, _format, _locale_id, _calendar_type, _options) do
    {:error,
     Localize.InvalidValueError.exception(
       value: nil,
       expected: "a map with an :hour key",
       context: "Localize.Calendar.localize/3"
     )}
  end

  # ── strftime options ────────────────────────────────────────────

  @doc """
  Returns a keyword list of options for use with
  `Calendar.strftime/3`.

  The returned keyword list contains callback functions that
  produce localized month names, day names, and AM/PM indicators.

  ### Arguments

  * `options` is a keyword list.

  ### Options

  * `:locale` is a locale identifier. The default is `:en`.

  * `:calendar_type` is a CLDR calendar type atom. The default
    is `:gregorian`.

  ### Returns

  * A keyword list with `:am_pm_names`, `:month_names`,
    `:abbreviated_month_names`, `:day_of_week_names`, and
    `:abbreviated_day_of_week_names` keys.

  ### Examples

      iex> options = Localize.Calendar.strftime_options!(locale: :en)
      iex> options[:month_names].(6)
      "June"

      iex> options = Localize.Calendar.strftime_options!(locale: :de)
      iex> options[:abbreviated_day_of_week_names].(1)
      "Mo."

  """
  @spec strftime_options!(Keyword.t()) :: Keyword.t()
  def strftime_options!(options \\ []) do
    locale = Keyword.get(options, :locale, :en)
    calendar_type = Keyword.get(options, :calendar_type, @default_calendar_type)

    with {:ok, locale_id} <- resolve_locale_id(locale),
         {:ok, months_data} <- get_calendar_data_raw(locale_id, calendar_type, :months),
         {:ok, days_data} <- get_calendar_data_raw(locale_id, calendar_type, :days),
         {:ok, periods_data} <- get_calendar_data_raw(locale_id, calendar_type, :day_periods) do
      [
        am_pm_names: fn am_pm ->
          am_pm_map = get_in(periods_data, [:format, :abbreviated, am_pm])

          if is_map(am_pm_map) do
            Map.get(am_pm_map, :default, "")
          else
            am_pm_map || ""
          end
        end,
        month_names: fn month ->
          get_in(months_data, [:format, :wide, month])
        end,
        abbreviated_month_names: fn month ->
          get_in(months_data, [:format, :abbreviated, month])
        end,
        day_of_week_names: fn day ->
          get_in(days_data, [:format, :wide, day])
        end,
        abbreviated_day_of_week_names: fn day ->
          get_in(days_data, [:format, :abbreviated, day])
        end
      ]
    else
      {:error, exception} -> raise exception
    end
  end

  # ── Territory preferences ───────────────────────────────────────

  @week_info Localize.SupplementalData.weeks()

  @doc """
  Returns the first day of the week for a territory.

  Day numbers follow ISO 8601: 1 = Monday through 7 = Sunday.

  ### Arguments

  * `territory` is a territory atom (e.g., `:US`, `:GB`).

  ### Returns

  * An integer from 1 to 7.

  * `{:error, exception}` if the territory is not known.

  ### Examples

      iex> Localize.Calendar.first_day_for_territory(:US)
      7

      iex> Localize.Calendar.first_day_for_territory(:GB)
      1

  """
  @spec first_day_for_territory(atom()) :: integer() | {:error, Exception.t()}
  def first_day_for_territory(territory) when is_atom(territory) do
    case get_in(@week_info, [:first_day, territory]) do
      nil ->
        get_in(@week_info, [:first_day, @the_world]) || 1

      day ->
        day
    end
  end

  @doc """
  Returns the minimum days in the first week of the year
  for a territory.

  ### Arguments

  * `territory` is a territory atom.

  ### Returns

  * An integer from 1 to 7.

  ### Examples

      iex> Localize.Calendar.min_days_for_territory(:US)
      1

      iex> Localize.Calendar.min_days_for_territory(:GB)
      4

  """
  @spec min_days_for_territory(atom()) :: integer()
  def min_days_for_territory(territory) when is_atom(territory) do
    case get_in(@week_info, [:min_days, territory]) do
      nil ->
        get_in(@week_info, [:min_days, @the_world]) || 1

      days ->
        days
    end
  end

  @doc """
  Returns the weekend days for a territory as a list
  of ISO day-of-week numbers.

  ### Arguments

  * `territory` is a territory atom.

  ### Returns

  * A list of integers from 1 to 7.

  ### Examples

      iex> Localize.Calendar.weekend(:US)
      [6, 7]

      iex> Localize.Calendar.weekend(:IL)
      [5, 6]

  """
  @spec weekend(atom()) :: [integer()]
  def weekend(territory) when is_atom(territory) do
    starts =
      get_in(@week_info, [:weekend_start, territory]) ||
        get_in(@week_info, [:weekend_start, @the_world]) || 6

    ends =
      get_in(@week_info, [:weekend_end, territory]) ||
        get_in(@week_info, [:weekend_end, @the_world]) || 7

    Enum.to_list(starts..ends)
  end

  @doc """
  Returns the weekday numbers for a territory as a list
  of ISO day-of-week numbers.

  ### Arguments

  * `territory` is a territory atom.

  ### Returns

  * A list of integers from 1 to 7.

  ### Examples

      iex> Localize.Calendar.weekdays(:US)
      [1, 2, 3, 4, 5]

  """
  @spec weekdays(atom()) :: [integer()]
  def weekdays(territory) when is_atom(territory) do
    @days -- weekend(territory)
  end

  @doc """
  Returns the first day of the week for a locale.

  Derives the territory from the locale and returns the
  first day of the week for that territory.

  ### Arguments

  * `locale` is a locale identifier atom, string, or
    `t:Localize.LanguageTag.t/0`.

  ### Returns

  * An integer from 1 to 7.

  * `{:error, exception}` if the locale is invalid.

  ### Examples

      iex> Localize.Calendar.first_day_for_locale(:en)
      7

  """
  @spec first_day_for_locale(Localize.locale()) :: integer() | {:error, Exception.t()}
  def first_day_for_locale(locale) do
    with {:ok, territory} <- territory_from_locale(locale) do
      first_day_for_territory(territory)
    end
  end

  @doc """
  Returns the minimum days in the first week of the year
  for a locale.

  ### Arguments

  * `locale` is a locale identifier atom, string, or
    `t:Localize.LanguageTag.t/0`.

  ### Returns

  * An integer from 1 to 7.

  * `{:error, exception}` if the locale is invalid.

  """
  @spec min_days_for_locale(Localize.locale()) :: integer() | {:error, Exception.t()}
  def min_days_for_locale(locale) do
    with {:ok, territory} <- territory_from_locale(locale) do
      min_days_for_territory(territory)
    end
  end

  # ── Private helpers ─────────────────────────────────────────────

  defp get_calendar_data(locale, calendar_type, data_key) do
    with {:ok, locale_id} <- resolve_locale_id(locale) do
      get_calendar_data_raw(locale_id, calendar_type, data_key)
    end
  end

  defp get_calendar_data_raw(locale_id, calendar_type, data_key) do
    Localize.Locale.get(locale_id, [:dates, :calendars, calendar_type, data_key])
  end

  defp resolve_locale_id(%Localize.LanguageTag{cldr_locale_id: id}) when not is_nil(id),
    do: {:ok, id}

  defp resolve_locale_id(locale) when is_atom(locale), do: {:ok, locale}

  defp resolve_locale_id(locale) when is_binary(locale) do
    with {:ok, language_tag} <- Localize.validate_locale(locale) do
      {:ok, language_tag.cldr_locale_id}
    end
  end

  defp calendar_type_from(%{calendar: calendar}) do
    if function_exported?(calendar, :cldr_calendar_type, 0) do
      calendar.cldr_calendar_type()
    else
      @default_calendar_type
    end
  end

  defp calendar_type_from(_), do: @default_calendar_type

  defp day_of_era(%{year: year}) when year > 0, do: {:current, 1}
  defp day_of_era(%{year: _year}), do: {:before_current, 0}
  defp day_of_era(_), do: {:current, 1}

  defp quarter_of_year(%{month: month}) when is_integer(month) do
    div(month - 1, 3) + 1
  end

  defp quarter_of_year(_), do: 1

  defp month_of_year(%{month: month}) when is_integer(month), do: month
  defp month_of_year(_), do: 1

  defp iso_day_of_week(%{year: year, month: month, day: day, calendar: calendar})
       when is_integer(year) and is_integer(month) and is_integer(day) do
    {day_of_week, _} = calendar.day_of_week(year, month, day, :monday)
    day_of_week
  rescue
    _ -> Calendar.ISO.day_of_week(year, month, day, :monday) |> elem(0)
  end

  defp iso_day_of_week(%{year: year, month: month, day: day})
       when is_integer(year) and is_integer(month) and is_integer(day) do
    Calendar.ISO.day_of_week(year, month, day, :monday) |> elem(0)
  end

  defp iso_day_of_week(_), do: 1

  defp territory_from_locale(%Localize.LanguageTag{territory: territory})
       when not is_nil(territory) do
    {:ok, territory}
  end

  defp territory_from_locale(locale) when is_atom(locale) do
    with {:ok, language_tag} <- Localize.validate_locale(locale) do
      {:ok, language_tag.territory || :US}
    end
  end

  defp territory_from_locale(locale) when is_binary(locale) do
    with {:ok, language_tag} <- Localize.validate_locale(locale) do
      {:ok, language_tag.territory || :US}
    end
  end

  defp territory_from_locale(_), do: {:ok, :US}
end
