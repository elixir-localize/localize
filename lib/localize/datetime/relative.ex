defmodule Localize.DateTime.Relative do
  @moduledoc """
  Formats relative time strings such as "3 days ago", "tomorrow",
  or "in 10 seconds".

  Supports integer offsets (in seconds), `Date`, `DateTime`,
  `NaiveDateTime`, and `Time` structs.

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

  * `relative` is an integer (seconds from now), or a `Date`,
    `DateTime`, `NaiveDateTime`, or `Time` struct.

  * `options` is a keyword list of options.

  ### Options

  * `:locale` is a locale identifier. The default is `:en`.

  * `:format` is `:standard`, `:narrow`, or `:short`.
    The default is `:standard`.

  * `:unit` is the time unit for formatting. One of `:second`,
    `:minute`, `:hour`, `:day`, `:week`, `:month`, `:year`,
    `:mon`, `:tue`, `:wed`, `:thu`, `:fri`, `:sat`, `:sun`,
    `:quarter`. If omitted, a unit is derived automatically.

  * `:numeric` is `:auto` or `:always`, mirroring ECMA-402's
    `numeric` option. With `:auto` (the default), named forms
    such as "yesterday" and "tomorrow" are used when the locale
    defines them. With `:always`, output is always numeric:
    "1 day ago" instead of "yesterday".

  * `:relative_to` is the baseline date/datetime from which
    the difference is calculated. Defaults to now.

  ### Returns

  * `{:ok, formatted_string}` on success.

  * `{:error, exception}` on failure.

  ### Examples

      iex> Localize.DateTime.Relative.to_string(-1, unit: :day, locale: :en)
      {:ok, "yesterday"}

      iex> Localize.DateTime.Relative.to_string(1, unit: :day, locale: :en)
      {:ok, "tomorrow"}

      iex> Localize.DateTime.Relative.to_string(-3, unit: :day, locale: :en)
      {:ok, "3 days ago"}

      iex> Localize.DateTime.Relative.to_string(2, unit: :hour, locale: :en)
      {:ok, "in 2 hours"}

      iex> Localize.DateTime.Relative.to_string(-1, unit: :day, locale: :en, numeric: :always)
      {:ok, "1 day ago"}

      iex> Localize.DateTime.Relative.to_string(1, unit: :day, locale: :en, numeric: :always)
      {:ok, "in 1 day"}

  """
  @spec to_string(integer() | Date.t() | DateTime.t() | Time.t(), Keyword.t()) ::
          {:ok, String.t()} | {:error, Exception.t()}
  def to_string(relative, options \\ []) do
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
      {scaled, resolved_unit} =
        derive_unit(relative, relative_to, time_difference, unit)

      case format_relative(scaled, resolved_unit, format, locale_id, numeric) do
        {:ok, _} = result -> result
        {:error, _} -> {:ok, Kernel.to_string(scaled)}
      end
    end
  end

  @doc """
  Same as `to_string/2` but raises on error.

  ### Options

  See `to_string/2` for the supported options.

  ### Examples

      iex> Localize.DateTime.Relative.to_string!(-3, unit: :day, locale: :en)
      "3 days ago"

      iex> Localize.DateTime.Relative.to_string!(~D[2024-06-14], relative_to: ~D[2024-06-15], locale: :en)
      "yesterday"

  """
  @spec to_string!(integer() | Date.t() | DateTime.t() | Time.t(), Keyword.t()) :: String.t()
  def to_string!(relative, options \\ []) do
    case to_string(relative, options) do
      {:ok, string} -> string
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Formats a relative time into typed parts, mirroring ECMA-402's `formatToParts` for `Intl.RelativeTimeFormat`.

  The parts concatenate to exactly the string `to_string/2` produces with the same options. Named forms ("yesterday") are a single `:literal` part; pattern forms tag the number as an `:integer` part carrying a `:unit` key ("3 days ago" is `:integer` "3" plus `:literal` " days ago"), matching the JS part shape.

  ### Arguments

  * `relative` is an integer, float, `Date`, `Time`, `DateTime`, or `NaiveDateTime`.

  * `options` is a keyword list of options.

  ### Options

  See `to_string/2` for the supported options.

  ### Returns

  * `{:ok, parts}` where `parts` is a list of `%{type: atom(), value: String.t()}` maps; `:integer` parts also carry a `:unit` key.

  * `{:error, exception}` if the options are invalid.

  ### Examples

      iex> Localize.DateTime.Relative.to_parts(-1, unit: :day, locale: :en)
      {:ok, [%{type: :literal, value: "yesterday"}]}

      iex> Localize.DateTime.Relative.to_parts(-3, unit: :day, locale: :en)
      {:ok,
       [
         %{type: :integer, value: "3", unit: :day},
         %{type: :literal, value: " days ago"}
       ]}

      iex> Localize.DateTime.Relative.to_parts(1, unit: :day, locale: :en, numeric: :always)
      {:ok,
       [
         %{type: :literal, value: "in "},
         %{type: :integer, value: "1", unit: :day},
         %{type: :literal, value: " day"}
       ]}

  """
  @spec to_parts(integer() | Date.t() | DateTime.t() | Time.t(), Keyword.t()) ::
          {:ok, [%{type: atom(), value: String.t()}]} | {:error, Exception.t()}
  def to_parts(relative, options \\ []) do
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
      {scaled, resolved_unit} =
        derive_unit(relative, relative_to, time_difference, unit)

      case parts_relative(scaled, resolved_unit, format, locale_id, numeric) do
        {:ok, _} = result -> result
        {:error, _} -> {:ok, [number_part(scaled, resolved_unit)]}
      end
    end
  end

  @doc """
  Same as `to_parts/2` but raises on error.

  ### Arguments

  * `relative` is an integer, float, `Date`, `Time`, `DateTime`, or `NaiveDateTime`.

  * `options` is a keyword list of options. See `to_parts/2`.

  ### Returns

  * A list of `%{type: atom(), value: String.t()}` maps.

  ### Raises

  * Raises an exception if the options are invalid.

  ### Examples

      iex> Localize.DateTime.Relative.to_parts!(-1, unit: :day, locale: :en)
      [%{type: :literal, value: "yesterday"}]

  """
  @spec to_parts!(integer() | Date.t() | DateTime.t() | Time.t(), Keyword.t()) ::
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

  # ── Core formatting ───────────────────────────────────────

  defp format_relative(relative, unit, format, locale_id, numeric) do
    with {:ok, date_fields} <- Localize.Locale.get(locale_id, [:date_fields]) do
      unit_data = get_in(date_fields, [unit, format])

      cond do
        is_nil(unit_data) ->
          {:ok, Kernel.to_string(relative)}

        # Special ordinal forms: "yesterday", "tomorrow", "today", etc.
        # Skipped entirely under `numeric: :always` (ECMA-402), which
        # forces the plural-rule pattern path below.
        numeric == :auto and relative in -2..2 and is_map(unit_data[:relative_ordinal]) ->
          format_ordinal_or_pattern(relative, unit_data, locale_id)

        true ->
          format_with_pattern(relative, unit_data, locale_id)
      end
    end
  end

  # Use the special ordinal form ("yesterday", "tomorrow", ...)
  # when one exists for the value, otherwise fall back to the
  # plural-rule pattern.
  defp format_ordinal_or_pattern(relative, unit_data, locale_id) do
    case Map.get(unit_data[:relative_ordinal], relative) do
      nil ->
        format_with_pattern(relative, unit_data, locale_id)

      result ->
        {:ok, result}
    end
  end

  defp format_with_pattern(relative, unit_data, locale_id) do
    # Zero formats with the future pattern ("in 0 days") per
    # ECMA-402 and ICU.
    direction = if relative >= 0, do: :relative_future, else: :relative_past
    rules = unit_data[direction]

    if is_nil(rules) do
      {:ok, Kernel.to_string(relative)}
    else
      # Select the correct plural form
      plural_form =
        Localize.Number.PluralRule.Cardinal.plural_rule(abs(relative), locale_id)

      pattern = Map.get(rules, plural_form) || Map.get(rules, :other)

      if pattern do
        formatted_number = Kernel.to_string(abs(trunc(relative)))
        result = Localize.Substitution.substitute(formatted_number, pattern)
        {:ok, Enum.join(result)}
      else
        {:ok, Kernel.to_string(relative)}
      end
    end
  end

  # ── Parts formatting ──────────────────────────────────────

  # The parts sibling of `format_relative/5`: identical selection
  # logic, producing tagged parts instead of a string. The number is
  # rendered the same way `format_with_pattern/3` renders it so the
  # parts always concatenate to the `to_string/2` result.
  defp parts_relative(relative, unit, format, locale_id, numeric) do
    with {:ok, date_fields} <- Localize.Locale.get(locale_id, [:date_fields]) do
      unit_data = get_in(date_fields, [unit, format])

      cond do
        is_nil(unit_data) ->
          {:ok, [number_part(relative, unit)]}

        numeric == :auto and relative in -2..2 and is_map(unit_data[:relative_ordinal]) ->
          parts_ordinal_or_pattern(relative, unit, unit_data, locale_id)

        true ->
          parts_with_pattern(relative, unit, unit_data, locale_id)
      end
    end
  end

  defp parts_ordinal_or_pattern(relative, unit, unit_data, locale_id) do
    case Map.get(unit_data[:relative_ordinal], relative) do
      nil -> parts_with_pattern(relative, unit, unit_data, locale_id)
      result -> {:ok, [%{type: :literal, value: result}]}
    end
  end

  defp parts_with_pattern(relative, unit, unit_data, locale_id) do
    direction = if relative >= 0, do: :relative_future, else: :relative_past
    rules = unit_data[direction]

    if is_nil(rules) do
      {:ok, [number_part(relative, unit)]}
    else
      plural_form =
        Localize.Number.PluralRule.Cardinal.plural_rule(abs(relative), locale_id)

      pattern = Map.get(rules, plural_form) || Map.get(rules, :other)

      if pattern do
        number_parts = [
          %{type: :integer, value: Kernel.to_string(abs(trunc(relative))), unit: unit}
        ]

        {:ok, Localize.Substitution.substitute_parts([number_parts], pattern)}
      else
        {:ok, [number_part(relative, unit)]}
      end
    end
  end

  # Fallback rendering mirrors `to_string/2` exactly: the signed,
  # untruncated value.
  defp number_part(relative, unit) do
    %{type: :integer, value: Kernel.to_string(relative), unit: unit}
  end

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

  defp time_difference(%DateTime{} = relative, _relative_to) do
    {:ok, DateTime.diff(relative, DateTime.utc_now())}
  end

  defp time_difference(%NaiveDateTime{} = relative, %NaiveDateTime{} = relative_to) do
    {:ok, NaiveDateTime.diff(relative, relative_to)}
  end

  defp time_difference(%NaiveDateTime{} = relative, _relative_to) do
    {:ok, NaiveDateTime.diff(relative, NaiveDateTime.utc_now())}
  end

  defp time_difference(%Date{} = relative, %Date{} = relative_to) do
    {:ok, Date.diff(relative, relative_to) * @day}
  end

  defp time_difference(%Date{} = relative, _relative_to) do
    {:ok, Date.diff(relative, Date.utc_today()) * @day}
  end

  defp time_difference(%Time{} = relative, %Time{} = relative_to) do
    {:ok, Time.diff(relative, relative_to)}
  end

  defp time_difference(%Time{} = relative, _relative_to) do
    {:ok, Time.diff(relative, Time.utc_now())}
  end

  # ── Unit derivation ───────────────────────────────────────

  # When the user provides a unit and an integer, use the integer directly
  defp derive_unit(relative, _relative_to, _time_difference, unit)
       when not is_nil(unit) and is_integer(relative) do
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
