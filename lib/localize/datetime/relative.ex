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
  @day 86400
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

  """
  @spec to_string(integer() | Date.t() | DateTime.t() | Time.t(), Keyword.t()) ::
          {:ok, String.t()} | {:error, Exception.t()}
  def to_string(relative, options \\ []) do
    locale = Keyword.get(options, :locale, Localize.get_locale())
    format = Keyword.get(options, :format, :standard)
    unit = Keyword.get(options, :unit)
    relative_to = Keyword.get_lazy(options, :relative_to, &DateTime.utc_now/0)

    with {:ok, locale_id} <- resolve_locale_id(locale),
         {:ok, unit} <- validate_unit(unit),
         {:ok, format} <- validate_format(format),
         {:ok, time_difference} <- time_difference(relative, relative_to) do
      {scaled, resolved_unit} =
        derive_unit(relative, relative_to, time_difference, unit)

      case format_relative(scaled, resolved_unit, format, locale_id) do
        {:ok, _} = result -> result
        nil -> {:ok, Kernel.to_string(scaled)}
      end
    end
  end

  @doc """
  Same as `to_string/2` but raises on error.

  """
  @spec to_string!(integer() | Date.t() | DateTime.t() | Time.t(), Keyword.t()) :: String.t()
  def to_string!(relative, options \\ []) do
    case to_string(relative, options) do
      {:ok, string} -> string
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Returns the list of known time units.

  """
  @spec known_units() :: [atom()]
  def known_units, do: @unit_keys

  # ── Core formatting ───────────────────────────────────────

  defp format_relative(relative, unit, format, locale_id) do
    with {:ok, date_fields} <- Localize.Locale.get(locale_id, [:date_fields]) do
      unit_data = get_in(date_fields, [unit, format])

      cond do
        is_nil(unit_data) ->
          {:ok, Kernel.to_string(relative)}

        # Special ordinal forms: "yesterday", "tomorrow", "today", etc.
        relative in -2..2 and is_map(unit_data[:relative_ordinal]) ->
          case Map.get(unit_data[:relative_ordinal], relative) do
            nil ->
              format_with_pattern(relative, unit_data, locale_id)

            result ->
              {:ok, result}
          end

        true ->
          format_with_pattern(relative, unit_data, locale_id)
      end
    end
  end

  defp format_with_pattern(relative, unit_data, locale_id) do
    direction = if relative > 0, do: :relative_future, else: :relative_past
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
       expected: "a valid time unit: #{inspect(@unit_keys)}",
       context: "Localize.DateTime.Relative"
     )}
  end

  defp validate_format(format) when format in @known_formats, do: {:ok, format}

  defp validate_format(format) do
    {:error,
     Localize.InvalidValueError.exception(
       value: format,
       expected: "one of #{inspect(@known_formats)}",
       context: "Localize.DateTime.Relative"
     )}
  end

  defp resolve_locale_id(%Localize.LanguageTag{cldr_locale_id: id}), do: {:ok, id}

  defp resolve_locale_id(locale) when is_atom(locale) or is_binary(locale) do
    case Localize.validate_locale(locale) do
      {:ok, tag} -> {:ok, tag.cldr_locale_id}
      error -> error
    end
  end
end
