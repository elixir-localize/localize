defmodule Localize.DateTime do
  @moduledoc """
  Provides localized formatting of `DateTime`, `NaiveDateTime`,
  and datetime-like maps.

  The primary function is `to_string/2` which accepts a datetime
  value and an options keyword list. Format patterns are defined
  in CLDR and described in
  [TR35](http://unicode.org/reports/tr35/tr35-dates.html).

  ## Predefined formats

  * `:short` — abbreviated date and time (e.g., "1/2/25, 3:04 PM").

  * `:medium` — standard date and time (default).

  * `:long` — includes time zone name.

  * `:full` — verbose day-of-week, date, and time zone.

  Custom CLDR skeleton strings and raw format patterns are also
  supported via the `:format` option.

  """

  import Kernel, except: [to_string: 1]

  @default_format :medium
  @standard_formats [:short, :medium, :long, :full]

  @doc """
  Formats a datetime according to a CLDR format pattern.

  ### Arguments

  * `datetime` is a `t:DateTime.t/0`, `t:NaiveDateTime.t/0`,
    or any map with date and time keys.

  * `options` is a keyword list of options.

  ### Options

  * `:format` is a standard format name (`:short`, `:medium`,
    `:long`, `:full`) or a format pattern string. The default
    is `:medium`. It sets the width of the date and the time
    together; `:date_format` and `:time_format` override each
    axis separately.

  * `:date_format` and `:time_format` are standard format names
    that set the width of the date half and the time half
    independently, each defaulting to `:format`. Use them for
    the common "full date, short time" pairing:
    `date_format: :full, time_format: :short` renders
    "Wednesday, April 8, 2026, 12:00 PM". When `:date_format`
    is given it also selects the wrapper width.

  * `:style` selects the CLDR pattern that joins the date and
    the time. `:default` (the default) uses the standard
    wrapper ("April 8, 2026, 12:00:00 PM"); `:at` uses the
    locale's "at time" wrapper ("April 8, 2026 at 12:00:00 PM",
    de "8. April 2026 um 12:00:00"). CLDR defines the "at time"
    wrapper only for `:full` and `:long`, so `:at` falls back to
    the standard wrapper for `:medium` and `:short`.

  * `:locale` is a locale identifier. The default is `:en`.

  * `:number_system` is a CLDR numbering system name (for example, `:thai`). All numeric fields render in that system; a `-u-nu-` locale extension may be used instead. The default is the locale's number system.

  * `:prefer` selects between CLDR `alt` variants. Accepts an
    atom or a list of atoms in priority order. Recognised values:
    `:standard` / `:variant` (locales like en-CA publish both an
    ISO pattern `"y-MM-dd"` and a locale-variant `"d/M/yy"`),
    and `:unicode` / `:ascii` (mostly time formats — NBSP and
    curly quotes vs ASCII-only). Examples: `prefer: :variant`,
    `prefer: [:variant, :ascii]`. The default is
    `[:standard, :unicode]`.

  ### Returns

  * `{:ok, formatted_string}` on success.

  * `{:error, exception}` if the datetime cannot be formatted.

  ### Examples

      iex> Localize.DateTime.to_string(~N[2017-07-10 14:30:00], locale: :en, prefer: :ascii)
      {:ok, "Jul 10, 2017, 2:30:00 PM"}

      iex> Localize.DateTime.to_string(~N[2017-07-10 14:30:00], format: :short, locale: :en, prefer: :ascii)
      {:ok, "7/10/17, 2:30 PM"}

  """
  @spec to_string(map(), Keyword.t()) :: {:ok, String.t()} | {:error, Exception.t()}
  def to_string(datetime, options \\ []) do
    do_format(datetime, options, :string)
  end

  # Full datetime: year, month, day, hour, minute, second all present.
  # The `output` mode (:string | :parts) selects the formatter entry
  # point at each terminal, so `to_string/2` and `to_parts/2` share
  # every resolution path.
  defp do_format(
         %{year: _, month: _, day: _, hour: _, minute: _, second: _} = datetime,
         options,
         output
       ) do
    locale = Keyword.get(options, :locale, Localize.get_locale())
    format = Keyword.get(options, :format, @default_format)
    style = Keyword.get(options, :style, :default)
    options = Keyword.put_new(options, :locale, locale)

    with {:ok, locale_id} <- resolve_locale_id(locale) do
      cond do
        # Explicit pattern string — format directly
        is_binary(format) ->
          invoke_formatter(output, datetime, format, locale_id, Map.new(options))

        # Standard format with separate date/time formats — use wrapper
        format in @standard_formats or
            (Keyword.has_key?(options, :date_format) and
               Keyword.has_key?(options, :time_format)) ->
          format_with_wrapper(datetime, options, locale_id, format, style, output)

        # Skeleton atom — resolve to a pattern from available_formats
        is_atom(format) ->
          format_with_skeleton(datetime, options, locale_id, format, output)

        true ->
          {:error,
           Localize.DateTimeFormatError.exception(format: format, reason: :invalid_format)}
      end
    end
  end

  # Partial datetime: full date plus at least one time field but not all.
  # Render the date and time portions independently (each deriving a
  # skeleton from the fields actually present, via the existing
  # `Localize.Date` / `Localize.Time` partial paths) and compose them
  # with the locale's datetime wrapper pattern.
  defp do_format(%{year: _, month: _, day: _, hour: _} = datetime, options, output) do
    format_partial_datetime(datetime, options, output)
  end

  defp do_format(datetime, options, output) when is_map(datetime) do
    # Try as date-only or time-only
    cond do
      Map.has_key?(datetime, :year) and Map.has_key?(datetime, :month) ->
        case output do
          :string -> Localize.Date.to_string(datetime, options)
          :parts -> Localize.Date.to_parts(datetime, options)
        end

      Map.has_key?(datetime, :hour) ->
        case output do
          :string -> Localize.Time.to_string(datetime, options)
          :parts -> Localize.Time.to_parts(datetime, options)
        end

      true ->
        {:error, Localize.DateTimeInvalidInputError.exception(type: :datetime)}
    end
  end

  defp do_format(_invalid, _options, _output) do
    {:error, Localize.DateTimeInvalidInputError.exception(type: :datetime)}
  end

  defp invoke_formatter(:string, datetime, pattern, locale_id, options_map) do
    Localize.DateTime.Formatter.format(datetime, pattern, locale_id, options_map)
  end

  defp invoke_formatter(:parts, datetime, pattern, locale_id, options_map) do
    Localize.DateTime.Formatter.format_to_parts(datetime, pattern, locale_id, options_map)
  end

  @doc """
  Same as `to_string/2` but raises on error.

  ### Arguments

  * `datetime` is a `t:DateTime.t/0`, `t:NaiveDateTime.t/0`,
    or any map with date and time keys.

  * `options` is a keyword list of options.

  ### Options

  See `to_string/2` for the supported options.

  ### Returns

  * A formatted string.

  * Raises an exception if the datetime cannot be formatted.

  ### Examples

      iex> Localize.DateTime.to_string!(~N[2017-07-10 14:30:00], locale: :en, prefer: :ascii)
      "Jul 10, 2017, 2:30:00 PM"

      iex> Localize.DateTime.to_string!(~N[2017-07-10 14:30:00], format: :short, locale: :en, prefer: :ascii)
      "7/10/17, 2:30 PM"

  """
  @spec to_string!(map(), Keyword.t()) :: String.t()
  def to_string!(datetime, options \\ []) do
    case to_string(datetime, options) do
      {:ok, string} -> string
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Formats a datetime into typed parts, mirroring ECMA-402's `formatToParts`.

  The parts concatenate to exactly the string `to_string/2` produces with the same options. Each pattern field is tagged with its type (`:year`, `:month`, `:day`, `:weekday`, `:hour`, `:minute`, `:second`, `:day_period`, `:time_zone_name`, `:era`, `:fractional_second`, `:literal`, …). Standard formats, skeleton atoms, explicit pattern strings, and combined date+time wrappers all decompose.

  ### Arguments

  * `datetime` is a `t:DateTime.t/0`, `t:NaiveDateTime.t/0`, or any map with date and time keys.

  * `options` is a keyword list of options.

  ### Options

  See `to_string/2` for the supported options.

  ### Returns

  * `{:ok, parts}` where `parts` is a list of `%{type: atom(), value: String.t()}` maps.

  * `{:error, exception}` if the datetime cannot be formatted.

  ### Examples

      iex> Localize.DateTime.to_parts(~N[2017-07-10 14:30:00], format: :hm, locale: :en, prefer: :ascii)
      {:ok,
       [
         %{type: :hour, value: "2"},
         %{type: :literal, value: ":"},
         %{type: :minute, value: "30"},
         %{type: :literal, value: " "},
         %{type: :day_period, value: "PM"}
       ]}

  """
  @spec to_parts(map(), Keyword.t()) ::
          {:ok, [%{type: atom(), value: String.t()}]} | {:error, Exception.t()}
  def to_parts(datetime, options \\ []) do
    do_format(datetime, options, :parts)
  end

  @doc """
  Same as `to_parts/2` but raises on error.

  ### Arguments

  * `datetime` is a `t:DateTime.t/0`, `t:NaiveDateTime.t/0`, or any map with date and time keys.

  * `options` is a keyword list of options. See `to_parts/2`.

  ### Returns

  * A list of `%{type: atom(), value: String.t()}` maps.

  ### Raises

  * Raises an exception if the datetime cannot be formatted.

  ### Examples

      iex> Localize.DateTime.to_parts!(~N[2017-07-10 14:30:00], format: :hm, locale: :en, prefer: :ascii) |> length()
      5

  """
  @spec to_parts!(map(), Keyword.t()) :: [%{type: atom(), value: String.t()}]
  def to_parts!(datetime, options \\ []) do
    case to_parts(datetime, options) do
      {:ok, parts} -> parts
      {:error, exception} -> raise exception
    end
  end

  defp format_partial_datetime(datetime, options, output) do
    locale = Keyword.get(options, :locale, Localize.get_locale())
    options = Keyword.put_new(options, :locale, locale)
    format = Keyword.get(options, :format, @default_format)

    date_format = Keyword.get(options, :date_format, format)
    time_format = Keyword.get(options, :time_format, format)
    # The wrapper level follows the date format when explicit, otherwise
    # the requested top-level format. Non-standard atoms fall back to
    # `:medium` for wrapper selection only.
    wrapper_level =
      cond do
        date_format in @standard_formats -> date_format
        format in @standard_formats -> format
        true -> :medium
      end

    date_only = Map.drop(datetime, [:hour, :minute, :second, :microsecond])

    time_only =
      datetime
      |> Map.take([:hour, :minute, :second, :microsecond, :calendar])

    date_options = Keyword.put(options, :format, date_format)
    time_options = Keyword.put(options, :format, time_format)

    with {:ok, locale_id} <- resolve_locale_id(locale) do
      wrapper = fallback_wrapper(wrapper_level, locale_id)
      compose_partial(output, wrapper, date_only, time_only, date_options, time_options)
    end
  end

  defp compose_partial(:string, wrapper, date_only, time_only, date_options, time_options) do
    with {:ok, date_str} <- Localize.Date.to_string(date_only, date_options),
         {:ok, time_str} <- Localize.Time.to_string(time_only, time_options) do
      result =
        wrapper
        |> String.replace("{1}", date_str)
        |> String.replace("{0}", time_str)

      {:ok, result}
    end
  end

  # The wrapper indexes time as {0} and date as {1}, so the parts
  # lists are supplied in that order.
  defp compose_partial(:parts, wrapper, date_only, time_only, date_options, time_options) do
    with {:ok, date_parts} <- Localize.Date.to_parts(date_only, date_options),
         {:ok, time_parts} <- Localize.Time.to_parts(time_only, time_options) do
      tokens = Localize.Substitution.parse(wrapper)
      {:ok, Localize.Substitution.substitute_parts([time_parts, date_parts], tokens)}
    end
  end

  defp format_with_wrapper(datetime, options, locale_id, format, style, output) do
    date_format = Keyword.get(options, :date_format, format)
    time_format = Keyword.get(options, :time_format, format)

    # The wrapper style should match the date format level
    # (e.g., full date + short time → use full wrapper)
    wrapper_format =
      if Keyword.has_key?(options, :date_format),
        do: date_format,
        else: format

    options_map =
      options
      |> Map.new()
      |> Map.put(:date_format, date_format)
      |> Map.put(:time_format, time_format)

    with {:ok, wrapper} <- resolve_wrapper(wrapper_format, locale_id, style) do
      invoke_formatter(output, datetime, wrapper, locale_id, options_map)
    end
  end

  # Fractional seconds (S) never participate in skeleton matching
  # per TR35: the S field is stripped before resolution and appended
  # to the seconds field of the resolved pattern afterwards.
  defp format_with_skeleton(datetime, options, locale_id, skeleton, output) do
    {skeleton, fraction_count} =
      Localize.DateTime.Format.Match.split_fractional_seconds(skeleton)

    with {:ok, available} <- Localize.DateTime.Format.available_formats(locale_id) do
      case Map.get(available, skeleton) do
        nil ->
          # Try best-match algorithm for skeletons not found exactly
          format_with_best_match(
            datetime,
            options,
            locale_id,
            skeleton,
            available,
            fraction_count,
            output
          )

        %{} = variant_map ->
          variant_map
          |> Localize.DateTime.Format.resolve_variant(options)
          |> Localize.DateTime.Format.Match.append_fractional_seconds(fraction_count, locale_id)
          |> format_resolved_pattern(datetime, options, locale_id, skeleton, output)

        pattern when is_binary(pattern) ->
          pattern
          |> Localize.DateTime.Format.Match.append_fractional_seconds(fraction_count, locale_id)
          |> then(&invoke_formatter(output, datetime, &1, locale_id, Map.new(options)))
      end
    end
  end

  defp format_with_best_match(
         datetime,
         options,
         locale_id,
         skeleton,
         available,
         fraction_count,
         output
       ) do
    case Localize.DateTime.Format.Match.best_match(skeleton, locale_id) do
      {:ok, matched_skeleton} when is_atom(matched_skeleton) ->
        format_matched_skeleton(
          Map.get(available, matched_skeleton),
          datetime,
          options,
          locale_id,
          skeleton,
          fraction_count,
          output
        )

      {:ok, {date_skeleton, time_skeleton}} ->
        date_pattern =
          Localize.DateTime.Format.resolve_variant(
            Map.get(available, date_skeleton, ""),
            options
          )

        time_pattern =
          Map.get(available, time_skeleton, "")
          |> Localize.DateTime.Format.resolve_variant(options)
          |> Localize.DateTime.Format.Match.append_fractional_seconds(fraction_count, locale_id)

        format_combined_patterns(
          date_pattern,
          time_pattern,
          datetime,
          options,
          locale_id,
          skeleton,
          output
        )

      _ ->
        {:error,
         Localize.DateTimeUnresolvedFormatError.exception(
           format: skeleton,
           locale: locale_id
         )}
    end
  end

  defp format_matched_skeleton(
         nil,
         _datetime,
         _options,
         locale_id,
         skeleton,
         _fraction_count,
         _output
       ) do
    {:error,
     Localize.DateTimeUnresolvedFormatError.exception(
       format: skeleton,
       locale: locale_id
     )}
  end

  defp format_matched_skeleton(
         matched_pattern,
         datetime,
         options,
         locale_id,
         skeleton,
         fraction_count,
         output
       ) do
    matched_pattern
    |> Localize.DateTime.Format.resolve_variant(options)
    |> Localize.DateTime.Format.Match.append_fractional_seconds(fraction_count, locale_id)
    |> format_resolved_pattern(datetime, options, locale_id, skeleton, output)
  end

  defp format_combined_patterns(
         date_pattern,
         time_pattern,
         datetime,
         options,
         locale_id,
         _skeleton,
         output
       )
       when is_binary(date_pattern) and is_binary(time_pattern) do
    options_map =
      options
      |> Map.new()
      |> Map.put(:date_format, :medium)
      |> Map.put(:time_format, :medium)

    with {:ok, wrapper} <- resolve_wrapper(:medium, locale_id, :default) do
      combined = String.replace(wrapper, "{0}", time_pattern)
      combined = String.replace(combined, "{1}", date_pattern)
      invoke_formatter(output, datetime, combined, locale_id, options_map)
    end
  end

  defp format_combined_patterns(
         _date_pattern,
         _time_pattern,
         _datetime,
         _options,
         locale_id,
         skeleton,
         _output
       ) do
    {:error,
     Localize.DateTimeUnresolvedFormatError.exception(
       format: skeleton,
       locale: locale_id
     )}
  end

  defp format_resolved_pattern(nil, _datetime, _options, locale_id, skeleton, _output) do
    {:error,
     Localize.DateTimeUnresolvedFormatError.exception(
       format: skeleton,
       locale: locale_id
     )}
  end

  defp format_resolved_pattern(pattern, datetime, options, locale_id, _skeleton, output)
       when is_binary(pattern) do
    invoke_formatter(output, datetime, pattern, locale_id, Map.new(options))
  end

  defp resolve_wrapper(format, locale_id, style) do
    standard_format = if is_atom(format), do: format, else: :medium

    case style do
      :at ->
        # Use at-style format (e.g., "{1} 'at' {0}")
        case Localize.DateTime.Format.date_time_at_formats(locale_id) do
          {:ok, at_formats} ->
            pattern =
              get_in(at_formats, [:standard, standard_format]) ||
                fallback_wrapper(standard_format, locale_id)

            {:ok, pattern}

          _ ->
            {:ok, fallback_wrapper(standard_format, locale_id)}
        end

      _ ->
        # Use standard wrapper format (e.g., "{1}, {0}")
        {:ok, fallback_wrapper(standard_format, locale_id)}
    end
  end

  defp fallback_wrapper(standard_format, locale_id) do
    case Localize.DateTime.Format.date_time_formats(locale_id) do
      {:ok, dt_formats} -> Map.get(dt_formats, standard_format, "{1}, {0}")
      _ -> "{1}, {0}"
    end
  end

  defp resolve_locale_id(locale), do: Localize.Locale.cldr_locale_id_from(locale)
end
