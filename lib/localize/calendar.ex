defmodule Localize.Calendar do
  @moduledoc """
  Calendar localization functions for retrieving locale-specific
  names for eras, months, days, quarters, and day periods.

  Also provides territory-based week preferences (first day of week,
  weekend days) and functions to produce localized date part strings
  from `Date`, `DateTime`, and `NaiveDateTime` structs.

  ## Display names

  The `display_name/3` function provides a unified API for
  localized calendar-related names, modeled on the JavaScript
  `Intl.DisplayNames` API:

  | Type | Value | Example result |
  |---|---|---|
  | `:calendar` | `:gregorian` | `"Gregorian Calendar"` |
  | `:era` | `1` | `"Anno Domini"` |
  | `:month` | `1` | `"January"` |
  | `:day_of_week` | `1` (ISO Monday) | `"Monday"` |
  | `:quarter` | `1` | `"1st quarter"` |
  | `:day_period` | `:am` | `"AM"` |
  | `:date_time_field` | `:year` | `"year"` |

  All types support `:locale` and `:style` options. The `:month`,
  `:day_of_week`, `:quarter`, and `:day_period` types also support a
  `:context` option (`:format` or `:stand_alone`).

  `:style` is the display width — `:wide` (the default),
  `:abbreviated`, `:narrow`, or `:short`. Widths vary by type:
  only the day types carry `:short`, and a width the type does not
  have returns an error naming the widths it does.

  ## Naming a date's parts

  `localize/3` is the same lookup addressed by a date rather than
  by an explicit value: `localize(~D[2019-06-01], :month)` and
  `display_name(:month, 6)` both return `{:ok, "June"}`. It derives
  the part's value from the date and delegates, so the two take the
  same options and always agree. Use it when you have a date, and
  `display_name/3` when you have the value itself.

  ## Data access

  Lower-level data access functions (`eras/2`, `months/2`,
  `days/2`, `quarters/2`, `day_periods/2`) return full data
  maps for use in formatting pipelines.

  """

  import Localize.Utils.Helpers, only: [is_keyword_list: 1]

  alias Localize.LanguageTag

  @default_calendar_type :gregorian

  @acceptable_calendars [
    :gregorian,
    :buddhist,
    :chinese,
    :coptic,
    :dangi,
    :ethiopic,
    :ethiopic_amete_alem,
    :hebrew,
    :indian,
    :islamic,
    :islamic_civil,
    :islamic_rgsa,
    :islamic_tbla,
    :islamic_umalqura,
    :japanese,
    :persian,
    :roc
  ]

  @parts [:era, :quarter, :month, :day_of_week, :days_of_week, :day_period]

  @type part :: :era | :quarter | :month | :day_of_week | :days_of_week | :day_period
  @type format :: :wide | :abbreviated | :narrow
  @type context :: :format | :stand_alone

  @days 1..7 |> Enum.to_list()
  @the_world :"001"

  # ISO day numbers for the -u-fw- (first day of week) extension values.
  @first_day_from_fw %{mon: 1, tue: 2, wed: 3, thu: 4, fri: 5, sat: 6, sun: 7}

  @doc """
  Returns the list of known CLDR calendar types.

  ### Returns

  * A list of calendar type atoms.

  ### Examples

      iex> calendars = Localize.Calendar.known_calendars()
      iex> :gregorian in calendars and :buddhist in calendars and :hebrew in calendars
      true

  """
  @spec known_calendars() :: [atom(), ...]
  def known_calendars do
    @acceptable_calendars
  end

  # ── Display names ─────────────────────────────────────────────

  @display_name_types [
    :calendar,
    :era,
    :quarter,
    :month,
    :day_of_week,
    :day_period,
    :date_time_field
  ]

  @date_time_fields [
    :era,
    :year,
    :quarter,
    :month,
    :week,
    :weekday,
    :day,
    :day_period,
    :hour,
    :minute,
    :second,
    :zone
  ]

  @doc """
  Returns a localized display name for a calendar-related item.

  This is a unified API for retrieving localized names for
  calendar systems, date-time fields, eras, months, days, quarters,
  and day periods — modeled on the JavaScript `Intl.DisplayNames`
  API.

  ### Summary

  | Type | Value | Example result |
  |---|---|---|
  | `:calendar` | `:gregorian` | `"Gregorian Calendar"` |
  | `:era` | `1` | `"Anno Domini"` |
  | `:month` | `1` | `"January"` |
  | `:day_of_week` | `1` (ISO Monday) | `"Monday"` |
  | `:quarter` | `1` | `"1st quarter"` |
  | `:day_period` | `:am` | `"AM"` |
  | `:date_time_field` | `:year` | `"year"` |

  ### Arguments

  * `type` is the type of calendar item. One of:

    * `:calendar` — a calendar system name (e.g., `:gregorian`).

    * `:era` — an era name by index (e.g., `1` for AD).

    * `:quarter` — a quarter name by number (1–4).

    * `:month` — a month name by number (1–12).

    * `:day_of_week` — a day-of-week name by ISO day number (1–7,
      Monday–Sunday).

    * `:day_period` — a day period name (e.g., `:am`, `:pm`,
      `:noon`, `:midnight`).

    * `:date_time_field` — a date-time field label (e.g.,
      `:year`, `:month`, `:day`, `:hour`, `:minute`, `:second`).

  * `value` is the value to look up. The type depends on
    the `type` argument (see above).

  * `options` is a keyword list of options.

  ### Options

  * `:locale` is a locale identifier. The default is
    `Localize.get_locale()`.

  * `:style` is the display width. One of `:wide` (default),
    `:abbreviated`, `:narrow`, or `:short`. Not all styles are
    available for all types.

  * `:context` is `:format` (default) or `:stand_alone`.
    Applies to `:month`, `:day_of_week`, `:quarter`, and `:day_period`.

  * `:day_period` — if set to `:variant`, uses variant day period
    names ("am"/"pm" instead of "AM"/"PM" in English). Applies to
    the `:day_period` type.

  * `:calendar` is the calendar system atom. The default is
    `:gregorian`.

  ### Returns

  * `{:ok, name}` where `name` is the localized display name.

  * `{:error, exception}` if the value is not found.

  ### Examples

      iex> Localize.Calendar.display_name(:calendar, :gregorian)
      {:ok, "Gregorian Calendar"}

      iex> Localize.Calendar.display_name(:month, 1)
      {:ok, "January"}

      iex> Localize.Calendar.display_name(:month, 1, style: :abbreviated)
      {:ok, "Jan"}

      iex> Localize.Calendar.display_name(:day_of_week, 1)
      {:ok, "Monday"}

      iex> Localize.Calendar.display_name(:day_of_week, 1, style: :narrow)
      {:ok, "M"}

      iex> Localize.Calendar.display_name(:day_period, :am)
      {:ok, "AM"}

      iex> Localize.Calendar.display_name(:date_time_field, :year)
      {:ok, "year"}

      iex> Localize.Calendar.display_name(:era, 1)
      {:ok, "Anno Domini"}

      iex> Localize.Calendar.display_name(:quarter, 1, style: :abbreviated)
      {:ok, "Q1"}

  """
  @spec display_name(atom(), term(), Keyword.t()) ::
          {:ok, String.t()} | {:error, Exception.t()}
  def display_name(type, value, options \\ [])

  def display_name(:calendar, calendar_type, options) when is_keyword_list(options) do
    locale = Keyword.get(options, :locale, Localize.get_locale())

    with {:ok, locale_id} <- resolve_locale_id(locale),
         {:ok, ldn} <- Localize.Locale.get(locale_id, [:locale_display_names]) do
      calendar_names = get_in(ldn, [:types, :calendar]) || %{}

      case Map.get(calendar_names, calendar_type) do
        nil -> {:error, Localize.UnknownCalendarError.exception(calendar: calendar_type)}
        name when is_binary(name) -> {:ok, name}
      end
    end
  end

  def display_name(:date_time_field, field, options)
      when field in @date_time_fields and is_keyword_list(options) do
    locale = Keyword.get(options, :locale, Localize.get_locale())
    style = map_field_style(Keyword.get(options, :style, :wide))

    with {:ok, locale_id} <- resolve_locale_id(locale),
         {:ok, date_fields} <- Localize.Locale.get(locale_id, [:date_fields]) do
      date_fields
      |> Map.get(field)
      |> get_in([style, :display_name])
      |> unwrap_localized_name()
      |> wrap_or_invalid(field, "a known date-time field")
    end
  end

  def display_name(:era, era_index, options) when is_keyword_list(options) do
    lookup_calendar_field(:eras, era_index, options, "a valid era index", style: :wide)
  end

  def display_name(:quarter, quarter, options)
      when quarter in 1..4 and is_keyword_list(options) do
    lookup_calendar_field(:quarters, quarter, options, "1..4")
  end

  def display_name(:month, month, options) when month in 1..13 and is_keyword_list(options) do
    lookup_calendar_field(:months, month, options, "1..13")
  end

  def display_name(:day_of_week, day, options) when day in 1..7 and is_keyword_list(options) do
    lookup_calendar_field(:days, day, options, "1..7 (ISO day)")
  end

  def display_name(:day_period, period, options) when is_keyword_list(options) do
    lookup_calendar_field(
      :day_periods,
      period,
      options,
      "a day period atom (:am, :pm, :noon, :midnight, etc.)",
      style: :abbreviated,
      unwrap: true
    )
  end

  def display_name(_type, _value, options) when not is_keyword_list(options),
    do: {:error, Localize.Utils.Helpers.invalid_options(options)}

  def display_name(type, value, _options) when type in @display_name_types do
    {:error, invalid_display_value_error(value, "a valid value for #{inspect(type)}")}
  end

  def display_name(type, _value, _options) do
    {:error,
     Localize.InvalidValueError.exception(
       value: type,
       expected: "a known display name type",
       allowed_values: @display_name_types,
       context: "Calendar.display_name"
     )}
  end

  @doc """
  Same as `display_name/3` but raises on error.

  ### Arguments

  * `type` is the type of calendar item (`:calendar`, `:era`,
    `:quarter`, `:month`, `:day_of_week`, `:day_period`, or
    `:date_time_field`). See `display_name/3`.

  * `value` is the value to look up. The type depends on the
    `type` argument.

  * `options` is a keyword list of options.

  ### Options

  See `display_name/3` for the supported options.

  ### Returns

  * The localized display name as a string.

  * Raises an exception if the value is not found.

  ### Examples

      iex> Localize.Calendar.display_name!(:month, 1)
      "January"

      iex> Localize.Calendar.display_name!(:quarter, 1, style: :abbreviated)
      "Q1"

  """
  @spec display_name!(
          :calendar | :era | :quarter | :month | :day_of_week | :day_period | :date_time_field,
          term(),
          Keyword.t()
        ) :: String.t()
  def display_name!(type, value, options \\ []) do
    case display_name(type, value, options) do
      {:ok, name} -> name
      {:error, exception} -> raise exception
    end
  end

  # Map :wide/:short style names to date_fields width keys
  defp map_field_style(:wide), do: :standard
  defp map_field_style(:short), do: :short
  defp map_field_style(:narrow), do: :narrow
  defp map_field_style(style), do: style

  # Shared implementation for the calendar-data lookup clauses
  # (:era, :quarter, :month, :day_of_week, :day_period). Each takes the same
  # shape: resolve locale → load CLDR data for the given key → walk
  # `[context, style, value]` (or `[style, value]` for :era) → return
  # the localised name or an InvalidValueError. Per-clause variations
  # are captured by the `defaults` keyword: `style:` overrides the
  # default `:wide`, and `unwrap: true` peels the `%{default: name}`
  # shape that day-period entries can take.
  defp lookup_calendar_field(data_key, value, options, expected, defaults \\ []) do
    locale = Keyword.get(options, :locale, Localize.get_locale())
    style = Keyword.get(options, :style, Keyword.get(defaults, :style, :wide))
    calendar_type = Keyword.get(options, :calendar, @default_calendar_type)
    unwrap? = Keyword.get(defaults, :unwrap, false)
    variant? = Keyword.get(options, :day_period) == :variant

    with {:ok, locale_id} <- resolve_locale_id(locale),
         {:ok, data} <- get_calendar_data_raw(locale_id, calendar_type, data_key),
         {:ok, styles} <- field_styles(data, data_key, options),
         {:ok, names} <- field_names(styles, style) do
      names
      |> Map.get(value)
      |> maybe_unwrap_name(unwrap?, variant?)
      |> wrap_or_invalid(value, expected)
    end
  end

  # `:eras` are keyed by style alone; every other calendar field is
  # keyed by context (`:format` / `:stand_alone`) first.
  defp field_styles(data, :eras, _options), do: {:ok, data}

  defp field_styles(data, _data_key, options) do
    context = Keyword.get(options, :context, :format)

    case Map.get(data, context) do
      styles when is_map(styles) -> {:ok, styles}
      _ -> {:error, invalid_field_option_error(:context, context, data)}
    end
  end

  # A style the field does not carry is a bad `:style` option, not a
  # bad value, so the error names the style and lists what the field
  # actually has. Widths vary by field — only `:days` has `:short` —
  # which is why the available set is read from the data rather than
  # hard-coded.
  defp field_names(styles, style) do
    case Map.get(styles, style) do
      names when is_map(names) -> {:ok, names}
      _ -> {:error, invalid_field_option_error(:style, style, styles)}
    end
  end

  defp invalid_field_option_error(option, value, available) do
    Localize.InvalidValueError.exception(
      value: value,
      expected: "a #{inspect(option)} supported by this calendar field",
      allowed_values: available |> Map.keys() |> Enum.sort(),
      context: "Calendar.display_name"
    )
  end

  # Some CLDR fields (day-period names, date-field display names) wrap
  # the binary in `%{default: name}` when an `alt` variant exists.
  # Unwrap to the binary; pass plain binaries through; return nil
  # for anything else so the caller's `wrap_or_invalid/3` produces
  # the not-found error.
  defp unwrap_localized_name(value), do: unwrap_localized_name(value, false)

  # `day_period: :variant` selects the CLDR `alt` name where the field has
  # one ("am" rather than "AM"), falling back to the default when it
  # does not.
  defp unwrap_localized_name(value, true) when is_map(value),
    do: Map.get(value, :variant) || Map.get(value, :default)

  defp unwrap_localized_name(%{default: name}, _variant?), do: name
  defp unwrap_localized_name(name, _variant?) when is_binary(name), do: name
  defp unwrap_localized_name(_value, _variant?), do: nil

  defp maybe_unwrap_name(value, true, variant?), do: unwrap_localized_name(value, variant?)
  defp maybe_unwrap_name(value, false, _variant?), do: value

  defp wrap_or_invalid(nil, value, expected),
    do: {:error, invalid_display_value_error(value, expected)}

  defp wrap_or_invalid(name, _value, _expected), do: {:ok, name}

  defp invalid_display_value_error(value, expected) do
    Localize.InvalidValueError.exception(
      value: value,
      expected: expected,
      context: "Calendar.display_name"
    )
  end

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
    by context (`:format`, `:stand_alone`), then format, then quarter
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
    context (`:format`, `:stand_alone`), then format, then month
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

  * `{:ok, day_data}` where `day_data` is a map keyed by context
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
    keyed by context, format, period, and variant.

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
  Returns the cyclic year names for a locale and calendar type.

  Cyclic year names are used by some calendar systems (such as
  Chinese and Dangi) that follow a 60-year cycle of named years.

  ### Arguments

  * `locale` is a locale identifier atom, string, or
    `t:Localize.LanguageTag.t/0`.

  * `calendar_type` is a CLDR calendar type atom. The default
    is `:gregorian`.

  ### Returns

  * `{:ok, cyclic_year_data}` where `cyclic_year_data` is a map
    of cyclic name sets.

  * `{:error, exception}` if the locale or calendar is not found.

  ### Examples

      iex> {:ok, cyclic} = Localize.Calendar.cyclic_years(:en, :chinese)
      iex> Map.keys(cyclic) |> Enum.sort()
      [:day_parts, :days, :months, :solar_terms, :years, :zodiacs]

      iex> {:ok, cyclic} = Localize.Calendar.cyclic_years(:en, :chinese)
      iex> get_in(cyclic, [:zodiacs, :format, :abbreviated, 1])
      "Rat"

  """
  @spec cyclic_years(Localize.locale(), atom()) :: {:ok, map()} | {:error, Exception.t()}
  def cyclic_years(locale, calendar_type \\ @default_calendar_type) do
    get_calendar_data(locale, calendar_type, :cyclic_name_sets)
  end

  @doc """
  Returns the month pattern data for a locale and calendar type.

  Month patterns are used by some calendar systems (such as
  Chinese and Hebrew) that have leap months. The patterns define
  how to format month names in leap and non-leap contexts.

  ### Arguments

  * `locale` is a locale identifier atom, string, or
    `t:Localize.LanguageTag.t/0`.

  * `calendar_type` is a CLDR calendar type atom. The default
    is `:gregorian`.

  ### Returns

  * `{:ok, month_pattern_data}` where `month_pattern_data` is a map
    of month patterns keyed by context and format width.

  * `{:error, exception}` if the locale or calendar is not found.

  ### Examples

      iex> {:ok, patterns} = Localize.Calendar.month_patterns(:en, :chinese)
      iex> get_in(patterns, [:format, :narrow, :leap])
      [0, "b"]

  """
  @spec month_patterns(Localize.locale(), atom()) :: {:ok, map()} | {:error, Exception.t()}
  def month_patterns(locale, calendar_type \\ @default_calendar_type) do
    get_calendar_data(locale, calendar_type, :month_patterns)
  end

  @doc """
  Returns the acceptable CLDR calendar types.

  ### Returns

  * A list of atoms.

  ### Examples

      iex> Localize.Calendar.acceptable_calendars()
      [:gregorian, :buddhist, :chinese, :coptic, :dangi, :ethiopic, :ethiopic_amete_alem, :hebrew, :indian, :islamic, :islamic_civil, :islamic_rgsa, :islamic_tbla, :islamic_umalqura, :japanese, :persian, :roc]

  """
  @spec acceptable_calendars() :: [atom(), ...]
  def acceptable_calendars, do: @acceptable_calendars

  # ── Localize date parts ─────────────────────────────────────────

  @doc """
  Returns a localized string for a part of a date or time.

  A month is named by its calendar: `month_of_year/3` gives its month of
  the year and `cardinal_month/1` the CLDR month whose name it takes, so
  a year that begins in July names its first month July, and the Hebrew
  and lunisolar calendars name each month whatever its place in the
  year. A leap month takes CLDR's leap-year name for its month (the
  Hebrew "Adar II"), or its month's name in the calendar's leap-month
  pattern (the Chinese "Second Monthbis"). A date's calendar is
  `Calendar.ISO` or one implementing the Calendrical behaviour, which
  answers these questions; any other is refused.

  A part is named from the fields of the value it is asked of: an era
  from the year, a quarter from the year and the month, a month from the
  month, a day of the week from the year, the month and the day, and a day
  period from the hour. A value that lacks one of them has no such part,
  and is an error naming the field, as a pattern that asks for the part is
  in `Localize.Date.to_string/2`.

  ### Arguments

  * `datetime` is any `t:Date.t/0`, `t:Time.t/0`, `t:DateTime.t/0`, or
    `t:NaiveDateTime.t/0`, or a map with the fields `part` is named from.

  * `part` is one of `:era`, `:quarter`, `:month`,
    `:day_of_week`, `:days_of_week`, or `:day_period`.

  * `options` is a keyword list of options. The default is `[]`.

  ### Options

  * `:locale` is a locale identifier. The default is
    `Localize.get_locale()`.

  * `:style` is the display width. One of `:wide` (default),
    `:abbreviated`, `:narrow`, or `:short`. Not all widths exist
    for all parts — only the day parts carry `:short` — and a
    width the part does not have returns an error listing the
    widths it does.

  * `:context` is one of `:format` or `:stand_alone`. The default
    is `:format`.

  * `:era` — if set to `:variant`, uses variant era names
    ("Common Era" instead of "Anno Domini" in English).

  * `:day_period` — if set to `:variant`, uses variant day period
    names ("am"/"pm" instead of "AM"/"PM" in English). Each
    variant option is named for the part it applies to.

  ### Returns

  * `{:ok, name}` where `name` is the localized string.

  * `{:ok, days}` where `days` is a list of
    `{day_number, day_name}` tuples, when `part` is
    `:days_of_week`.

  * `{:error, %Localize.UnknownCalendarError{}}` if the date's
    calendar cannot answer for its parts.

  * `{:error, %Localize.DateTimeInvalidInputError{}}` if the value lacks
    a field the part is named from, or holds one that is not an integer.

  * `{:error, exception}` if the part cannot be localized.

  ### Examples

      iex> Localize.Calendar.localize(~D[2019-06-01], :month)
      {:ok, "June"}

      iex> {:error, error} = Localize.Calendar.localize(%{year: 2019}, :month)
      iex> error.missing
      [:month]

      iex> Localize.Calendar.localize(~D[2019-06-01], :month, style: :abbreviated)
      {:ok, "Jun"}

      iex> Localize.Calendar.localize(~D[2019-06-01], :day_of_week)
      {:ok, "Saturday"}

      iex> Localize.Calendar.localize(~D[2019-01-01], :era)
      {:ok, "Anno Domini"}

      iex> Localize.Calendar.localize(~D[2019-01-01], :era, era: :variant)
      {:ok, "Common Era"}

      iex> Localize.Calendar.localize(~D[2019-01-01], :quarter)
      {:ok, "1st quarter"}

  """
  @spec localize(map(), part(), Keyword.t()) ::
          {:ok, String.t() | [{1..7, String.t()}]} | {:error, Exception.t()}
  def localize(datetime, part, options \\ [])

  # A date whose calendar cannot answer for its parts is refused here.
  def localize(datetime, part, options) when is_map(datetime) and is_keyword_list(options) do
    with :ok <- validate_value(datetime) do
      localize_part(datetime, part, options)
    end
  end

  def localize(datetime, _part, options) when is_keyword_list(options),
    do: {:error, Localize.Utils.Helpers.invalid_value(datetime, "a date, time or datetime")}

  def localize(_datetime, _part, options),
    do: {:error, Localize.Utils.Helpers.invalid_options(options)}

  defp localize_part(datetime, :era, options) do
    with :ok <- holds_part(datetime, :era),
         {:ok, era} <- era_of(datetime) do
      era_key = if options[:era] == :variant, do: -era - 1, else: era
      options = Keyword.put_new(options, :calendar, era_calendar_type_from(datetime))
      display_name(:era, era_key, options)
    end
  end

  defp localize_part(datetime, :quarter, options) do
    with :ok <- holds_part(datetime, :quarter),
         {:ok, quarter} <- quarter_of_year(datetime) do
      display_name(:quarter, quarter, localize_options(datetime, options))
    end
  end

  defp localize_part(datetime, :month, options) do
    with :ok <- holds_part(datetime, :month) do
      case cldr_month(datetime) do
        {:error, _reason} = error -> error
        month -> month_name(month, localize_options(datetime, options))
      end
    end
  end

  defp localize_part(datetime, :day_of_week, options) do
    with {:ok, day} <- day_of_week(datetime) do
      display_name(:day_of_week, day, localize_options(datetime, options))
    end
  end

  defp localize_part(datetime, :days_of_week, options) do
    options = localize_options(datetime, options)

    Enum.reduce_while(@days, {:ok, []}, fn day, {:ok, acc} ->
      case display_name(:day_of_week, day, options) do
        {:ok, name} -> {:cont, {:ok, [{day, name} | acc]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, days} -> {:ok, Enum.reverse(days)}
      {:error, _reason} = error -> error
    end
  end

  defp localize_part(%{hour: hour} = datetime, :day_period, options) when is_integer(hour) do
    am_pm = if hour < 12 or rem(hour, 24) < 12, do: :am, else: :pm

    display_name(:day_period, am_pm, localize_options(datetime, options))
  end

  defp localize_part(_datetime, :day_period, _options) do
    {:error,
     Localize.InvalidValueError.exception(
       value: nil,
       expected: "a map with an :hour key",
       context: "Localize.Calendar.localize/3"
     )}
  end

  defp localize_part(_datetime, part, _options) do
    {:error,
     Localize.InvalidValueError.exception(
       value: part,
       expected: "a localizable date part",
       allowed_values: @parts,
       context: "Localize.Calendar.localize/3"
     )}
  end

  # Whether a value holds the fields a part is named from. One that lacks a
  # field has no such part and is an error naming it, with the pattern
  # symbol that asks a format for the part, as `Localize.Date.to_string/2`
  # answers a pattern the value cannot fill. The first value of the part was
  # named instead: January for a year alone, Monday for a year and a month,
  # and the current era for a month and a day.
  defp holds_part(datetime, part) do
    {symbol, fields} = part_fields(part)
    missing = Enum.reject(fields, &Map.has_key?(datetime, &1))
    invalid = Enum.reject(fields -- missing, &is_integer(Map.get(datetime, &1)))

    if missing == [] and invalid == [] do
      :ok
    else
      {:error,
       Localize.DateTimeInvalidInputError.exception(
         format: symbol,
         missing: missing,
         invalid: invalid
       )}
    end
  end

  defp part_fields(:era), do: {"G", [:year]}
  defp part_fields(:quarter), do: {"Q", [:year, :month]}
  defp part_fields(:month), do: {"M", [:month]}
  defp part_fields(:day_of_week), do: {"E", [:year, :month, :day]}

  @doc """
  Same as `localize/3` but raises on error.

  ### Arguments

  * `datetime` is any `t:Date.t/0`, `t:DateTime.t/0`, or
    `t:NaiveDateTime.t/0`.

  * `part` is one of `:era`, `:quarter`, `:month`,
    `:day_of_week`, `:days_of_week`, or `:day_period`.

  * `options` is a keyword list of options.

  ### Options

  See `localize/3` for the supported options.

  ### Returns

  * The localized name, or the list of `{day_number, day_name}`
    tuples when `part` is `:days_of_week`.

  * Raises an exception if the part cannot be localized.

  ### Examples

      iex> Localize.Calendar.localize!(~D[2019-06-01], :month)
      "June"

      iex> Localize.Calendar.localize!(~D[2019-06-01], :month, style: :abbreviated)
      "Jun"

  """
  @spec localize!(map(), part(), Keyword.t()) :: String.t() | [{1..7, String.t()}]
  def localize!(datetime, part, options \\ []) do
    case localize(datetime, part, options) do
      {:ok, name} -> name
      {:error, exception} -> raise exception
    end
  end

  # The datetime carries the calendar, which `display_name/3` takes as
  # the `:calendar` option.
  defp localize_options(datetime, options) do
    Keyword.put_new(options, :calendar, calendar_type_from(datetime))
  end

  # ── strftime options ────────────────────────────────────────────

  @doc """
  Returns a keyword list of options for use with
  `Calendar.strftime/3`.

  The returned keyword list contains callback functions that
  produce localized month names, day names, and AM/PM indicators.

  `Calendar.strftime/3` passes a month-name callback the month number
  alone, so a month is named by that number. For a calendar whose month
  names do not follow a month's position in its year (the Hebrew and
  lunisolar calendars), name the month with `localize/3` instead.

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
  def strftime_options!(options \\ [])

  def strftime_options!(options) when is_keyword_list(options) do
    locale = Keyword.get(options, :locale, Localize.get_locale())
    calendar_type = Keyword.get(options, :calendar_type, @default_calendar_type)

    with {:ok, locale_id} <- resolve_locale_id(locale),
         {:ok, months_data} <- get_calendar_data_raw(locale_id, calendar_type, :months),
         {:ok, days_data} <- get_calendar_data_raw(locale_id, calendar_type, :days),
         {:ok, periods_data} <- get_calendar_data_raw(locale_id, calendar_type, :day_periods) do
      [
        am_pm_names: am_pm_callback(periods_data),
        month_names: month_callback(months_data, :wide),
        abbreviated_month_names: month_callback(months_data, :abbreviated),
        day_of_week_names: day_callback(days_data, :wide),
        abbreviated_day_of_week_names: day_callback(days_data, :abbreviated)
      ]
    else
      {:error, exception} -> raise exception
    end
  end

  def strftime_options!(options), do: raise(Localize.Utils.Helpers.invalid_options(options))

  defp am_pm_callback(periods_data) do
    fn am_pm ->
      case get_in(periods_data, [:format, :abbreviated, am_pm]) do
        am_pm_map when is_map(am_pm_map) -> Map.get(am_pm_map, :default, "")
        other -> other || ""
      end
    end
  end

  defp month_callback(months_data, width) do
    fn month -> get_in(months_data, [:format, width, month]) end
  end

  defp day_callback(days_data, width) do
    fn day -> get_in(days_data, [:format, width, day]) end
  end

  # ── Territory preferences ───────────────────────────────────────

  @doc """
  Returns the first day of the week for a territory.

  Day numbers follow ISO 8601: 1 = Monday through 7 = Sunday.

  ### Arguments

  * `territory` is a territory atom (e.g., `:US`, `:GB`).

  ### Returns

  * An integer from 1 to 7.

  * `{:error, exception}` if `territory` is not an atom.

  ### Examples

      iex> Localize.Calendar.first_day_for_territory(:US)
      7

      iex> Localize.Calendar.first_day_for_territory(:GB)
      1

  """
  @spec first_day_for_territory(atom()) :: integer() | {:error, Exception.t()}
  def first_day_for_territory(territory) when is_atom(territory) do
    week_info = Localize.SupplementalData.weeks()

    case get_in(week_info, [:first_day, territory]) do
      nil ->
        get_in(week_info, [:first_day, @the_world]) || 1

      day ->
        day
    end
  end

  def first_day_for_territory(territory), do: invalid_territory(territory)

  @doc """
  Returns the minimum days in the first week of the year
  for a territory.

  ### Arguments

  * `territory` is a territory atom.

  ### Returns

  * An integer from 1 to 7.

  * `{:error, exception}` if `territory` is not an atom.

  ### Examples

      iex> Localize.Calendar.min_days_for_territory(:US)
      1

      iex> Localize.Calendar.min_days_for_territory(:GB)
      4

  """
  @spec min_days_for_territory(atom()) :: integer() | {:error, Exception.t()}
  def min_days_for_territory(territory) when is_atom(territory) do
    week_info = Localize.SupplementalData.weeks()

    case get_in(week_info, [:min_days, territory]) do
      nil ->
        get_in(week_info, [:min_days, @the_world]) || 1

      days ->
        days
    end
  end

  def min_days_for_territory(territory), do: invalid_territory(territory)

  @doc """
  Returns the weekend days for a territory as a list
  of ISO day-of-week numbers.

  ### Arguments

  * `territory` is a territory atom.

  ### Returns

  * A list of integers from 1 to 7.

  * `{:error, exception}` if `territory` is not an atom.

  ### Examples

      iex> Localize.Calendar.weekend(:US)
      [6, 7]

      iex> Localize.Calendar.weekend(:IL)
      [5, 6]

  """
  @spec weekend(atom()) :: [integer()] | {:error, Exception.t()}
  def weekend(territory) when is_atom(territory) do
    week_info = Localize.SupplementalData.weeks()

    starts =
      get_in(week_info, [:weekend_start, territory]) ||
        get_in(week_info, [:weekend_start, @the_world]) || 6

    ends =
      get_in(week_info, [:weekend_end, territory]) ||
        get_in(week_info, [:weekend_end, @the_world]) || 7

    Enum.to_list(starts..ends)
  end

  def weekend(territory), do: invalid_territory(territory)

  @doc """
  Returns the weekday numbers for a territory as a list
  of ISO day-of-week numbers.

  ### Arguments

  * `territory` is a territory atom.

  ### Returns

  * A list of integers from 1 to 7.

  * `{:error, exception}` if `territory` is not an atom.

  ### Examples

      iex> Localize.Calendar.weekdays(:US)
      [1, 2, 3, 4, 5]

  """
  @spec weekdays(atom()) :: [1..7, ...] | {:error, Exception.t()}
  def weekdays(territory) when is_atom(territory) do
    @days -- weekend(territory)
  end

  def weekdays(territory), do: invalid_territory(territory)

  defp invalid_territory(territory),
    do: {:error, Localize.Utils.Helpers.invalid_value(territory, "a territory code atom")}

  @doc """
  Returns the first day of the week for a locale.

  The day is found as TR35's first day algorithm finds it: a `-u-fw-`
  day, else the first day of a `-u-rg-` region, else Monday for the
  `-u-ca-iso8601` calendar, else the first day of the locale's region,
  of its `-u-sd-` subdivision's region, of the region its likely
  subtags add, or of the world.

  ### Arguments

  * `locale` is a locale identifier atom, string, or
    `t:Localize.LanguageTag.t/0`.

  ### Returns

  * An integer from 1 to 7 (Monday is 1).

  * `{:error, exception}` if the locale is invalid.

  ### Examples

      iex> Localize.Calendar.first_day_for_locale(:en)
      7

      iex> Localize.Calendar.first_day_for_locale("en-u-fw-mon")
      1

      iex> Localize.Calendar.first_day_for_locale("en-u-rg-gbzzzz")
      1

      iex> Localize.Calendar.first_day_for_locale("en-u-ca-iso8601")
      1

  """
  @spec first_day_for_locale(Localize.locale()) :: integer() | {:error, Exception.t()}
  # A struct built by hand can carry fields of the wrong shape, including a
  # first-day keyword CLDR does not define, which are reported or ignored
  # rather than raised on.
  def first_day_for_locale(%LanguageTag{} = language_tag) do
    with {:ok, tag} <- LanguageTag.validate_fields(language_tag) do
      first_day_for_tag(tag)
    end
  end

  def first_day_for_locale(locale) do
    with {:ok, language_tag} <- Localize.validate_locale(locale) do
      first_day_for_locale(language_tag)
    end
  end

  # TR35's first day of the week (tr35-dates, "First Day Overrides").
  # `iso8601` is the one calendar that names a first day of its own: BCP 47
  # defines it as the Gregorian calendar with ISO 8601's week rules.
  defp first_day_for_tag(%LanguageTag{} = tag) do
    cond do
      day = Map.get(@first_day_from_fw, locale_keyword(tag, :fw)) -> day
      region = region_of(locale_keyword(tag, :rg)) -> first_day_for_territory(region)
      locale_keyword(tag, :ca) == :iso8601 -> 1
      true -> first_day_for_territory(week_region(tag))
    end
  end

  @doc """
  Returns the minimum days in the first week of the year
  for a locale.

  The `-u-ca-iso8601` calendar's weeks hold four days, as ISO 8601's
  do. Any other locale takes the minimum days of the region TR35's
  first day algorithm finds for it: a `-u-rg-` region, else the
  locale's region, its `-u-sd-` subdivision's region, the region its
  likely subtags add, or the world.

  ### Arguments

  * `locale` is a locale identifier atom, string, or
    `t:Localize.LanguageTag.t/0`.

  ### Returns

  * An integer from 1 to 7.

  * `{:error, exception}` if the locale is invalid.

  ### Examples

      iex> Localize.Calendar.min_days_for_locale(:en)
      1

      iex> Localize.Calendar.min_days_for_locale(:de)
      4

      iex> Localize.Calendar.min_days_for_locale("en-u-ca-iso8601")
      4

  """
  @spec min_days_for_locale(Localize.locale()) :: integer() | {:error, Exception.t()}
  def min_days_for_locale(%LanguageTag{} = language_tag) do
    with {:ok, tag} <- LanguageTag.validate_fields(language_tag) do
      if locale_keyword(tag, :ca) == :iso8601,
        do: 4,
        else: min_days_for_territory(region_of(locale_keyword(tag, :rg)) || week_region(tag))
    end
  end

  def min_days_for_locale(locale) do
    with {:ok, language_tag} <- Localize.validate_locale(locale) do
      min_days_for_locale(language_tag)
    end
  end

  # The value of a `-u-` key in a tag whose fields have been validated, which
  # leaves a tag without the extension an empty map.
  defp locale_keyword(%LanguageTag{locale: keywords}, key), do: Map.get(keywords, key)

  # The region whose week data a locale takes when no `-u-rg-` override
  # names one, as TR35's first day algorithm orders them: the region subtag
  # the identifier carries, else its `-u-sd-` subdivision's region, else the
  # region its likely subtags add, else the world.
  defp week_region(%LanguageTag{} = tag) do
    case region_of(locale_keyword(tag, :sd)) do
      nil -> likely_region(tag)
      subdivision_region -> explicit_region(tag) || subdivision_region
    end
  end

  # The region subtag an identifier carries itself. A validated tag's
  # territory may be one its likely subtags added, so the identifier is read
  # again; a struct built by hand has only the territory it was given.
  defp explicit_region(%LanguageTag{canonical_locale_id: identifier} = tag)
       when is_binary(identifier) do
    case LanguageTag.parse(identifier) do
      {:ok, %LanguageTag{territory: territory}} -> territory
      {:error, _exception} -> tag.territory
    end
  end

  defp explicit_region(%LanguageTag{territory: territory}), do: territory

  defp likely_region(%LanguageTag{territory: territory}) when not is_nil(territory), do: territory

  defp likely_region(%LanguageTag{} = tag) do
    case LanguageTag.add_likely_subtags(tag) do
      {:ok, %LanguageTag{territory: territory}} when not is_nil(territory) -> territory
      _no_region -> @the_world
    end
  end

  defp region_of(subdivision), do: Localize.Territory.region_of(subdivision)

  # ── Private helpers ─────────────────────────────────────────────

  defp get_calendar_data(locale, calendar_type, data_key) do
    with {:ok, locale_id} <- resolve_locale_id(locale) do
      get_calendar_data_raw(locale_id, calendar_type, data_key)
    end
  end

  defp get_calendar_data_raw(locale_id, calendar_type, data_key) do
    Localize.Locale.get(locale_id, [:dates, :calendars, calendar_type, data_key])
  end

  defp resolve_locale_id(locale), do: Localize.Locale.cldr_locale_id_from(locale)

  defp calendar_type_from(datetime), do: date_calendar_type(datetime)

  # A calendar may name its eras from another CLDR calendar than its
  # months: Calendrical's lunisolar Japanese calendar takes its month
  # names from the Chinese calendar and its eras (元号) from the
  # Japanese one, through its `era_calendar_type/0`.
  defp era_calendar_type_from(datetime),
    do: era_calendar_type(Map.get(datetime, :calendar, Calendar.ISO))

  @doc false
  # The year of era and the era of a date, whole or partial, from its
  # calendar's `year_of_era/3`. `{:error, fields}` names the fields that
  # would settle an era the date leaves open, and `{:error, exception}`
  # shows an answer that is not a year of era and an era.
  @spec year_of_era(term()) ::
          {:ok, {Calendar.year(), Calendar.era()}} | {:error, [atom()] | Exception.t()}
  def year_of_era(date), do: settle(date, &year_of_era_on/2)

  @doc false
  # The year a date shows: its calendar's `calendar_year/3` when that is
  # at least 1, and otherwise the year of era, so a year before a
  # calendar's first era counts back as TR35 counts it — year 0 is 1 BC in
  # `Calendar.ISO` and in Calendrical's calendars alike.
  @spec displayed_year(term()) :: {:ok, Calendar.year()} | {:error, [atom()] | Exception.t()}
  def displayed_year(date), do: settle(date, &displayed_year_on/2)

  # The related Gregorian year in which the first sixty-year cycle began, as
  # ICU counts the cycles of the Chinese and Dangi calendars: 2637 BC.
  @first_cyclic_year -2636

  @doc false
  # The place of a date's year in the sixty-year cycle, where `y` writes that
  # place. TR35's `U` names "the year value" and is written as `y` writes it
  # where it has no name for it, so in a calendar whose years the locale's
  # data names by a cycle the two write one number, the year's place in the
  # cycle, with `u` for the number that takes in the cycles; ICU4C writes
  # the Chinese and Dangi year that began in 2026 as 43 (user, 2026-10-04:
  # "Follow TR35"). The calendar answers the place, its `cyclic_year/3`, as
  # it answers it for `U`.
  #
  # `:none` where the locale names no cycle of years for the calendar, as it
  # names none for the Gregorian, and where the calendar displays another
  # year than the year's own number: a year of an era, as a lunisolar
  # calendar with imperial eras does, which `y` then writes.
  @spec cycle_place(term(), Localize.locale()) :: {:ok, pos_integer()} | :none
  def cycle_place(%{year: year} = date, locale) when is_integer(year) do
    calendar = Map.get(date, :calendar, Calendar.ISO)
    month = integer_or_first(Map.get(date, :month))
    day = integer_or_first(Map.get(date, :day))

    # The calendar is asked before the locale's data is read: a calendar with
    # no cycle answers the year itself, and most dates are in one.
    with {:ok, ^year} <- displayed_year(date),
         {:ok, number} when number != year <-
           ask(calendar, :cyclic_year, [year, month, day], "a year of the cycle", &is_integer/1),
         {:ok, %{years: %{format: %{} = names}}} when map_size(names) > 0 <-
           cyclic_years(locale, date_calendar_type(date)) do
      {:ok, Localize.Utils.Math.amod(number, 60)}
    else
      _no_cycle -> :none
    end
  end

  def cycle_place(_date, _locale), do: :none

  @doc false
  # The number of the sixty-year cycle a date's year is in, where `y` writes
  # the year's place in it (`cycle_place/2`). CLDR gives the Chinese and
  # Dangi calendars one era and no name for it, and TR35 does not say what
  # `G` writes for them; ICU holds the cycle as their era and writes its
  # number, and Localize follows it (user, 2026-10-06). ICU counts both
  # calendars' cycles from the one that began in 2637 BC, so the year that
  # began in 1984 is the first of the 78th in each: the count is the same
  # for every calendar of cyclic years, and is taken from the year's related
  # Gregorian year, which the calendar answers.
  @spec cycle(term(), Localize.locale()) :: {:ok, integer()} | :none
  def cycle(date, locale) do
    with {:ok, _place} <- cycle_place(date, locale),
         {:ok, related} <- related_gregorian_year(date) do
      {:ok, cycle_of_related_year(related)}
    else
      _no_cycle -> :none
    end
  end

  @doc false
  # The cycle a related Gregorian year is in, and the related Gregorian
  # year of a place in a cycle: the first year of the first cycle began in
  # 2637 BC, the year -2636.
  @spec cycle_of_related_year(integer()) :: integer()
  def cycle_of_related_year(related), do: Integer.floor_div(related - @first_cyclic_year, 60) + 1

  @doc false
  @spec related_year_of_cycle(integer(), pos_integer()) :: integer()
  def related_year_of_cycle(cycle, place) when is_integer(cycle) and is_integer(place),
    do: @first_cyclic_year + (cycle - 1) * 60 + place - 1

  # The related Gregorian year is constant through a calendar year, so a
  # date without its month or its day is asked on the first it could be.
  defp related_gregorian_year(%{year: year} = date) do
    ask(
      Map.get(date, :calendar, Calendar.ISO),
      :related_gregorian_year,
      [year, integer_or_first(Map.get(date, :month)), integer_or_first(Map.get(date, :day))],
      "a Gregorian year",
      &is_integer/1
    )
  end

  # The cyclic year is constant through a calendar year, so a date without
  # its month or its day is asked on the first it could be.
  defp integer_or_first(value) when is_integer(value), do: value
  defp integer_or_first(_absent), do: 1

  @doc false
  # A date's extended year, TR35's `u`: one number for its year through every
  # era of its calendar, as the calendar's `extended_year/3` answers. It is
  # the year itself where a calendar's years run on through its eras, as
  # `Calendar.ISO`'s do, year 0 being 1 BC, and it is not where they do not:
  # a Julian year -1, which is 1 BC, is 0.
  @spec extended_year(term()) :: {:ok, Calendar.year()} | {:error, [atom()] | Exception.t()}
  def extended_year(date), do: settle(date, &extended_year_on/2)

  # The calendar is asked with the fields the date has, the others `nil`. A
  # whole date is one day and that is its answer. A partial date could be any
  # day of its month, or of its year when it has no month, and a calendar
  # that answers from the fields it is given settles it: a calendar of weeks
  # and the Gregorian calendars name a year and its era from the year alone.
  # A calendar that needs the day says so, and the answer is then taken on
  # the first and the last of the days the date could be, and stands when the
  # two agree. They always do where eras begin with years. Where one began
  # mid-year, as in the Japanese calendar, a date in the year or month of the
  # change gets the fields that would settle it instead.
  defp settle(%{year: year} = date, answer) when is_integer(year) do
    calendar = Map.get(date, :calendar, Calendar.ISO)

    case answer.(calendar, {year, integer_field(date, :month), integer_field(date, :day)}) do
      {:ok, _answer} = settled -> settled
      {:error, _exception} = error -> settle_over_span(date, calendar, year, answer, error)
    end
  end

  defp settle(_date, _answer), do: {:error, [:year]}

  defp integer_field(date, field) do
    case Map.get(date, field) do
      value when is_integer(value) -> value
      _missing -> nil
    end
  end

  # A whole date has no other day to ask about, so its calendar's error
  # stands.
  defp settle_over_span(%{month: month, day: day}, _calendar, _year, _answer, error)
       when is_integer(month) and is_integer(day),
       do: error

  defp settle_over_span(date, calendar, year, answer, _error) do
    with {:ok, {first, last, unsettled}} <- date_span(date, calendar, year),
         {:ok, first_answer} <- answer.(calendar, first),
         {:ok, last_answer} <- answer.(calendar, last) do
      if last_answer == first_answer,
        do: {:ok, first_answer},
        else: {:error, unsettled}
    end
  end

  # The era `localize/3` names, for a value with its year (`holds_part/2`).
  # One whose days span two eras is an error naming the fields that would
  # settle it.
  defp era_of(datetime) do
    case year_of_era(datetime) do
      {:ok, {_year_of_era, era}} ->
        {:ok, era}

      {:error, fields} when is_list(fields) ->
        {:error, Localize.DateTimeInvalidInputError.exception(format: "G", missing: fields)}

      {:error, _exception} = error ->
        error
    end
  end

  # The first and last days a partial date could be, and the fields that
  # would say which: its month when it has a month the calendar has, and
  # otherwise its year. The calendar measures both. A year's days are its
  # `year/1`. A month's run from its first to the day its `days_in_month/2`
  # counts, the days of whatever the month field holds: a month's, or the
  # seven of a calendar of weeks' week. Where a reform took days out of a
  # month the count can name one of them (December 1582 in Belgium has 21
  # days, the 1st to the 14th and the 25th to the 31st), so the day is
  # checked (`valid_date?/3`) and the last one the calendar has at or below
  # the count is taken.
  defp date_span(date, calendar, year) do
    measure = answering(calendar)
    month = Map.get(date, :month)

    if is_integer(month) and measure.valid_date?(year, month, 1) do
      last_day = last_day_of(measure, year, month, measure.days_in_month(year, month))
      {:ok, {{year, month, 1}, {year, month, last_day}, [:day]}}
    else
      year_span(calendar, year)
    end
  end

  defp last_day_of(measure, year, month, day) when is_integer(day) and day > 1 do
    if measure.valid_date?(year, month, day),
      do: day,
      else: last_day_of(measure, year, month, day - 1)
  end

  defp last_day_of(_measure, _year, _month, _day), do: 1

  defp year_span(calendar, year) do
    with {:ok, %Date.Range{first: first, last: last}} <-
           ask(calendar, :year, [year], "the days of a year", &match?(%Date.Range{}, &1)) do
      {:ok,
       {{first.year, first.month, first.day}, {last.year, last.month, last.day}, [:month, :day]}}
    end
  end

  defp year_of_era_on(calendar, {year, month, day}) do
    ask(calendar, :year_of_era, [year, month, day], "a year of era and an era", fn
      {year_of_era, era} -> is_integer(year_of_era) and is_integer(era)
      _other -> false
    end)
  end

  # A calendar's `calendar_year/3` numbers a year as it is displayed — the
  # year of its era in the Japanese calendar, the year as a Julian calendar
  # beginning in March counts it — but gives a year before the first era
  # as it is, 0 or -5. TR35 counts those back from the era, so a year
  # below 1 is the year of era, from the `year_of_era/3` that names the
  # date's era.
  defp displayed_year_on(calendar, {year, month, day} = date) do
    case ask(calendar, :calendar_year, [year, month, day], "a year", &is_integer/1) do
      {:ok, shown} when shown >= 1 -> {:ok, shown}
      {:ok, _before_the_first_era} -> year_of_era_shown(calendar, date)
      {:error, _exception} = error -> error
    end
  end

  defp year_of_era_shown(calendar, date) do
    with {:ok, {year_of_era, _era}} <- year_of_era_on(calendar, date), do: {:ok, year_of_era}
  end

  defp extended_year_on(calendar, {year, month, day}) do
    ask(calendar, :extended_year, [year, month, day], "an extended year", &is_integer/1)
  end

  @doc false
  # The module a calendar's questions are put to: the calendar itself, or
  # `Localize.Calendar.ISO` for `Calendar.ISO`, which has none of the
  # callbacks and for which Localize answers as the Gregorian calendar.
  @spec answering(module()) :: module()
  def answering(Calendar.ISO), do: Localize.Calendar.ISO
  def answering(calendar), do: calendar

  # The callbacks Localize puts to a calendar other than `Calendar.ISO`, which
  # every calendar implementing the Calendrical behaviour answers: the
  # behaviour's own, and every callback of the `Calendar` behaviour it
  # extends, which Localize reaches directly and through `Date.convert/2`,
  # `Date.shift/2` and their kin.
  @answers [
             cldr_calendar_type: 0,
             era_calendar_type: 0,
             parsing_calendar: 0,
             month_of_year: 3,
             cardinal_month: 1,
             calendar_year: 3,
             extended_year: 3,
             related_gregorian_year: 3,
             cyclic_year: 3,
             week_of_year: 3,
             week_of_month: 3,
             week: 2,
             quarter: 2,
             year: 1,
             plus: 6,
             diff: 3
           ] ++
             (Calendar.behaviour_info(:callbacks) -- Calendar.behaviour_info(:optional_callbacks))

  @doc false
  # The CLDR calendar whose data names a calendar's months and days.
  @spec cldr_calendar_type(module()) :: atom()
  def cldr_calendar_type(calendar), do: answering(calendar).cldr_calendar_type()

  @doc false
  # The CLDR calendar whose data names a date's months and days: the
  # calendar's answer for the date where it gives one, through the optional
  # `cldr_calendar_type/3` (a composite calendar answers with the calendar in
  # effect on the date, so the Japanese composite names its lunisolar months
  # from the Chinese calendar and its later months from the Japanese), and
  # otherwise its `cldr_calendar_type/0`. A date without its month or day is
  # asked on the first. A value without a year has only the calendar's type.
  @spec date_calendar_type(term()) :: atom()
  def date_calendar_type(%{year: year} = date) when is_integer(year) do
    answers = date |> Map.get(:calendar, Calendar.ISO) |> answering()

    if Code.ensure_loaded?(answers) and function_exported?(answers, :cldr_calendar_type, 3) do
      month = Map.get(date, :month)
      day = Map.get(date, :day)
      month = if is_integer(month), do: month, else: 1
      day = if is_integer(day), do: day, else: 1

      case answers.cldr_calendar_type(year, month, day) do
        type when is_atom(type) and type not in [nil, true, false] -> type
        _not_a_calendar_type -> answers.cldr_calendar_type()
      end
    else
      answers.cldr_calendar_type()
    end
  end

  def date_calendar_type(%{calendar: calendar}), do: cldr_calendar_type(calendar)
  def date_calendar_type(_value), do: cldr_calendar_type(Calendar.ISO)

  @doc false
  # The CLDR calendar whose data names a calendar's eras.
  @spec era_calendar_type(module()) :: atom()
  def era_calendar_type(calendar), do: answering(calendar).era_calendar_type()

  @doc false
  # The calendar a date written for `calendar` is parsed in before it is
  # converted into it, as the calendar answers: itself, or `Calendar.ISO`
  # for a calendar of weeks, whose written month and day name no single
  # week. The answer is a calendar that must answer Localize in turn.
  @spec parsing_calendar(module()) :: {:ok, module()} | {:error, Exception.t()}
  def parsing_calendar(calendar) do
    parsing = answering(calendar).parsing_calendar()

    with :ok <- validate_calendar(%{calendar: parsing}), do: {:ok, parsing}
  end

  @doc false
  # The calendars a date written for `calendar` is read in, in turn: the one
  # its `parsing_calendar/0` names, and then any it names besides with the
  # optional `parsing_calendars/0`. A composite calendar writes the dates of
  # each of its calendars with that calendar's formats, its
  # `cldr_calendar_type/3` answering for a date: `Calendrical.Reform.Japan`
  # writes a date before 1873 as its lunisolar calendar does, "Mo5 11,
  # 1872", which the formats of its own CLDR type, the Japanese calendar's,
  # do not read. A calendar is a module, so the composite names the
  # calendars themselves, and each is read as any calendar is and its date
  # converted, as a calendar of weeks' is from `Calendar.ISO`; a CLDR type
  # is never mapped back to a calendar. Every calendar named must answer
  # Localize, and a calendar that names none is read as it was.
  @spec parsing_calendars(module()) :: {:ok, [module(), ...]} | {:error, Exception.t()}
  def parsing_calendars(calendar) do
    with {:ok, parsing} <- parsing_calendar(calendar),
         {:ok, others} <- further_parsing_calendars(answering(calendar), calendar) do
      {:ok, Enum.uniq([parsing | others])}
    end
  end

  defp further_parsing_calendars(answers, calendar) do
    if Code.ensure_loaded?(answers) and function_exported?(answers, :parsing_calendars, 0) do
      with {:ok, others} <-
             ask(calendar, :parsing_calendars, [], "a list of calendars", &is_list/1),
           nil <- Enum.find_value(others, &calendar_error/1) do
        {:ok, others}
      end
    else
      {:ok, []}
    end
  end

  defp calendar_error(calendar) do
    case validate_calendar(%{calendar: calendar}) do
      :ok -> nil
      {:error, _exception} = error -> error
    end
  end

  @doc false
  # The value written in the calendar the locale's `-u-ca-` names, which is
  # the calendar TR35 writes a date in where the locale names one:
  # `en-u-ca-hebrew` writes a Gregorian date as the Hebrew calendar's. A
  # locale that names no calendar, and a value already in the one it names,
  # is returned as it stands.
  #
  # A CLDR calendar type names no module on its own, and Localize ships the
  # ISO calendar alone, so the module comes from the value's own calendar
  # through the optional `calendar_from_cldr_calendar_type/1` that the
  # library supplying the calendars answers for its family. A calendar whose
  # family does not answer, or answers with no calendar of that type, leaves
  # the type unknown.
  @spec convert_to_locale_calendar(map(), term()) :: {:ok, map()} | {:error, Exception.t()}
  def convert_to_locale_calendar(value, locale) do
    case locale_calendar_type(locale) do
      nil -> {:ok, value}
      calendar_type -> convert_to_calendar_type(value, calendar_type)
    end
  end

  defp locale_calendar_type(%LanguageTag{locale: keywords} = language_tag)
       when is_map(keywords) do
    case locale_keyword(language_tag, :ca) do
      # `iso8601` names ISO 8601's week rules and not a calendar of its own,
      # which `first_day_for_locale/1` and `min_days_for_locale/1` read from
      # the locale; no module answers for it and a date keeps its calendar.
      :iso8601 -> nil
      calendar_type -> calendar_type
    end
  end

  # A tag whose keywords are not a map names no calendar: the caller resolves
  # the locale itself and reports the shape.
  defp locale_calendar_type(%LanguageTag{}), do: nil

  defp locale_calendar_type(locale) do
    case Localize.validate_locale(locale) do
      {:ok, language_tag} -> locale_calendar_type(language_tag)
      # The caller resolves the locale itself and reports what is wrong with it.
      {:error, _exception} -> nil
    end
  end

  # A time has no calendar to write it in, and a value that is no date keeps
  # whatever fields it was given.
  defp convert_to_calendar_type(%Time{} = value, _calendar_type), do: {:ok, value}

  defp convert_to_calendar_type(value, calendar_type) do
    calendar = Map.get(value, :calendar, Calendar.ISO)

    if cldr_calendar_type(calendar) == calendar_type do
      {:ok, value}
    else
      with {:ok, target} <- calendar_of_type(calendar, calendar_type) do
        convert_value(value, target)
      end
    end
  end

  defp calendar_of_type(calendar, calendar_type) do
    answers = answering(calendar)

    with true <- Code.ensure_loaded?(answers),
         true <- function_exported?(answers, :calendar_from_cldr_calendar_type, 1),
         {:ok, target} <- answers.calendar_from_cldr_calendar_type(calendar_type) do
      {:ok, target}
    else
      _no_calendar ->
        {:error, Localize.UnknownCalendarError.exception(calendar: calendar_type)}
    end
  end

  defp convert_value(%Date{} = value, calendar),
    do: converted(value, Date.convert(value, calendar), calendar)

  defp convert_value(%NaiveDateTime{} = value, calendar),
    do: converted(value, NaiveDateTime.convert(value, calendar), calendar)

  defp convert_value(%DateTime{} = value, calendar),
    do: converted(value, DateTime.convert(value, calendar), calendar)

  defp convert_value(value, _calendar), do: {:ok, value}

  defp converted(_value, {:ok, converted}, _calendar), do: {:ok, converted}

  defp converted(value, {:error, _reason}, calendar),
    do: {:error, Localize.CalendarConversionError.exception(value: value, calendar: calendar)}

  @doc false
  # A date in its calendar's own notation, as the calendar writes it with its
  # `date_to_string/3`, when the calendar writes its dates in one rather than
  # in the locale's formats: "2026-W25-2" for a calendar of weeks. A calendar
  # whose dates are parsed in another calendar (`parsing_calendar/0`) names
  # its days in its own notation, which no locale format writes, so a date
  # written in it reads back as itself. Any other date is `:none`, as is a
  # date with a field that is not an integer, which the calendar is not asked
  # to write: the format that needs the field says which it is.
  @spec notation(map()) :: {:ok, String.t()} | :none | {:error, Exception.t()}
  def notation(%{year: year, month: month, day: day} = date)
      when is_integer(year) and is_integer(month) and is_integer(day) do
    calendar = Map.get(date, :calendar, Calendar.ISO)

    case own_notation?(calendar) do
      {:ok, true} ->
        ask(calendar, :date_to_string, [year, month, day], "a date as a string", &is_binary/1)

      {:ok, false} ->
        :none

      {:error, _exception} = error ->
        error
    end
  end

  def notation(_date), do: :none

  @doc false
  # A date written in its calendar's own notation (`notation/1`), read back
  # by the calendar's `parse_date/1`. The text is that notation only when
  # the calendar writes the date it reads as exactly the text, so text the
  # calendar reads another way, such as an ISO 8601 date, is `:none`, as is
  # any text for a calendar without a notation of its own.
  @spec from_notation(String.t(), module()) :: {:ok, Date.t()} | :none | {:error, Exception.t()}
  def from_notation(text, calendar) do
    with {:ok, true} <- own_notation?(calendar),
         {:ok, {:ok, {year, month, day}}} <-
           ask(calendar, :parse_date, [text], "a date's fields or an error", &parsed_date?/1),
         {:ok, date} <- Date.new(year, month, day, calendar),
         {:ok, ^text} <- notation(date) do
      {:ok, date}
    else
      {:error, %{__exception__: true}} = error -> error
      _not_its_notation -> :none
    end
  end

  defp parsed_date?({:ok, {year, month, day}}),
    do: is_integer(year) and is_integer(month) and is_integer(day)

  defp parsed_date?({:error, _reason}), do: true
  defp parsed_date?(_answer), do: false

  @doc false
  # Whether a calendar writes its dates in a notation of its own rather than
  # in the locale's formats: it does when it reads written dates in another
  # calendar, as its `parsing_calendar/0` answers.
  @spec own_notation?(module()) :: {:ok, boolean()} | {:error, Exception.t()}
  def own_notation?(calendar) do
    with {:ok, parsing} <- parsing_calendar(calendar), do: {:ok, parsing != calendar}
  end

  @typedoc false
  @type date_fields :: {Calendar.year(), Calendar.month(), Calendar.day()}

  @typedoc false
  @type date_part :: :years | :quarters | :months | :weeks | :days

  @doc false
  # Which of two dates of one calendar is the earlier day. `Date.compare/2`
  # orders the dates of one calendar by their fields, which is not their
  # order in a calendar whose year turns after its first month: in a Julian
  # calendar reckoned from 25 March, January follows December of the same
  # year. The calendar's own count of days orders them (`Date.diff/2`).
  @spec compare_days(Date.t(), Date.t()) :: :lt | :eq | :gt
  def compare_days(%Date{} = date, %Date{} = other) do
    case Date.diff(date, other) do
      0 -> :eq
      days when days < 0 -> :lt
      _days -> :gt
    end
  end

  @doc false
  # The whole years, quarters, months, weeks or days from one date of a
  # calendar to another, as the calendar counts them (its `diff/3`): the most
  # its `plus/6` adds to the earlier date without passing the later, and
  # negative when `to` is the earlier. An error when the calendar answers
  # with something that is not a count.
  @spec diff(module(), date_fields(), date_fields(), date_part()) ::
          {:ok, integer()} | {:error, Exception.t()}
  def diff(calendar, from, to, date_part) do
    ask(calendar, :diff, [from, to, date_part], "a number of #{date_part}", &is_integer/1)
  end

  @doc false
  # The date a number of years, quarters, months, weeks or days on from a
  # date, as its calendar reaches it (its `plus/6`), the day brought into a
  # month that is too short for it. An error when the calendar answers with
  # something that is not a year, a month and a day.
  @spec plus(module(), date_fields(), date_part(), integer()) ::
          {:ok, date_fields()} | {:error, Exception.t()}
  def plus(calendar, {year, month, day}, date_part, count) do
    ask(
      calendar,
      :plus,
      [year, month, day, date_part, count, [coerce: true]],
      "a year, a month and a day",
      &date_fields?/1
    )
  end

  @doc false
  # The date a number of years and then months on from a date, as its
  # calendar shifts it (its `shift_date/4`, which `Date.shift/2` calls). A
  # calendar composes the two in its own way: a calendar of months counts
  # the years as months and brings the day into the month reached once, and
  # a calendar of weeks keeps the week in the year reached and counts its
  # months on from there. An error when the calendar answers with something
  # that is not a year, a month and a day.
  @spec shift(module(), date_fields(), integer(), integer()) ::
          {:ok, date_fields()} | {:error, Exception.t()}
  def shift(calendar, {year, month, day}, years, months) do
    ask(
      calendar,
      :shift_date,
      [year, month, day, Duration.new!(year: years, month: months)],
      "a year, a month and a day",
      &date_fields?/1
    )
  end

  defp date_fields?({year, month, day}),
    do: is_integer(year) and is_integer(month) and is_integer(day)

  defp date_fields?(_answer), do: false

  @doc false
  # Puts a question to a calendar: `callback` with `arguments`, to the
  # module `answering/1` names. The answer stands when `valid?` accepts it,
  # and is otherwise an error showing what the calendar answered.
  @spec ask(module(), atom(), list(), String.t(), (term() -> boolean())) ::
          {:ok, term()} | {:error, Exception.t()}
  def ask(calendar, callback, arguments, expected, valid?) do
    answer = apply(answering(calendar), callback, arguments)

    if valid?.(answer) do
      {:ok, answer}
    else
      {:error,
       Localize.InvalidValueError.exception(
         value: answer,
         expected: expected,
         context: inspect(calendar)
       )}
    end
  end

  @doc false
  # A value's calendar must answer Localize's questions: `Calendar.ISO`,
  # answered for by Localize, or a calendar implementing the Calendrical
  # behaviour. Any other calendar is refused where the value enters, rather
  # than failing in a format.
  @spec validate_calendar(term()) :: :ok | {:error, Exception.t()}
  def validate_calendar(%{calendar: calendar}) when calendar != Calendar.ISO do
    if is_atom(calendar) and Code.ensure_loaded?(calendar) and
         Enum.all?(@answers, fn {name, arity} -> function_exported?(calendar, name, arity) end),
       do: :ok,
       else: {:error, Localize.UnknownCalendarError.exception(calendar: calendar)}
  end

  def validate_calendar(_value), do: :ok

  @doc false
  # A value Localize formats must be one its calendar has: the calendar
  # answers (`validate_calendar/1`), and the value's date and time fields
  # name a date and a time the calendar's `valid_date?/3` and `valid_time?/4`
  # accept. Only the fields the value holds are checked, so a year and a
  # month are checked as the month's first day, and a month or a day below 1
  # is no calendar's, as Elixir's `Calendar` types say. A field that is not
  # an integer is left to the format that needs it.
  @spec validate_value(term()) :: :ok | {:error, Exception.t()}
  def validate_value(value) do
    with :ok <- validate_calendar(value),
         :ok <- validate_date(value) do
      validate_time(value)
    end
  end

  defp validate_date(%{} = value) do
    calendar = Map.get(value, :calendar, Calendar.ISO)

    case date_to_check({Map.get(value, :year), Map.get(value, :month), Map.get(value, :day)}) do
      {:check, arguments} -> possible(calendar, :valid_date?, arguments, value)
      :impossible -> impossible(:valid_date?, value, calendar)
      :unchecked -> :ok
    end
  end

  defp validate_date(_value), do: :ok

  # The date a value's fields ask its calendar about: the whole date, or a
  # year and a month as the month's first day. Without them only a month or
  # a day below 1 is known to be no calendar's.
  defp date_to_check({year, month, day})
       when is_integer(year) and is_integer(month) and is_integer(day),
       do: {:check, [year, month, day]}

  defp date_to_check({year, month, _day}) when is_integer(year) and is_integer(month),
    do: {:check, [year, month, 1]}

  defp date_to_check({_year, month, _day}) when is_integer(month) and month < 1, do: :impossible
  defp date_to_check({_year, _month, day}) when is_integer(day) and day < 1, do: :impossible
  defp date_to_check(_fields), do: :unchecked

  # A time without its smaller fields is checked as the start of its hour or
  # minute.
  defp validate_time(%{} = value) do
    fields = Map.take(value, [:hour, :minute, :second, :microsecond])

    arguments = [
      Map.get(fields, :hour, 0),
      Map.get(fields, :minute, 0),
      Map.get(fields, :second, 0),
      Map.get(fields, :microsecond, {0, 0})
    ]

    case arguments do
      _no_time when map_size(fields) == 0 ->
        :ok

      [hour, minute, second, {microsecond, precision}]
      when is_integer(hour) and is_integer(minute) and is_integer(second) and
             is_integer(microsecond) and is_integer(precision) ->
        possible(Map.get(value, :calendar, Calendar.ISO), :valid_time?, arguments, value)

      _not_integers ->
        :ok
    end
  end

  defp validate_time(_value), do: :ok

  defp possible(calendar, callback, arguments, value) do
    case ask(calendar, callback, arguments, "true or false", &is_boolean/1) do
      {:ok, true} -> :ok
      {:ok, false} -> impossible(callback, value, calendar)
      {:error, _not_an_answer} = error -> error
    end
  end

  defp impossible(:valid_date?, value, calendar) do
    {:error,
     Localize.InvalidValueError.exception(
       value: Map.take(value, [:year, :month, :day]),
       expected: "a date its calendar has",
       context: inspect(calendar)
     )}
  end

  defp impossible(:valid_time?, value, calendar) do
    {:error,
     Localize.InvalidValueError.exception(
       value: Map.take(value, [:hour, :minute, :second, :microsecond]),
       expected: "a time its calendar has",
       context: inspect(calendar)
     )}
  end

  @doc false
  # The CLDR month a date's month names, the index of its localized name,
  # as its calendar answers: `month_of_year/3` then `cardinal_month/1`, and
  # `{month, :leap}` for a leap month. A date without its day is taken on
  # the first; one without its year has its month named by
  # `cardinal_month/1` alone. `nil` when the date has no month, and an
  # error when its calendar answers with something that is not a month.
  @spec cldr_month(map()) ::
          Calendar.month() | {Calendar.month(), :leap} | nil | {:error, Exception.t()}
  def cldr_month(%{month: month} = date) when is_integer(month) do
    calendar = Map.get(date, :calendar, Calendar.ISO)
    answers = answering(calendar)

    case date do
      %{year: year} when is_integer(year) ->
        day = Map.get(date, :day)
        day = if is_integer(day), do: day, else: 1
        cardinal(answers.month_of_year(year, month, day), answers, calendar)

      _no_year ->
        cardinal(month, answers, calendar)
    end
  end

  def cldr_month(_date), do: nil

  defp cardinal({month, :leap}, answers, calendar) when is_integer(month) do
    with month when is_integer(month) <- cardinal(month, answers, calendar) do
      {month, :leap}
    end
  end

  defp cardinal(month, answers, calendar) when is_integer(month) do
    case answers.cardinal_month(month) do
      cardinal when is_integer(cardinal) -> cardinal
      other -> not_a_month(other, calendar)
    end
  end

  defp cardinal(other, _answers, calendar), do: not_a_month(other, calendar)

  defp not_a_month(answer, calendar) do
    {:error,
     Localize.InvalidValueError.exception(
       value: answer,
       expected: "a month",
       context: inspect(calendar)
     )}
  end

  @doc false
  # The day of the week, 1 for Monday to 7 for Sunday, as the date's
  # calendar answers it; a map without a calendar is an ISO date. An error
  # for a date without its year, month or day, which is no day of any week
  # and was named as Monday, and when its calendar answers with something
  # that is not a day of the week.
  @spec day_of_week(map()) :: {:ok, 1..7} | {:error, Exception.t()}
  def day_of_week(%{} = date) do
    calendar = Map.get(date, :calendar, Calendar.ISO)
    arguments = [Map.get(date, :year), Map.get(date, :month), Map.get(date, :day), :monday]

    with :ok <- holds_part(date, :day_of_week),
         {:ok, {day_of_week, _first, _last}} <-
           ask(calendar, :day_of_week, arguments, "a day of the week", &day_of_week?/1) do
      {:ok, day_of_week}
    end
  end

  defp day_of_week?({day, _first, _last}), do: day in 1..7
  defp day_of_week?(_answer), do: false

  @doc false
  # The quarter of the year a date is in, as its calendar answers it (its
  # `quarter_of_year/3`), which puts a thirteenth month in the last quarter
  # and a calendar of weeks' weeks in theirs; a map without a calendar is an
  # ISO date, and one without its day is taken on the first. An error when
  # the calendar answers with something that is not a quarter.
  @spec quarter_of_year(map()) :: {:ok, 1..4} | {:error, Exception.t()}
  def quarter_of_year(%{year: year, month: month} = date)
      when is_integer(year) and is_integer(month) do
    day = Map.get(date, :day)
    day = if is_integer(day), do: day, else: 1

    ask(
      Map.get(date, :calendar, Calendar.ISO),
      :quarter_of_year,
      [year, month, day],
      "a quarter of the year",
      &(&1 in 1..4)
    )
  end

  # A calendar's weeks are its own: its `week_of_year/3`, `week_of_month/3`
  # and `week/2` answer for them. `Calendar.ISO` has no weeks of its own, so
  # its weeks are the locale's, numbered as TR35 numbers them from the
  # locale's week data: the first day of the week and the fewest days of a
  # year, or a month, that its week 1 holds (`Localize.DateTime.Week.config/1`).
  # The questions below take that data and put it, with the question, to
  # `Calendar.ISO` alone (user, 2026-10-02).
  @typedoc false
  @type week_data :: {1..7, 1..7}

  defp week_question(Calendar.ISO, arguments, week_data), do: arguments ++ [week_data]
  defp week_question(_calendar, arguments, _week_data), do: arguments

  @doc false
  # The week-based year a date's week belongs to and its week of that year,
  # as its calendar answers them (its `week_of_year/3`), or in the locale's
  # weeks for `Calendar.ISO`. A map without a calendar is an ISO date. An
  # error when the calendar answers with something that is not a year and a
  # week.
  @spec week_of_year(map(), week_data()) ::
          {:ok, {integer(), pos_integer()}} | {:error, [atom()] | Exception.t()}
  def week_of_year(%{year: year, month: month, day: day} = date, week_data)
      when is_integer(year) and is_integer(month) and is_integer(day) do
    calendar = Map.get(date, :calendar, Calendar.ISO)

    ask(
      calendar,
      :week_of_year,
      week_question(calendar, [year, month, day], week_data),
      "a week-based year and a week",
      fn
        {week_year, week} -> is_integer(week_year) and is_integer(week)
        _other -> false
      end
    )
  end

  # A date without its day is in the week that the first and the last of the
  # days it could be are both in: the week a calendar of weeks' year and week
  # name, its month field holding a week. A month of days runs through
  # several weeks, and `{:error, [:day]}` names the field that would say
  # which.
  def week_of_year(%{year: year, month: month} = date, week_data)
      when is_integer(year) and is_integer(month) do
    calendar = Map.get(date, :calendar, Calendar.ISO)

    with {:ok, {first, last, unsettled}} <- date_span(date, calendar, year),
         {:ok, first_week} <- week_of_year(on_day(date, first), week_data),
         {:ok, last_week} <- week_of_year(on_day(date, last), week_data) do
      if first_week == last_week, do: {:ok, first_week}, else: {:error, unsettled}
    end
  end

  def week_of_year(_date, _week_data), do: {:error, [:year, :month]}

  defp on_day(date, {year, month, day}),
    do: Map.merge(date, %{year: year, month: month, day: day})

  @doc false
  # The week of the month a date is in and the month that week belongs to,
  # as its calendar answers them (its `week_of_month/3`), or in the locale's
  # weeks for `Calendar.ISO`. A map without a calendar is an ISO date. An
  # error when the calendar answers with something that is not a month and a
  # week.
  @spec week_of_month(map(), week_data()) ::
          {:ok, {Calendar.month(), pos_integer()}} | {:error, Exception.t()}
  def week_of_month(%{year: year, month: month, day: day} = date, week_data)
      when is_integer(year) and is_integer(month) and is_integer(day) do
    calendar = Map.get(date, :calendar, Calendar.ISO)

    ask(
      calendar,
      :week_of_month,
      week_question(calendar, [year, month, day], week_data),
      "a month and a week of the month",
      fn
        {month, week} -> is_integer(month) and is_integer(week)
        _other -> false
      end
    )
  end

  @doc false
  # The days of week `week` of week-based year `year` in a calendar's own
  # weeks, as it answers them (its `week/2`), or in the locale's weeks for
  # `Calendar.ISO`: the days the formatter writes that year and week for.
  @spec week(module(), integer(), integer(), week_data()) ::
          {:ok, Date.Range.t()} | {:error, Exception.t()}
  def week(calendar, year, week, week_data) do
    ask(
      calendar,
      :week,
      week_question(calendar, [year, week], week_data),
      "the days of a week",
      &match?(%Date.Range{}, &1)
    )
  end

  @doc false
  # The day a date's week of the month is named by: the date itself when its
  # week belongs to its own month, else a day of that week in the month the
  # week belongs to, which the rule for a month's weeks can make the month
  # before or after the date's. A pattern with `W` writes its month, and the
  # year and era the month is in, from this day, as `Y` writes the year `w`
  # belongs to, so "week W of MMMM" names the week's month.
  @spec week_month_day(map(), week_data()) :: {:ok, map()} | {:error, Exception.t()}
  def week_month_day(%{year: year, month: month, day: day} = date, week_data)
      when is_integer(year) and is_integer(month) and is_integer(day) do
    case week_of_month(date, week_data) do
      {:ok, {^month, _week}} -> {:ok, date}
      {:ok, {week_month, _week}} -> day_in_week_month(date, week_month, week_data)
      {:error, _not_an_answer} = error -> error
    end
  end

  def week_month_day(date, _week_data), do: {:ok, date}

  # The calendar says which days a week holds: the week of the year the date
  # is in (`week_of_year/2`) and that week's days (`week/4`). The first of
  # them in the week's month names it. A calendar of weeks, whose month field
  # is its week and whose week never leaves its month, has no such day and is
  # named by the date.
  defp day_in_week_month(date, week_month, week_data) do
    calendar = Map.get(date, :calendar, Calendar.ISO)

    with {:ok, {week_year, week}} <- week_of_year(date, week_data),
         {:ok, days} <- week(calendar, week_year, week, week_data) do
      case Enum.find(days, &(&1.month == week_month)) do
        %Date{} = day -> {:ok, Map.merge(date, Map.take(day, [:year, :month, :day]))}
        nil -> {:ok, date}
      end
    end
  end

  # CLDR's leap-year name of a month (`7_yeartype_leap`, the Hebrew "Adar II")
  # is keyed by an atom. The keys are built here from the closed set of month
  # numbers, so no atom is made at runtime.
  @leap_year_name_keys Map.new(1..13, &{&1, :"#{&1}_yeartype_leap"})

  defp month_name({month, :leap}, options), do: leap_month_name(month, options)
  defp month_name(month, options), do: display_name(:month, month, options)

  # A leap month takes CLDR's leap-year name for its month where the calendar
  # has one, and otherwise its month's name in the calendar's leap-month
  # pattern (the Chinese "Second Monthbis"), or the month's name alone.
  defp leap_month_name(month, options) do
    with {:ok, name} <- display_name(:month, month, options) do
      key = Map.get(@leap_year_name_keys, month)

      case lookup_calendar_field(:months, key, options, "a leap-year month name") do
        {:ok, leap_year_name} -> {:ok, leap_year_name}
        {:error, _no_leap_year_name} -> {:ok, in_leap_month_pattern(name, options)}
      end
    end
  end

  defp in_leap_month_pattern(name, options) do
    locale = Keyword.get(options, :locale, Localize.get_locale())
    calendar_type = Keyword.get(options, :calendar, @default_calendar_type)
    context = Keyword.get(options, :context, :format)
    style = Keyword.get(options, :style, :wide)

    with {:ok, patterns} <- month_patterns(locale, calendar_type),
         pattern when is_list(pattern) <- get_in(patterns, [context, style, :leap]) do
      [name] |> Localize.Substitution.substitute(pattern) |> IO.iodata_to_binary()
    else
      _no_leap_month_pattern -> name
    end
  end
end
