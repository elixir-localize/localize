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
  import Localize.Utils.Helpers, only: [is_keyword_list: 1]

  @default_format :medium
  @standard_formats [:short, :medium, :long, :full]

  # The fields that decide how a map is routed, and the keys the time half
  # of a partial value keeps.
  @value_date_fields [:year, :month, :day]
  @value_time_fields [:hour, :minute, :second]
  @partial_time_keys [
    :hour,
    :minute,
    :second,
    :microsecond,
    :time_zone,
    :zone_abbr,
    :utc_offset,
    :std_offset
  ]

  @doc """
  Formats a datetime according to a CLDR format pattern.

  ### Arguments

  * `datetime` is a `t:DateTime.t/0`, `t:NaiveDateTime.t/0`,
    or any map with date or time keys. A map holding only some of
    the date and time fields formats its date half and its time
    half separately and joins them; one holding only date keys or
    only time keys is formatted as `Localize.Date` or
    `Localize.Time` would format it.

  * `options` is a keyword list of options.

  ### Options

  * `:format` is a standard format name (`:short`, `:medium`,
    `:long`, `:full`), a format skeleton atom or a format pattern
    string. The default is `:medium`. A standard format sets the
    width of the date and the time together; `:date_format` and
    `:time_format` override each axis separately.

  * `:date_format` and `:time_format` are standard format names
    or skeleton atoms that set the date half and the time half
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

      iex> Localize.DateTime.to_string(%{year: 2026, month: 6, day: 15, hour: 14}, locale: :en, prefer: :ascii)
      {:ok, "Jun 15, 2026, 2 PM"}

  """
  @spec to_string(map(), Keyword.t()) :: {:ok, String.t()} | {:error, Exception.t()}
  def to_string(datetime, options \\ []) do
    do_format(datetime, options, :string)
  end

  # Every map takes one of four routes, chosen by the fields it holds. The
  # `output` mode (:string | :parts) selects the formatter entry point at
  # each terminal, so `to_string/2` and `to_parts/2` share every
  # resolution path.
  defp do_format(datetime, options, output) when is_map(datetime) and is_keyword_list(options) do
    case value_shape(datetime) do
      :complete -> format_datetime(datetime, options, output, :complete)
      :partial -> format_datetime(datetime, options, output, :partial)
      :date -> delegate_format(Localize.Date, datetime, options, output)
      :time -> delegate_format(Localize.Time, datetime, options, output)
      :none -> {:error, Localize.DateTimeInvalidInputError.exception(type: :datetime)}
    end
  end

  defp do_format(_datetime, options, _output) when not is_keyword_list(options),
    do: {:error, Localize.Utils.Helpers.invalid_options(options)}

  defp do_format(_invalid, _options, _output) do
    {:error, Localize.DateTimeInvalidInputError.exception(type: :datetime)}
  end

  # A complete value holds every date and time field. A partial one holds
  # some of each, and neither half's fields may be dropped. The rest hold
  # fields of only one kind.
  defp value_shape(%{year: _, month: _, day: _, hour: _, minute: _, second: _}), do: :complete

  defp value_shape(value) do
    has_date_field = Enum.any?(@value_date_fields, &Map.has_key?(value, &1))
    has_time_field = Enum.any?(@value_time_fields, &Map.has_key?(value, &1))

    cond do
      has_date_field and has_time_field -> :partial
      has_date_field -> :date
      has_time_field -> :time
      true -> :none
    end
  end

  defp delegate_format(module, value, options, :string), do: module.to_string(value, options)
  defp delegate_format(module, value, options, :parts), do: module.to_parts(value, options)

  defp format_datetime(datetime, options, output, shape) do
    locale = Keyword.get(options, :locale, Localize.get_locale())
    format = Keyword.get(options, :format, @default_format)
    style = Keyword.get(options, :style, :default)
    options = Keyword.put_new(options, :locale, locale)

    with {:ok, locale_id} <- resolve_locale_id(locale) do
      cond do
        # Explicit pattern string — format directly
        is_binary(format) ->
          invoke_formatter(output, datetime, format, locale_id, Map.new(options))

        # Standard or separate date and time formats on a partial value —
        # each half derives its own skeleton, then the wrapper joins them.
        shape == :partial and wrapped_format?(format, options) ->
          format_partial_datetime(datetime, options, locale_id, style, output)

        # Standard format with separate date/time formats — use wrapper
        wrapped_format?(format, options) ->
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

  defp wrapped_format?(format, options) do
    format in @standard_formats or
      (Keyword.has_key?(options, :date_format) and Keyword.has_key?(options, :time_format))
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

  # A partial value's date and time halves format independently through
  # `Localize.Date` and `Localize.Time`, which derive a skeleton from the
  # fields present, and join through the wrapper a complete value would
  # use, honouring `:style` the same way.
  defp format_partial_datetime(datetime, options, locale_id, style, output) do
    format = Keyword.get(options, :format, @default_format)
    date_format = Keyword.get(options, :date_format, format)
    time_format = Keyword.get(options, :time_format, format)

    wrapper_format =
      if Keyword.has_key?(options, :date_format), do: date_format, else: format

    date_only = Map.drop(datetime, @partial_time_keys)
    time_only = Map.take(datetime, [:calendar | @partial_time_keys])

    date_options = Keyword.put(options, :format, date_format)
    time_options = Keyword.put(options, :format, time_format)

    with {:ok, wrapper} <- resolve_wrapper(wrapper_format, locale_id, style) do
      compose_partial(output, wrapper, date_only, time_only, date_options, time_options)
    end
  end

  # The wrapper is a pattern: `{1}` takes the date, `{0}` the time, and its
  # literal text may be quoted (`{1} 'at' {0}`), so it is tokenized rather
  # than substituted as plain text.
  defp compose_partial(output, wrapper, date_only, time_only, date_options, time_options) do
    with {:ok, tokens} <- tokenize_wrapper(wrapper),
         {:ok, date_value} <- format_half(output, Localize.Date, date_only, date_options),
         {:ok, time_value} <- format_half(output, Localize.Time, time_only, time_options) do
      pieces =
        Enum.map(tokens, fn
          {:date, _line, _count} -> date_value
          {:time, _line, _count} -> time_value
          {:literal, _line, text} -> literal_piece(output, text)
        end)

      {:ok, join_pieces(output, pieces)}
    end
  end

  defp tokenize_wrapper(wrapper) do
    case Localize.DateTime.Format.Compiler.tokenize(wrapper) do
      {:ok, tokens, _end_line} ->
        {:ok, tokens}

      _error ->
        {:error, Localize.DateTimeFormatError.exception(format: wrapper, reason: :tokenize_error)}
    end
  end

  defp format_half(:string, module, value, options), do: module.to_string(value, options)
  defp format_half(:parts, module, value, options), do: module.to_parts(value, options)

  defp literal_piece(:string, text), do: text
  defp literal_piece(:parts, text), do: [%{type: :literal, value: text}]

  defp join_pieces(:string, pieces), do: IO.iodata_to_binary(pieces)
  defp join_pieces(:parts, pieces), do: Enum.concat(pieces)

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
  # to the seconds field of the resolved pattern afterwards. A `-u-hc-`
  # override first replaces the skeleton's hour symbols, as it does for
  # `Localize.Time`.
  defp format_with_skeleton(datetime, options, locale_id, skeleton, output) do
    {skeleton, fraction_count} =
      skeleton
      |> Localize.Time.hour_cycle_skeleton(Keyword.get(options, :locale, locale_id))
      |> Localize.DateTime.Format.Match.split_fractional_seconds()

    with {:ok, available} <- Localize.DateTime.Format.available_formats(locale_id) do
      # A skeleton naming only zone fields is its own pattern: there is one
      # field, so nothing to order, and `availableFormats` carries no
      # zone-only entry for the matcher to find.
      if Localize.DateTime.Format.Match.zone_only_skeleton?(skeleton) do
        skeleton
        |> Kernel.to_string()
        |> format_resolved_pattern(datetime, options, locale_id, skeleton, output)
      else
        format_from_available(
          datetime,
          options,
          locale_id,
          skeleton,
          available,
          fraction_count,
          output
        )
      end
    end
  end

  defp format_from_available(
         datetime,
         options,
         locale_id,
         skeleton,
         available,
         fraction_count,
         output
       ) do
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
        |> Localize.Time.apply_hour_cycle(Keyword.get(options, :locale, locale_id), skeleton)
        |> format_resolved_pattern(datetime, options, locale_id, skeleton, output)

      pattern when is_binary(pattern) ->
        pattern
        |> Localize.DateTime.Format.Match.append_fractional_seconds(fraction_count, locale_id)
        |> Localize.Time.apply_hour_cycle(Keyword.get(options, :locale, locale_id), skeleton)
        |> then(&invoke_formatter(output, datetime, &1, locale_id, Map.new(options)))
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
          available
          |> Map.get(date_skeleton, "")
          |> Localize.DateTime.Format.resolve_variant(options)
          |> adjust_to_requested_widths(skeleton, date_skeleton)

        time_pattern =
          available
          |> Map.get(time_skeleton, "")
          |> Localize.DateTime.Format.resolve_variant(options)
          |> adjust_to_requested_widths(skeleton, time_skeleton)
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

      _no_match ->
        format_via_append_items(
          datetime,
          options,
          locale_id,
          skeleton,
          fraction_count,
          output
        )
    end
  end

  # TR35's append-item path, taken when no available format carries every
  # requested field. A skeleton spanning both halves is split first so each
  # half resolves on its own and the two join through the locale's
  # date-time wrapper — otherwise `:yMMMdQhm` would append the hour and
  # minute as parenthesised items instead of formatting them as a time.
  defp format_via_append_items(datetime, options, locale_id, skeleton, fraction_count, output) do
    alias Localize.DateTime.Format.AppendItems

    case Localize.DateTime.Format.Match.separate_date_and_time(skeleton) do
      {date_skeleton, time_skeleton} ->
        with {:ok, date_pattern} <-
               AppendItems.resolve_pattern(date_skeleton, locale_id, :gregorian, options),
             {:ok, time_pattern} <-
               AppendItems.resolve_pattern(time_skeleton, locale_id, :gregorian, options) do
          format_combined_patterns(
            date_pattern,
            Localize.DateTime.Format.Match.append_fractional_seconds(
              time_pattern,
              fraction_count,
              locale_id
            ),
            datetime,
            options,
            locale_id,
            skeleton,
            output
          )
        else
          _unresolvable -> unresolved_skeleton(skeleton, locale_id)
        end

      nil ->
        case AppendItems.augment(skeleton, locale_id, :gregorian, options) do
          {:ok, pattern} ->
            pattern
            |> Localize.DateTime.Format.Match.append_fractional_seconds(
              fraction_count,
              locale_id
            )
            |> Localize.Time.apply_hour_cycle(Keyword.get(options, :locale, locale_id), skeleton)
            |> then(&invoke_formatter(output, datetime, &1, locale_id, Map.new(options)))

          _unresolvable ->
            unresolved_skeleton(skeleton, locale_id)
        end
    end
  end

  defp unresolved_skeleton(skeleton, locale_id) do
    {:error,
     Localize.DateTimeUnresolvedFormatError.exception(
       format: skeleton,
       locale: locale_id
     )}
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
    |> adjust_to_requested_widths(skeleton)
    |> Localize.DateTime.Format.Match.append_fractional_seconds(fraction_count, locale_id)
    |> Localize.Time.apply_hour_cycle(Keyword.get(options, :locale, locale_id), skeleton)
    |> format_resolved_pattern(datetime, options, locale_id, skeleton, output)
  end

  # TR35 matches a skeleton to the closest available format and then adjusts
  # that format's field widths to the ones requested. `en` ships an `MMM`
  # format and no `MMMM`, so without this step asking for `:MMMM` matched
  # `MMM` and rendered "Jul" where the literal pattern renders "July".
  defp adjust_to_requested_widths(pattern, skeleton, matched_id \\ nil)

  defp adjust_to_requested_widths(pattern, skeleton, matched_id) when is_binary(pattern) do
    {:ok, tokens} = Localize.DateTime.Format.Match.tokenize_skeleton(skeleton)

    {:ok, adjusted} =
      Localize.DateTime.Format.Match.adjust_field_lengths(pattern, tokens, matched_id)

    adjusted
  end

  defp adjust_to_requested_widths(pattern, _skeleton, _matched_id), do: pattern

  defp format_combined_patterns(
         date_pattern,
         time_pattern,
         datetime,
         options,
         locale_id,
         skeleton,
         output
       )
       when is_binary(date_pattern) and is_binary(time_pattern) do
    options_map =
      options
      |> Map.new()
      |> Map.put(:date_format, :medium)
      |> Map.put(:time_format, :medium)

    with {:ok, wrapper} <- resolve_wrapper(skeleton, locale_id, :default) do
      time_pattern =
        Localize.Time.apply_hour_cycle(
          time_pattern,
          Keyword.get(options, :locale, locale_id),
          skeleton
        )

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

  @doc false
  # The pattern joining a date and a time for `date_format` in the locale, as
  # `to_string/2` chooses it for `style`. `Localize.Interval` joins a date to
  # a time range through it (TR35 §Interval Formats step 3).
  def date_time_wrapper(date_format, locale_id, style) do
    resolve_wrapper(date_format, locale_id, style)
  end

  defp resolve_wrapper(format, locale_id, style) do
    standard_format = wrapper_length(format)

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

  # TR35 Missing Skeleton Fields, step 3: the date-time glue's length
  # follows the requested date fields — full for a wide month with a
  # weekday, long for a wide month, medium for an abbreviated month and
  # short otherwise. A standard format is its own length.
  defp wrapper_length(format) when format in @standard_formats, do: format

  defp wrapper_length(format) when is_atom(format) or is_binary(format) do
    case Localize.DateTime.Format.Compiler.tokenize(Kernel.to_string(format)) do
      {:ok, tokens, _end_line} -> length_for_date_fields(tokens)
      _error -> :medium
    end
  end

  defp wrapper_length(_format), do: :medium

  defp length_for_date_fields(tokens) do
    month_widths =
      for {field, _line, count} <- tokens, field in [:month, :standalone_month], do: count

    weekday? =
      Enum.any?(tokens, fn {field, _line, _count} ->
        field in [:day_name, :day_of_week, :standalone_day_of_week]
      end)

    cond do
      4 in month_widths and weekday? -> :full
      4 in month_widths -> :long
      3 in month_widths -> :medium
      true -> :short
    end
  end

  defp resolve_locale_id(locale), do: Localize.Locale.cldr_locale_id_from(locale)

  @doc """
  Parses a localized date and time string.

  Parsing lives in the companion [calendrical](https://hex.pm/packages/calendrical)
  package, which carries the calendar systems Localize formats for.
  `calendrical` depends on Localize, so Localize resolves it at runtime rather
  than depending on it in return — add `{:calendrical, "~> 1.0"}` to your
  dependencies to use this function.

  ### Arguments

  * `string` is a string in any shape the locale accepts, including the
    locale's CLDR short, medium, long and full patterns and ISO 8601.

  * `options` is a keyword list of options.

  ### Options

  * `:locale` is a locale identifier. The default is the locale returned by
    `Localize.get_locale/0`.

  * Remaining options are passed to `Calendrical.DateTime.parse/2`, which
    documents them.

  ### Returns

  * `{:ok, value}` where `value` is a `t:NaiveDateTime.t()` , or

  * `{:error, exception}` if the string does not parse, or a
    `t:Localize.DependencyRequiredError.t/0` if `calendrical` is not among
    the application's dependencies.

  ### Examples

  Shown rather than run as doctests: `calendrical` is not a dependency of
  Localize itself, so the call does not resolve in this package's own tests.

      Localize.DateTime.parse("22.03.2026, 14:30", locale: :de)
      #=> {:ok, ~N[2026-03-22 14:30:00]}

      Localize.DateTime.parse("March 22, 2026, 2:30 PM", locale: :en)
      #=> {:ok, ~N[2026-03-22 14:30:00]}

  """
  @spec parse(String.t(), Keyword.t()) ::
          {:ok, NaiveDateTime.t() | DateTime.t()} | {:error, Exception.t()}
  def parse(string, options \\ []) when is_binary(string) do
    Localize.OptionalDependency.call(
      "Calendrical.DateTime",
      :parse,
      [string, options],
      package: "calendrical",
      operation: "Localize.DateTime.parse/2"
    )
  end
end
