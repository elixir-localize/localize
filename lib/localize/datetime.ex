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
    is `:medium`.

  * `:locale` is a locale identifier. The default is `:en`.

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
  def to_string(datetime, options \\ [])

  # Full datetime: year, month, day, hour, minute, second all present.
  def to_string(
        %{year: _, month: _, day: _, hour: _, minute: _, second: _} = datetime,
        options
      ) do
    locale = Keyword.get(options, :locale, Localize.get_locale())
    format = Keyword.get(options, :format, @default_format)
    style = Keyword.get(options, :style, :default)
    options = Keyword.put_new(options, :locale, locale)

    with {:ok, locale_id} <- resolve_locale_id(locale) do
      cond do
        # Explicit pattern string — format directly
        is_binary(format) ->
          Localize.DateTime.Formatter.format(datetime, format, locale_id, Map.new(options))

        # Standard format with separate date/time formats — use wrapper
        format in @standard_formats or
            (Keyword.has_key?(options, :date_format) and
               Keyword.has_key?(options, :time_format)) ->
          format_with_wrapper(datetime, options, locale_id, format, style)

        # Skeleton atom — resolve to a pattern from available_formats
        is_atom(format) ->
          format_with_skeleton(datetime, options, locale_id, format)

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
  def to_string(%{year: _, month: _, day: _, hour: _} = datetime, options) do
    format_partial_datetime(datetime, options)
  end

  def to_string(datetime, options) when is_map(datetime) do
    # Try as date-only or time-only
    cond do
      Map.has_key?(datetime, :year) and Map.has_key?(datetime, :month) ->
        Localize.Date.to_string(datetime, options)

      Map.has_key?(datetime, :hour) ->
        Localize.Time.to_string(datetime, options)

      true ->
        {:error, Localize.DateTimeInvalidInputError.exception(type: :datetime)}
    end
  end

  def to_string(_invalid, _options) do
    {:error, Localize.DateTimeInvalidInputError.exception(type: :datetime)}
  end

  @doc """
  Same as `to_string/2` but raises on error.

  ### Options

  See `to_string/2` for the supported options.

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

  defp format_partial_datetime(datetime, options) do
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

    with {:ok, locale_id} <- resolve_locale_id(locale),
         {:ok, date_str} <- Localize.Date.to_string(date_only, date_options),
         {:ok, time_str} <- Localize.Time.to_string(time_only, time_options) do
      wrapper = fallback_wrapper(wrapper_level, locale_id)

      result =
        wrapper
        |> String.replace("{1}", date_str)
        |> String.replace("{0}", time_str)

      {:ok, result}
    end
  end

  defp format_with_wrapper(datetime, options, locale_id, format, style) do
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
      Localize.DateTime.Formatter.format(datetime, wrapper, locale_id, options_map)
    end
  end

  defp format_with_skeleton(datetime, options, locale_id, skeleton) do
    with {:ok, available} <- Localize.DateTime.Format.available_formats(locale_id) do
      case Map.get(available, skeleton) do
        nil ->
          # Try best-match algorithm for skeletons not found exactly
          format_with_best_match(datetime, options, locale_id, skeleton, available)

        %{} = variant_map ->
          format_resolved_pattern(
            Localize.DateTime.Format.resolve_variant(variant_map, options),
            datetime,
            options,
            locale_id,
            skeleton
          )

        pattern when is_binary(pattern) ->
          Localize.DateTime.Formatter.format(datetime, pattern, locale_id, Map.new(options))
      end
    end
  end

  defp format_with_best_match(datetime, options, locale_id, skeleton, available) do
    case Localize.DateTime.Format.Match.best_match(skeleton, locale_id) do
      {:ok, matched_skeleton} when is_atom(matched_skeleton) ->
        format_matched_skeleton(
          Map.get(available, matched_skeleton),
          datetime,
          options,
          locale_id,
          skeleton
        )

      {:ok, {date_skeleton, time_skeleton}} ->
        date_pattern =
          Localize.DateTime.Format.resolve_variant(
            Map.get(available, date_skeleton, ""),
            options
          )

        time_pattern =
          Localize.DateTime.Format.resolve_variant(
            Map.get(available, time_skeleton, ""),
            options
          )

        format_combined_patterns(
          date_pattern,
          time_pattern,
          datetime,
          options,
          locale_id,
          skeleton
        )

      _ ->
        {:error,
         Localize.DateTimeUnresolvedFormatError.exception(
           format: skeleton,
           locale: locale_id
         )}
    end
  end

  defp format_matched_skeleton(nil, _datetime, _options, locale_id, skeleton) do
    {:error,
     Localize.DateTimeUnresolvedFormatError.exception(
       format: skeleton,
       locale: locale_id
     )}
  end

  defp format_matched_skeleton(matched_pattern, datetime, options, locale_id, skeleton) do
    format_resolved_pattern(
      Localize.DateTime.Format.resolve_variant(matched_pattern, options),
      datetime,
      options,
      locale_id,
      skeleton
    )
  end

  defp format_combined_patterns(
         date_pattern,
         time_pattern,
         datetime,
         options,
         locale_id,
         _skeleton
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
      Localize.DateTime.Formatter.format(datetime, combined, locale_id, options_map)
    end
  end

  defp format_combined_patterns(
         _date_pattern,
         _time_pattern,
         _datetime,
         _options,
         locale_id,
         skeleton
       ) do
    {:error,
     Localize.DateTimeUnresolvedFormatError.exception(
       format: skeleton,
       locale: locale_id
     )}
  end

  defp format_resolved_pattern(nil, _datetime, _options, locale_id, skeleton) do
    {:error,
     Localize.DateTimeUnresolvedFormatError.exception(
       format: skeleton,
       locale: locale_id
     )}
  end

  defp format_resolved_pattern(pattern, datetime, options, locale_id, _skeleton)
       when is_binary(pattern) do
    Localize.DateTime.Formatter.format(datetime, pattern, locale_id, Map.new(options))
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
