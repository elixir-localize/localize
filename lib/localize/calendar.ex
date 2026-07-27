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

  def display_name(:calendar, calendar_type, options) do
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

  def display_name(:date_time_field, field, options) when field in @date_time_fields do
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

  def display_name(:era, era_index, options) do
    lookup_calendar_field(:eras, era_index, options, "a valid era index", style: :wide)
  end

  def display_name(:quarter, quarter, options) when quarter in 1..4 do
    lookup_calendar_field(:quarters, quarter, options, "1..4")
  end

  def display_name(:month, month, options) when month in 1..13 do
    lookup_calendar_field(:months, month, options, "1..13")
  end

  def display_name(:day_of_week, day, options) when day in 1..7 do
    lookup_calendar_field(:days, day, options, "1..7 (ISO day)")
  end

  def display_name(:day_period, period, options) do
    lookup_calendar_field(
      :day_periods,
      period,
      options,
      "a day period atom (:am, :pm, :noon, :midnight, etc.)",
      style: :abbreviated,
      unwrap: true
    )
  end

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

  ### Arguments

  * `datetime` is any `t:Date.t/0`, `t:DateTime.t/0`, or
    `t:NaiveDateTime.t/0`.

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

  * `{:error, exception}` if the part cannot be localized.

  ### Examples

      iex> Localize.Calendar.localize(~D[2019-06-01], :month)
      {:ok, "June"}

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

  def localize(datetime, :era, options) do
    {_, era} = day_of_era(datetime)
    era_key = if options[:era] == :variant, do: -era - 1, else: era

    display_name(:era, era_key, localize_options(datetime, options))
  end

  def localize(datetime, :quarter, options) do
    display_name(:quarter, quarter_of_year(datetime), localize_options(datetime, options))
  end

  def localize(datetime, :month, options) do
    display_name(:month, month_of_year(datetime), localize_options(datetime, options))
  end

  def localize(datetime, :day_of_week, options) do
    display_name(:day_of_week, iso_day_of_week(datetime), localize_options(datetime, options))
  end

  def localize(datetime, :days_of_week, options) do
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

  def localize(%{hour: hour} = datetime, :day_period, options) do
    am_pm = if hour < 12 or rem(hour, 24) < 12, do: :am, else: :pm

    display_name(:day_period, am_pm, localize_options(datetime, options))
  end

  def localize(_datetime, :day_period, _options) do
    {:error,
     Localize.InvalidValueError.exception(
       value: nil,
       expected: "a map with an :hour key",
       context: "Localize.Calendar.localize/3"
     )}
  end

  def localize(_datetime, part, _options) do
    {:error,
     Localize.InvalidValueError.exception(
       value: part,
       expected: "a localizable date part",
       allowed_values: @parts,
       context: "Localize.Calendar.localize/3"
     )}
  end

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

  * `{:error, exception}` if the territory is not known.

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
    week_info = Localize.SupplementalData.weeks()

    case get_in(week_info, [:min_days, territory]) do
      nil ->
        get_in(week_info, [:min_days, @the_world]) || 1

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
    week_info = Localize.SupplementalData.weeks()

    starts =
      get_in(week_info, [:weekend_start, territory]) ||
        get_in(week_info, [:weekend_start, @the_world]) || 6

    ends =
      get_in(week_info, [:weekend_end, territory]) ||
        get_in(week_info, [:weekend_end, @the_world]) || 7

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
  @spec weekdays(atom()) :: [1..7, ...]
  def weekdays(territory) when is_atom(territory) do
    @days -- weekend(territory)
  end

  @doc """
  Returns the first day of the week for a locale.

  A `fw` value in the locale's `-u-` extension takes precedence
  per TR35; otherwise the territory derived from the locale
  determines the first day.

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

  """
  @spec first_day_for_locale(Localize.locale()) :: integer() | {:error, Exception.t()}
  def first_day_for_locale(%LanguageTag{locale: %{fw: fw}}) when not is_nil(fw) do
    Map.fetch!(@first_day_from_fw, fw)
  end

  def first_day_for_locale(%LanguageTag{} = locale) do
    with {:ok, territory} <- territory_from_locale(locale) do
      first_day_for_territory(territory)
    end
  end

  def first_day_for_locale(locale) do
    with {:ok, language_tag} <- Localize.validate_locale(locale) do
      first_day_for_locale(language_tag)
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

  ### Examples

      iex> Localize.Calendar.min_days_for_locale(:en)
      1

      iex> Localize.Calendar.min_days_for_locale(:de)
      4

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

  defp resolve_locale_id(locale), do: Localize.Locale.cldr_locale_id_from(locale)

  defp calendar_type_from(%{calendar: calendar}) do
    Code.ensure_loaded?(calendar)

    if function_exported?(calendar, :cldr_calendar_type, 0) do
      calendar.cldr_calendar_type()
    else
      @default_calendar_type
    end
  end

  defp calendar_type_from(_), do: @default_calendar_type

  # For dates carrying a non-`Calendar.ISO` calendar module
  # (e.g. `Calendrical.Japanese`, `Calendrical.Buddhist`), the
  # calendar's `year_of_era/3` callback returns the correct
  # `{era_year, era_index}` for the date. The earlier
  # year>0 → era 1 fallback is only safe for Gregorian.
  defp day_of_era(%{year: year, month: month, day: day, calendar: calendar})
       when is_atom(calendar) and calendar != Calendar.ISO do
    Code.ensure_loaded?(calendar)

    if function_exported?(calendar, :year_of_era, 3) do
      case calendar.year_of_era(year, month, day) do
        {era_year, era} when is_integer(era) -> {era_year, era}
        _ -> default_day_of_era(year)
      end
    else
      default_day_of_era(year)
    end
  end

  defp day_of_era(%{year: year}), do: default_day_of_era(year)
  defp day_of_era(_), do: {:current, 1}

  defp default_day_of_era(year) when year > 0, do: {:current, 1}
  defp default_day_of_era(_), do: {:before_current, 0}

  defp quarter_of_year(%{month: month}) when is_integer(month) do
    div(month - 1, 3) + 1
  end

  defp quarter_of_year(_), do: 1

  defp month_of_year(%{month: month}) when is_integer(month), do: month
  defp month_of_year(_), do: 1

  defp iso_day_of_week(%{year: year, month: month, day: day, calendar: Calendar.ISO})
       when is_integer(year) and is_integer(month) and is_integer(day) do
    Calendar.ISO.day_of_week(year, month, day, :monday) |> elem(0)
  end

  defp iso_day_of_week(%{year: year, month: month, day: day, calendar: calendar})
       when is_integer(year) and is_integer(month) and is_integer(day) do
    Code.ensure_loaded?(calendar)

    if function_exported?(calendar, :day_of_week, 4) do
      calendar.day_of_week(year, month, day, :monday) |> elem(0)
    else
      Calendar.ISO.day_of_week(year, month, day, :monday) |> elem(0)
    end
  end

  defp iso_day_of_week(%{year: year, month: month, day: day})
       when is_integer(year) and is_integer(month) and is_integer(day) do
    Calendar.ISO.day_of_week(year, month, day, :monday) |> elem(0)
  end

  defp iso_day_of_week(_), do: 1

  defp territory_from_locale(locale) do
    Localize.Territory.territory_from_locale(locale)
  end
end
