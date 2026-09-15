defmodule Localize.DateTime.Relative do
  @moduledoc """
  Formats relative times such as "3 days ago", "tomorrow" or "in 1.5 hours".

  A relative time is a number of units, or the difference between a `t:Date.t/0`, `t:Time.t/0`, `t:NaiveDateTime.t/0` or `t:DateTime.t/0` and a baseline. The number is formatted with the locale's digits and grouping, and the plural category of the number as displayed selects the unit's pattern. `to_string/2` returns the string and `to_parts/2` the same result as typed parts.

  """

  @second 1
  @minute 60
  @hour 3600
  @day 86_400
  @week 604_800
  @month 2_629_743.83
  @year 31_556_926

  @unit_steps %{
    second: @second,
    minute: @minute,
    hour: @hour,
    day: @day,
    week: @week,
    month: @month,
    year: @year
  }

  @other_units [:mon, :tue, :wed, :thu, :fri, :sat, :sun, :quarter]
  @unit_keys Enum.sort(Map.keys(@unit_steps) ++ @other_units)
  @known_formats [:standard, :narrow, :short]

  @doc """
  Returns a string representing a relative time for a given
  number, date, time, or datetime.

  ### Arguments

  * `relative` is a number of `:unit`s, which may be fractional, or a number of seconds when there is no `:unit`. It may instead be a `t:Date.t/0`, `t:Time.t/0`, `t:NaiveDateTime.t/0` or `t:DateTime.t/0`, whose difference from `:relative_to` is formatted.

  * `options` is a keyword list of options.

  ### Options

  * `:locale` is a locale identifier. The number is formatted with the locale's digits and grouping, in the number system a `-u-nu-` extension names if it has one. The default is `Localize.get_locale/0`.

  * `:format` is `:standard`, `:narrow`, or `:short`. The default is `:standard`.

  * `:unit` is the time unit for formatting. One of `:second`, `:minute`, `:hour`, `:day`, `:week`, `:month`, `:quarter`, `:year`, `:mon`, `:tue`, `:wed`, `:thu`, `:fri`, `:sat` or `:sun`. If omitted, a unit is derived from the difference in seconds.

  * `:numeric` is `:auto` or `:always`, mirroring ECMA-402's `numeric` option. With `:auto` (the default), an offset of -2 to 2 takes the unit's named form, such as "yesterday" or "tomorrow", where the locale has one. With `:always`, output is always numeric: "1 day ago" instead of "yesterday".

  * `:relative_to` is the baseline from which the difference is
    calculated. A `t:Date.t/0` or `t:Time.t/0` is measured against a
    value of its own type, a `t:NaiveDateTime.t/0` or a `t:DateTime.t/0`,
    a `t:NaiveDateTime.t/0` against a `t:NaiveDateTime.t/0` or a
    `t:DateTime.t/0`, and a `t:DateTime.t/0` against a `t:DateTime.t/0`.
    Any other pairing returns an error. Defaults to now.

  ### Returns

  * `{:ok, formatted_string}` on success.

  * `{:error, exception}` on failure.

  ### Examples

      iex> Localize.DateTime.Relative.to_string(-1, unit: :day, locale: :en)
      {:ok, "yesterday"}

      iex> Localize.DateTime.Relative.to_string(-3, unit: :day, locale: :en)
      {:ok, "3 days ago"}

      iex> Localize.DateTime.Relative.to_string(1.5, unit: :hour, locale: :en)
      {:ok, "in 1.5 hours"}

      iex> Localize.DateTime.Relative.to_string(-1000, unit: :day, locale: :de)
      {:ok, "vor 1.000 Tagen"}

      iex> Localize.DateTime.Relative.to_string(-1, unit: :day, locale: :en, numeric: :always)
      {:ok, "1 day ago"}

  """
  @spec to_string(number() | Date.t() | Time.t() | NaiveDateTime.t() | DateTime.t(), Keyword.t()) ::
          {:ok, String.t()} | {:error, Exception.t()}
  def to_string(relative, options \\ [])

  def to_string(relative, options) when is_list(options) do
    with {:ok, parts} <- to_parts(relative, options) do
      {:ok, Enum.map_join(parts, & &1.value)}
    end
  end

  def to_string(_relative, options), do: {:error, invalid_options(options)}

  @doc """
  Same as `to_string/2` but raises on error.

  ### Arguments

  * `relative` is a number, or a `t:Date.t/0`, `t:Time.t/0`, `t:NaiveDateTime.t/0` or `t:DateTime.t/0`. See `to_string/2`.

  * `options` is a keyword list of options.

  ### Options

  * See `to_string/2` for the supported options.

  ### Returns

  * The localized relative time as a string.

  ### Raises

  * Raises an exception if the relative time cannot be formatted.

  ### Examples

      iex> Localize.DateTime.Relative.to_string!(-3, unit: :day, locale: :en)
      "3 days ago"

      iex> Localize.DateTime.Relative.to_string!(~D[2024-06-14], relative_to: ~D[2024-06-15], locale: :en)
      "yesterday"

  """
  @spec to_string!(number() | Date.t() | Time.t() | NaiveDateTime.t() | DateTime.t(), Keyword.t()) ::
          String.t()
  def to_string!(relative, options \\ []) do
    case to_string(relative, options) do
      {:ok, string} -> string
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Formats a relative time into typed parts, mirroring ECMA-402's `formatToParts` for `Intl.RelativeTimeFormat`.

  The parts concatenate to exactly the string `to_string/2` produces with the same options. A named form ("yesterday") is a single `:literal` part. A pattern form places the number's parts from `Localize.Number.to_parts/2` (`:integer`, `:group`, `:decimal`, `:fraction`), each carrying a `:unit` key, between `:literal` parts, as ECMA-402 does: "in 1,000 days" is `:literal` "in ", `:integer` "1", `:group` ",", `:integer` "000" and `:literal` " days".

  ### Arguments

  * `relative` is a number, or a `t:Date.t/0`, `t:Time.t/0`, `t:NaiveDateTime.t/0` or `t:DateTime.t/0`.

  * `options` is a keyword list of options.

  ### Options

  See `to_string/2` for the supported options.

  ### Returns

  * `{:ok, parts}` where `parts` is a list of `%{type: atom(), value: String.t()}` maps; the number's parts also carry a `:unit` key.

  * `{:error, exception}` if `relative` or the options are invalid.

  ### Examples

      iex> Localize.DateTime.Relative.to_parts(-1, unit: :day, locale: :en)
      {:ok, [%{type: :literal, value: "yesterday"}]}

      iex> Localize.DateTime.Relative.to_parts(1000, unit: :day, locale: :en)
      {:ok,
       [
         %{type: :literal, value: "in "},
         %{type: :integer, value: "1", unit: :day},
         %{type: :group, value: ",", unit: :day},
         %{type: :integer, value: "000", unit: :day},
         %{type: :literal, value: " days"}
       ]}

  """
  @spec to_parts(number() | Date.t() | Time.t() | NaiveDateTime.t() | DateTime.t(), Keyword.t()) ::
          {:ok, [%{type: atom(), value: String.t()}]} | {:error, Exception.t()}
  def to_parts(relative, options \\ [])

  def to_parts(relative, options) when is_list(options) do
    locale = Keyword.get(options, :locale, Localize.get_locale())
    format = Keyword.get(options, :format, :standard)
    unit = Keyword.get(options, :unit)
    numeric = Keyword.get(options, :numeric, :auto)
    relative_to = Keyword.get_lazy(options, :relative_to, &DateTime.utc_now/0)

    with {:ok, locale_id} <- resolve_locale_id(locale),
         {:ok, unit} <- validate_unit(unit),
         {:ok, format} <- validate_format(format),
         {:ok, numeric} <- validate_numeric(numeric),
         {:ok, time_difference} <- time_difference(relative, relative_to) do
      {scaled, resolved_unit} = derive_unit(relative, relative_to, time_difference, unit)
      {:ok, relative_parts(scaled, resolved_unit, format, locale, locale_id, numeric)}
    end
  end

  def to_parts(_relative, options), do: {:error, invalid_options(options)}

  @doc """
  Same as `to_parts/2` but raises on error.

  ### Arguments

  * `relative` is a number, or a `t:Date.t/0`, `t:Time.t/0`, `t:NaiveDateTime.t/0` or `t:DateTime.t/0`. See `to_string/2`.

  * `options` is a keyword list of options. See `to_parts/2`.

  ### Returns

  * A list of `%{type: atom(), value: String.t()}` maps.

  ### Raises

  * Raises an exception if `relative` or the options are invalid.

  ### Examples

      iex> Localize.DateTime.Relative.to_parts!(-1, unit: :day, locale: :en)
      [%{type: :literal, value: "yesterday"}]

  """
  @spec to_parts!(number() | Date.t() | Time.t() | NaiveDateTime.t() | DateTime.t(), Keyword.t()) ::
          [%{type: atom(), value: String.t()}]
  def to_parts!(relative, options \\ []) do
    case to_parts(relative, options) do
      {:ok, parts} -> parts
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Returns the list of known time units.

  ### Examples

      iex> Localize.DateTime.Relative.known_units()
      [:day, :fri, :hour, :minute, :mon, :month, :quarter, :sat, :second, :sun, :thu, :tue, :wed, :week, :year]

  """
  @spec known_units() :: [atom(), ...]
  def known_units, do: @unit_keys

  # ── Formatting ────────────────────────────────────────────

  # `to_string/2` joins these parts, so the two always agree. A unit the
  # locale has no data for formats as the number alone.
  defp relative_parts(relative, unit, format, locale, locale_id, numeric) do
    with {:ok, date_fields} <- Localize.Locale.get(locale_id, [:date_fields]),
         %{} = unit_data <- get_in(date_fields, [unit, format]) do
      case named_form(relative, unit_data, numeric) do
        nil -> pattern_parts(relative, unit, unit_data, locale, locale_id)
        name -> [%{type: :literal, value: name}]
      end
    else
      _no_data -> number_parts(relative, unit, locale)
    end
  end

  # With `numeric: :auto` an offset of -2 to 2 takes the unit's named form
  # ("yesterday", "this hour") where the locale has one. ICU matches an
  # offset within one percent of those, so 0.9999 days is still "tomorrow".
  defp named_form(relative, %{relative_ordinal: %{} = names}, :auto)
       when relative > -2.1 and relative < 2.1 do
    hundredths = round(relative * 100)

    if rem(hundredths, 100) == 0 do
      Map.get(names, div(hundredths, 100))
    end
  end

  defp named_form(_relative, _unit_data, _numeric), do: nil

  # The number is formatted for the locale, and the pattern is chosen by the
  # plural category of the number as displayed: "in 1.5 days" is `:other` in
  # English and "dans 1,5 jour" `:one` in French. Zero takes the future
  # pattern ("in 0 days"), as in ECMA-402 and ICU.
  defp pattern_parts(relative, unit, unit_data, locale, locale_id) do
    direction = if relative < 0, do: :relative_past, else: :relative_future
    magnitude = abs(relative)

    with %{} = patterns <- unit_data[direction],
         {:ok, number} <- Localize.Number.to_parts(magnitude, locale: locale) do
      category =
        magnitude
        |> Localize.Number.source_number(locale: locale)
        |> Localize.Number.PluralRule.Cardinal.plural_rule(locale_id)

      case Map.get(patterns, category) || Map.get(patterns, :other) do
        nil -> number_parts(relative, unit, locale)
        pattern -> Localize.Substitution.substitute_parts([with_unit(number, unit)], pattern)
      end
    else
      _no_pattern -> number_parts(relative, unit, locale)
    end
  end

  defp number_parts(relative, unit, locale) do
    case Localize.Number.to_parts(relative, locale: locale) do
      {:ok, parts} -> with_unit(parts, unit)
      {:error, _exception} -> [%{type: :integer, value: Kernel.to_string(relative), unit: unit}]
    end
  end

  # As in ECMA-402's `formatToParts`, every part of the number carries the
  # unit.
  defp with_unit(parts, unit), do: Enum.map(parts, &Map.put(&1, :unit, unit))

  # ── Time difference calculation ────────────────────────────

  defp time_difference(relative, _relative_to) when is_integer(relative) do
    {:ok, relative}
  end

  defp time_difference(relative, _relative_to) when is_float(relative) do
    {:ok, trunc(relative)}
  end

  defp time_difference(%DateTime{} = relative, %DateTime{} = relative_to) do
    {:ok, DateTime.diff(relative, relative_to)}
  end

  defp time_difference(%NaiveDateTime{} = relative, %NaiveDateTime{} = relative_to) do
    {:ok, NaiveDateTime.diff(relative, relative_to)}
  end

  # A baseline of another type is converted only where the conversion is
  # unambiguous: a date or time is taken from a datetime, and a naive
  # datetime from a datetime's wall clock. That also covers the default
  # baseline, `DateTime.utc_now/0`. Any other pairing is an error.
  defp time_difference(%NaiveDateTime{} = relative, %DateTime{} = relative_to) do
    {:ok, NaiveDateTime.diff(relative, DateTime.to_naive(relative_to))}
  end

  defp time_difference(%Date{} = relative, %Date{} = relative_to) do
    {:ok, Date.diff(relative, relative_to) * @day}
  end

  defp time_difference(%Date{} = relative, %NaiveDateTime{} = relative_to) do
    {:ok, Date.diff(relative, NaiveDateTime.to_date(relative_to)) * @day}
  end

  defp time_difference(%Date{} = relative, %DateTime{} = relative_to) do
    {:ok, Date.diff(relative, DateTime.to_date(relative_to)) * @day}
  end

  defp time_difference(%Time{} = relative, %Time{} = relative_to) do
    {:ok, Time.diff(relative, relative_to)}
  end

  defp time_difference(%Time{} = relative, %NaiveDateTime{} = relative_to) do
    {:ok, Time.diff(relative, NaiveDateTime.to_time(relative_to))}
  end

  defp time_difference(%Time{} = relative, %DateTime{} = relative_to) do
    {:ok, Time.diff(relative, DateTime.to_time(relative_to))}
  end

  defp time_difference(%DateTime{}, relative_to) do
    {:error, invalid_baseline(relative_to, "a DateTime")}
  end

  defp time_difference(%NaiveDateTime{}, relative_to) do
    {:error, invalid_baseline(relative_to, "a NaiveDateTime or DateTime")}
  end

  defp time_difference(%Date{}, relative_to) do
    {:error, invalid_baseline(relative_to, "a Date, NaiveDateTime or DateTime")}
  end

  defp time_difference(%Time{}, relative_to) do
    {:error, invalid_baseline(relative_to, "a Time, NaiveDateTime or DateTime")}
  end

  defp time_difference(relative, _relative_to) do
    {:error,
     Localize.InvalidValueError.exception(
       value: relative,
       expected: "an integer, float, Date, Time, NaiveDateTime or DateTime"
     )}
  end

  defp invalid_options(options) do
    Localize.InvalidValueError.exception(value: options, expected: "a keyword list of options")
  end

  defp invalid_baseline(relative_to, expected) do
    Localize.InvalidValueError.exception(
      value: relative_to,
      expected: expected,
      context: ":relative_to"
    )
  end

  # ── Unit derivation ───────────────────────────────────────

  # A number with a unit is a count of that unit, whole or fractional.
  defp derive_unit(relative, _relative_to, _time_difference, unit)
       when not is_nil(unit) and is_number(relative) do
    {relative, unit}
  end

  # When a unit is specified but relative is a date/datetime, scale the difference
  defp derive_unit(_relative, _relative_to, time_difference, unit) when not is_nil(unit) do
    scaled = scale_relative(time_difference, unit)
    {scaled, unit}
  end

  # No unit — derive from the time difference magnitude
  defp derive_unit(_relative, _relative_to, time_difference, nil) do
    unit = unit_from_time(abs(time_difference))
    scaled = scale_relative(time_difference, unit)
    {scaled, unit}
  end

  defp unit_from_time(seconds) do
    cond do
      seconds < @minute -> :second
      seconds < @hour -> :minute
      seconds < @day -> :hour
      seconds < @week -> :day
      seconds < @month -> :week
      seconds < @year -> :month
      true -> :year
    end
  end

  defp scale_relative(time_difference, unit) do
    step = Map.get(@unit_steps, unit, 1)
    (time_difference / step) |> Float.round() |> trunc()
  end

  # ── Validation ─────────────────────────────────────────────

  defp validate_unit(nil), do: {:ok, nil}
  defp validate_unit(unit) when unit in @unit_keys, do: {:ok, unit}

  defp validate_unit(unit) do
    {:error,
     Localize.InvalidValueError.exception(
       value: unit,
       expected: :time_unit,
       allowed_values: @unit_keys,
       context: "Localize.DateTime.Relative"
     )}
  end

  defp validate_format(format) when format in @known_formats, do: {:ok, format}

  defp validate_format(format) do
    {:error,
     Localize.InvalidValueError.exception(
       value: format,
       expected: :format,
       allowed_values: @known_formats,
       context: "Localize.DateTime.Relative"
     )}
  end

  defp validate_numeric(numeric) when numeric in [:auto, :always], do: {:ok, numeric}

  defp validate_numeric(numeric) do
    {:error,
     Localize.InvalidValueError.exception(
       value: numeric,
       expected: :numeric,
       allowed_values: [:auto, :always],
       context: "Localize.DateTime.Relative"
     )}
  end

  defp resolve_locale_id(locale), do: Localize.Locale.cldr_locale_id_from(locale)
end
