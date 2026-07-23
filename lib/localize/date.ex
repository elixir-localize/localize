defmodule Localize.Date do
  @moduledoc """
  Provides localized formatting of `Date` structs and date-like maps.

  Supports both full dates (`%{year: _, month: _, day: _}`) and partial
  dates (any map with one or more of `:year`, `:month`, `:day`). For
  partial dates, the format is derived from the available fields.

  Formats are defined in CLDR and described in
  [TR35](http://unicode.org/reports/tr35/tr35-dates.html).

  """

  import Kernel, except: [to_string: 1]

  @standard_formats [:short, :medium, :long, :full]
  @default_format :medium
  # Ordered by CLDR canonical skeleton order: year, month, day
  @date_fields_ordered [{:year, "y"}, {:month, "M"}, {:day, "d"}]
  # @date_field_names Enum.map(@date_fields_ordered, &elem(&1, 0))

  defguardp is_full_date(date)
            when is_map_key(date, :year) and is_map_key(date, :month) and is_map_key(date, :day)

  defguardp has_date_field(date)
            when is_map_key(date, :year) or is_map_key(date, :month) or is_map_key(date, :day)

  @doc """
  Formats a date according to a CLDR format pattern.

  ### Arguments

  * `date` is a `t:Date.t/0` or any map with one or more of
    `:year`, `:month`, `:day` keys.

  * `options` is a keyword list of options.

  ### Options

  * `:format` is a standard format name (`:short`, `:medium`,
    `:long`, `:full`), a format skeleton atom, or a format
    pattern string. The default is `:medium` for full dates.
    For partial dates the format is derived from the available
    fields.

  * `:locale` is a locale identifier. The default is `:en`.

  * `:number_system` is a CLDR numbering system name (for example, `:thai`). All numeric fields render in that system; a `-u-nu-` locale extension may be used instead. The default is the locale's number system.

  * `:prefer` selects between CLDR `alt` variants. Accepts an
    atom or a list of atoms in priority order. Recognised values:
    `:standard` / `:variant` (locales like en-CA publish both an
    ISO pattern `"y-MM-dd"` and a locale-variant `"d/M/yy"`),
    and `:unicode` / `:ascii` (NBSP and curly quotes vs ASCII).
    Examples: `prefer: :variant`, `prefer: [:variant, :ascii]`.
    The default is `[:standard, :unicode]`.

  ### Returns

  * `{:ok, formatted_string}` on success.

  * `{:error, exception}` if the date cannot be formatted.

  ### Examples

      iex> Localize.Date.to_string(~D[2017-07-10], locale: :en)
      {:ok, "Jul 10, 2017"}

      iex> Localize.Date.to_string(~D[2017-07-10], format: :full, locale: :en)
      {:ok, "Monday, July 10, 2017"}

      iex> Localize.Date.to_string(~D[2017-07-10], format: :short, locale: :en)
      {:ok, "7/10/17"}

      iex> Localize.Date.to_string(~D[2017-07-10], format: :short, locale: :fr)
      {:ok, "10/07/2017"}

      iex> Localize.Date.to_string(%{year: 2024, month: 6}, format: :yMMM, locale: :fr)
      {:ok, "juin 2024"}

  """
  @spec to_string(map(), Keyword.t()) :: {:ok, String.t()} | {:error, Exception.t()}
  def to_string(date, options \\ []) do
    with {:ok, pattern, locale_id, formatter_options} <- formatting_plan(date, options) do
      Localize.DateTime.Formatter.format(date, pattern, locale_id, formatter_options)
    end
  end

  # Resolves the format pattern, locale, and formatter options for a
  # date — the shared front half of `to_string/2` and `to_parts/2`.
  defp formatting_plan(%{year: _, month: _, day: _} = date, options) do
    locale = Keyword.get(options, :locale, Localize.get_locale())
    format = Keyword.get(options, :format, @default_format)

    with {:ok, locale_id} <- resolve_locale_id(locale),
         {:ok, pattern} <- find_format(date, format, locale_id, options) do
      overrides = number_system_overrides_for(date, format, locale_id)

      formatter_options =
        options
        |> Map.new()
        |> Map.put_new(:locale, locale)
        |> merge_number_system_overrides(overrides)

      {:ok, pattern, locale_id, formatter_options}
    end
  end

  # Partial date
  defp formatting_plan(date, options) when has_date_field(date) do
    locale = Keyword.get(options, :locale, Localize.get_locale())
    format = Keyword.get(options, :format)

    with {:ok, locale_id} <- resolve_locale_id(locale) do
      resolved_format = resolve_partial_format(format, date)
      options = Keyword.put_new(options, :locale, locale)
      partial_formatting_plan(resolved_format, date, format, locale_id, options)
    end
  end

  defp formatting_plan(_date, _options) do
    {:error, Localize.DateTimeInvalidInputError.exception(type: :date)}
  end

  # Resolve the format for a partial date. Standard formats are
  # not accepted for partial dates; when no format is given the
  # format skeleton is derived from the available fields.
  defp resolve_partial_format(format, _date) when is_binary(format) do
    format
  end

  defp resolve_partial_format(format, _date)
       when is_atom(format) and format != nil and format not in @standard_formats do
    format
  end

  defp resolve_partial_format(format, _date) when format in @standard_formats do
    nil
  end

  defp resolve_partial_format(_format, date) do
    derive_format_id(date)
  end

  defp partial_formatting_plan(nil, _date, format, locale_id, _options) do
    {:error,
     Localize.DateTimeUnresolvedFormatError.exception(
       format: format,
       locale: locale_id
     )}
  end

  defp partial_formatting_plan(resolved_format, date, _format, locale_id, options) do
    with {:ok, pattern} <- find_format(date, resolved_format, locale_id, options) do
      overrides = number_system_overrides_for(date, resolved_format, locale_id)

      formatter_options =
        options |> Map.new() |> merge_number_system_overrides(overrides)

      {:ok, pattern, locale_id, formatter_options}
    end
  end

  @doc """
  Same as `to_string/2` but raises on error.

  ### Arguments

  * `date` is a `t:Date.t/0` or any map with one or more of
    `:year`, `:month`, `:day` keys.

  * `options` is a keyword list of options.

  ### Options

  See `to_string/2` for the supported options.

  ### Returns

  * A formatted string.

  * Raises an exception if the date cannot be formatted.

  ### Examples

      iex> Localize.Date.to_string!(~D[2017-07-10], locale: :en)
      "Jul 10, 2017"

      iex> Localize.Date.to_string!(%{year: 2024, month: 6}, format: :yMMM, locale: :fr)
      "juin 2024"

  """
  @spec to_string!(map(), Keyword.t()) :: String.t()
  def to_string!(date, options \\ []) do
    case to_string(date, options) do
      {:ok, string} -> string
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Formats a date into typed parts, mirroring ECMA-402's `formatToParts`.

  The parts concatenate to exactly the string `to_string/2` produces with the same options. Each pattern field is tagged with its type: `:year`, `:month`, `:day`, `:weekday`, `:era`, and `:literal` for separators.

  ### Arguments

  * `date` is a `t:Date.t/0` or any map with date keys.

  * `options` is a keyword list of options.

  ### Options

  See `to_string/2` for the supported options.

  ### Returns

  * `{:ok, parts}` where `parts` is a list of `%{type: atom(), value: String.t()}` maps.

  * `{:error, exception}` if the date cannot be formatted.

  ### Examples

      iex> Localize.Date.to_parts(~D[2017-07-10], locale: :en)
      {:ok,
       [
         %{type: :month, value: "Jul"},
         %{type: :literal, value: " "},
         %{type: :day, value: "10"},
         %{type: :literal, value: ", "},
         %{type: :year, value: "2017"}
       ]}

  """
  @spec to_parts(map(), Keyword.t()) ::
          {:ok, [%{type: atom(), value: String.t()}]} | {:error, Exception.t()}
  def to_parts(date, options \\ []) do
    with {:ok, pattern, locale_id, formatter_options} <- formatting_plan(date, options) do
      Localize.DateTime.Formatter.format_to_parts(date, pattern, locale_id, formatter_options)
    end
  end

  @doc """
  Same as `to_parts/2` but raises on error.

  ### Arguments

  * `date` is a `t:Date.t/0` or any map with date keys.

  * `options` is a keyword list of options. See `to_parts/2`.

  ### Returns

  * A list of `%{type: atom(), value: String.t()}` maps.

  ### Raises

  * Raises an exception if the date cannot be formatted.

  ### Examples

      iex> Localize.Date.to_parts!(~D[2017-07-10], locale: :en) |> length()
      5

  """
  @spec to_parts!(map(), Keyword.t()) :: [%{type: atom(), value: String.t()}]
  def to_parts!(date, options \\ []) do
    case to_parts(date, options) do
      {:ok, parts} -> parts
      {:error, exception} -> raise exception
    end
  end

  # ── Format resolution ──────────────────────────────────────

  defp find_format(_date, format, _locale_id, _options) when is_binary(format) do
    {:ok, format}
  end

  defp find_format(date, format, locale_id, options) when is_atom(format) do
    cldr_calendar = cldr_calendar_for(date)

    # For standard formats on full dates, resolve via the standard format map
    if format in @standard_formats and is_full_date(date) do
      Localize.DateTime.Format.resolve_format(:date, format, locale_id, cldr_calendar, options)
    else
      # Skeleton format — look up in available_formats
      resolve_skeleton(
        skeleton: format,
        locale_id: locale_id,
        calendar: cldr_calendar,
        options: options
      )
    end
  end

  defp find_format(_date, format, _locale_id, _options) do
    {:error, Localize.DateTimeFormatError.exception(format: format, reason: :invalid_format)}
  end

  # Look up the per-field number-system overrides for the
  # date's calendar. Returns `%{}` for ordinary patterns,
  # `%{"all" => :hebr}` for Hebrew dates, `%{"y" => :jpanyear}`
  # for Japanese imperial, etc. The formatter consults this
  # map when emitting numeric fields and applies the right
  # digit set or RBNF rule.
  defp number_system_overrides_for(date, format, locale_id) when is_atom(format) do
    Localize.DateTime.Format.number_system_overrides(
      :date,
      format,
      locale_id,
      cldr_calendar_for(date)
    )
  end

  defp number_system_overrides_for(_date, _format, _locale_id), do: %{}

  # Combine the calendar-derived overrides with any overrides the
  # caller supplied in options. User-supplied entries win over the
  # derived ones; derived entries fill any remaining fields.
  defp merge_number_system_overrides(options_map, overrides) do
    Map.update(options_map, :number_system_overrides, overrides, fn user_overrides ->
      if is_map(user_overrides) do
        Map.merge(overrides, user_overrides)
      else
        user_overrides
      end
    end)
  end

  # Resolve the CLDR calendar key from a date's `:calendar`
  # module. `Calendar.ISO` is Gregorian. Other calendar modules
  # (e.g. Calendrical's `Calendrical.Japanese`,
  # `Calendrical.Buddhist`) expose `cldr_calendar_type/0` —
  # probe it via `function_exported?/3` so Localize itself
  # doesn't need a hard dep on the calendar library.
  defp cldr_calendar_for(%{calendar: Calendar.ISO}), do: :gregorian

  defp cldr_calendar_for(%{calendar: module}) when is_atom(module) do
    Code.ensure_loaded?(module)

    if function_exported?(module, :cldr_calendar_type, 0) do
      module.cldr_calendar_type()
    else
      :gregorian
    end
  end

  defp cldr_calendar_for(_), do: :gregorian

  defp resolve_skeleton(opts) when is_list(opts) do
    skeleton = Keyword.fetch!(opts, :skeleton)
    locale_id = Keyword.fetch!(opts, :locale_id)
    calendar = Keyword.get(opts, :calendar, :gregorian)
    options = Keyword.get(opts, :options, [])
    # Internal: skeletons already attempted in this resolution
    # chain. Prevents an infinite loop where `best_match`
    # returns the same skeleton it was given because the
    # candidate set already contains it (and we then re-look-up
    # in the calendar's available_formats where it's missing).
    seen = Keyword.get(opts, :seen, MapSet.new())

    with {:ok, available} <-
           Localize.DateTime.Format.available_formats(locale_id, calendar) do
      case Map.get(available, skeleton) do
        nil ->
          resolve_skeleton_via_best_match(skeleton, locale_id, calendar, options, seen)

        %{} = variant_map ->
          variant_map
          |> Localize.DateTime.Format.resolve_variant(options)
          |> variant_pattern_result(skeleton, locale_id)

        pattern when is_binary(pattern) ->
          {:ok, pattern}
      end
    end
  end

  defp variant_pattern_result(nil, skeleton, locale_id) do
    {:error,
     Localize.DateTimeUnresolvedFormatError.exception(
       format: skeleton,
       locale: locale_id
     )}
  end

  defp variant_pattern_result(pattern, _skeleton, _locale_id) do
    {:ok, pattern}
  end

  # Two-step fallback when the exact skeleton isn't in the
  # calendar's `available_formats`:
  #
  # 1. Ask `best_match` for the nearest skeleton in the
  #    **same calendar's** format set. Pass the calendar
  #    explicitly — the default of `:gregorian` is what
  #    caused the infinite loop for non-Gregorian dates
  #    (best_match found the skeleton in gregorian, returned
  #    it, and resolve_skeleton re-looked-up in the original
  #    non-Gregorian calendar where it's still missing).
  #
  # 2. If best_match for the calendar finds nothing, fall back
  #    to gregorian's pattern set. Skeletons are
  #    calendar-agnostic by design, so a user requesting
  #    `:yMMMM` against a Japanese date should still get
  #    "MMMM y" rendering rather than an error.
  #
  # In both cases the recursion is guarded by a `seen` set
  # so a degenerate match cycle (`a → b → a`) terminates.
  defp resolve_skeleton_via_best_match(skeleton, locale_id, calendar, options, seen) do
    if MapSet.member?(seen, skeleton) do
      {:error,
       Localize.DateTimeUnresolvedFormatError.exception(
         format: skeleton,
         locale: locale_id
       )}
    else
      seen = MapSet.put(seen, skeleton)

      case Localize.DateTime.Format.Match.best_match(skeleton, locale_id, calendar) do
        {:ok, matched_id} when is_atom(matched_id) and matched_id != skeleton ->
          resolve_skeleton(
            skeleton: matched_id,
            locale_id: locale_id,
            calendar: calendar,
            options: options,
            seen: seen
          )

        {:ok, {_date_id, _time_id}} ->
          # Combined date+time skeleton — not applicable for
          # date-only formatting.
          {:error,
           Localize.DateTimeUnresolvedFormatError.exception(
             format: skeleton,
             locale: locale_id
           )}

        _ when calendar != :gregorian ->
          # Calendar-specific match exhausted — fall back to
          # gregorian patterns. The displayed values will
          # still be calendar-correct because the formatter's
          # `y` / `G` tokens read from `date.calendar`; only
          # the pattern selection switches to gregorian.
          resolve_skeleton(
            skeleton: skeleton,
            locale_id: locale_id,
            calendar: :gregorian,
            options: options,
            seen: seen
          )

        _ ->
          {:error,
           Localize.DateTimeUnresolvedFormatError.exception(
             format: skeleton,
             locale: locale_id
           )}
      end
    end
  end

  @doc false
  def derive_format_id(date) do
    @date_fields_ordered
    |> Enum.filter(fn {field, _symbol} -> Map.has_key?(date, field) end)
    |> Enum.map_join(fn {_field, symbol} -> symbol end)
    |> String.to_atom()
  end

  # ── Locale resolution ──────────────────────────────────────

  defp resolve_locale_id(locale), do: Localize.Locale.cldr_locale_id_from(locale)
end
