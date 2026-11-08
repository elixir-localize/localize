defmodule Localize.Date do
  @moduledoc """
  Provides localized formatting of `Date` structs and date-like maps.

  Supports both full dates (`%{year: _, month: _, day: _}`) and partial
  dates (any map with one or more of `:year`, `:month`, `:day`). For a
  partial date a standard format, or no format, derives the skeleton from
  the fields present; a skeleton or pattern that asks for a field the date
  does not have returns `Localize.DateTimeInvalidInputError`.

  Formats are defined in CLDR and described in
  [TR35](http://unicode.org/reports/tr35/tr35-dates.html).

  > #### Ordinal days are a technical preview {: .warning}
  >
  > CLDR 49 adds the `ddd` field, which formats the day as a date ordinal
  > taken from the locale's `dayOfMonths` data — `:yMMMddd` renders
  > "Jul 6th, 2024" in `en` and "1er juil. 2024" in `fr`. A locale without
  > that data, and any pattern whose month is numeric, format the plain day.
  >
  > TR35 designates the `dayOfMonth` section a technical preview, and the
  > element shape was narrowed once during CLDR 49's development. Only the
  > `abbreviated` width and the ordinal-keyed forms are read, and
  > `Localize.Interval` cannot yet request an ordinal skeleton. Treat both
  > the output and the surface as subject to change.

  """

  import Kernel, except: [to_string: 1]
  import Localize.Utils.Helpers, only: [is_keyword_list: 1]

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
    `:long`, `:full`), a format skeleton atom, a
    `Localize.DateTime.SemanticSkeleton` or a format pattern
    string. The default is `:medium`. For a partial date a
    standard format derives its skeleton from the fields present,
    with the month numeric at `:short`, abbreviated at `:medium`
    and wide at `:long` and `:full`. Every calendar's date is
    written from its year, its month and its day: a calendar built
    of weeks, such as `Calendrical.ISOWeek`, has the months of its
    pattern of weeks, named as CLDR's generic calendar names them
    (`"M06 16, 2026 AD"`), and its week is written by a format that
    names one (`:yw`, `"week 25 of 2026"`).

  * `:locale` is a locale identifier. The default is `:en`.

  * `:number_system` is a CLDR numbering system name (for example, `:thai`). All numeric fields render in that system; a `-u-nu-` locale extension may be used instead. The default is the locale's number system.

  * `:numeric_date_separator` is a string replacing the locale's `numericDateSeparator` wherever it separates the fields of a numeric-month date, as TR35 allows an implementation to offer. `Localize.DateTime.numeric_separators/2` returns the locale's own. The default is the locale's separator.

  * `:numeric_time_separator` is a string replacing the locale's `numericTimeSeparator` wherever it separates time fields. The default is the locale's separator.

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

      iex> Localize.Date.to_string(%{year: 2024, month: 6}, format: :long, locale: :en)
      {:ok, "June 2024"}

  """
  @spec to_string(map(), Keyword.t()) :: {:ok, String.t()} | {:error, Exception.t()}
  def to_string(date, options \\ []) do
    with :ok <- Localize.Calendar.validate_value(date),
         {:ok, date} <- convert_to_locale_calendar(date, options),
         {:ok, pattern, locale_id, formatter_options} <- formatting_plan(date, options) do
      Localize.DateTime.Formatter.format(date, pattern, locale_id, formatter_options)
    end
  end

  # The locale's `-u-ca-` names the calendar its dates are written in, so a
  # value is converted into it before a format is resolved for it: the format
  # and the fields it writes are the calendar's. Options that are no keyword
  # list are reported by `formatting_plan/2`.
  defp convert_to_locale_calendar(date, options) when is_keyword_list(options) do
    locale = Keyword.get(options, :locale, Localize.get_locale())
    Localize.Calendar.convert_to_locale_calendar(date, locale)
  end

  defp convert_to_locale_calendar(date, _options), do: {:ok, date}

  # Resolves the format pattern, locale, and formatter options for a
  # date — the shared front half of `to_string/2` and `to_parts/2`.
  defp formatting_plan(%{year: _, month: _, day: _} = date, options)
       when is_keyword_list(options) do
    locale = Keyword.get(options, :locale, Localize.get_locale())
    format = Keyword.get(options, :format, @default_format)

    # Validate once here and thread the tag down: every layer below reads
    # locale data, and a lookup keyed by a tag skips the locale resolution
    # that a lookup keyed by an id pays for on every call.
    with {:ok, language_tag} <- Localize.validate_locale(locale),
         effective = effective_format(date, format, language_tag),
         {:ok, pattern} <- find_format(date, effective, language_tag, options) do
      overrides = number_system_overrides_for(date, effective, language_tag)

      formatter_options =
        options
        |> Map.new()
        |> Map.put_new(:locale, language_tag)
        |> merge_number_system_overrides(overrides)

      {:ok, pattern_variations(pattern, format), language_tag, formatter_options}
    end
  end

  # Partial date
  defp formatting_plan(date, options) when has_date_field(date) and is_keyword_list(options) do
    locale = Keyword.get(options, :locale, Localize.get_locale())
    format = Keyword.get(options, :format)

    with {:ok, language_tag} <- Localize.validate_locale(locale) do
      resolved_format = resolve_partial_format(format, date)
      options = Keyword.put_new(options, :locale, language_tag)
      partial_formatting_plan(resolved_format, date, format, language_tag, options)
    end
  end

  defp formatting_plan(_date, options) when not is_keyword_list(options),
    do: {:error, Localize.Utils.Helpers.invalid_options(options)}

  defp formatting_plan(_date, _options) do
    {:error, Localize.DateTimeInvalidInputError.exception(type: :date)}
  end

  # Resolve the format for a partial date. A pattern string or a skeleton
  # is used as given. A standard format, or no format at all, derives the
  # skeleton from the fields present, with the month as wide as the format
  # asks: numeric at `:short`, abbreviated at `:medium` (the default) and
  # wide at `:long` and `:full`.
  defp resolve_partial_format(format, _date) when is_binary(format) do
    format
  end

  defp resolve_partial_format(format, date) when format in @standard_formats do
    derive_format_id(date, format)
  end

  defp resolve_partial_format(nil, date) do
    derive_format_id(date, @default_format)
  end

  defp resolve_partial_format(format, _date) do
    format
  end

  defp partial_formatting_plan(resolved_format, date, format, language_tag, options) do
    with {:ok, pattern} <- find_format(date, resolved_format, language_tag, options) do
      overrides = number_system_overrides_for(date, resolved_format, language_tag)

      formatter_options =
        options |> Map.new() |> merge_number_system_overrides(overrides)

      {:ok, pattern_variations(pattern, format), language_tag, formatter_options}
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
    with :ok <- Localize.Calendar.validate_value(date),
         {:ok, date} <- convert_to_locale_calendar(date, options),
         {:ok, pattern, locale_id, formatter_options} <- formatting_plan(date, options) do
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

  @doc false
  # The pattern `format` resolves to for `date`, as `to_string/2` resolves
  # it: a standard format through the locale's date formats, a skeleton
  # through TR35 matching and a semantic skeleton through its classical
  # skeleton. `Localize.DateTime` resolves the `{1}` half of a date-time
  # wrapper here.
  def resolve_pattern(date, format, locale_id, options) do
    with {:ok, pattern} <-
           find_format(date, effective_format(date, format, locale_id), locale_id, options) do
      {:ok, pattern_variations(pattern, format)}
    end
  end

  @doc false
  # The pattern `format` resolves to for `date` and the number systems its
  # numeric fields are written in, as `to_string/2` resolves the two. The
  # date parser reads a date written with `format` by them.
  def resolve_pattern_and_numbers(date, format, locale_id, options) do
    effective = effective_format(date, format, locale_id)

    with {:ok, pattern} <- find_format(date, effective, locale_id, options) do
      numbers = number_system_overrides_for(date, effective, locale_id)
      {:ok, pattern_variations(pattern, format), numbers}
    end
  end

  # A semantic skeleton's pattern variations, its column alignment among
  # them, apply to whichever pattern it resolved to: a standard format's as
  # much as a matched skeleton's.
  defp pattern_variations(pattern, format),
    do: Localize.DateTime.SemanticSkeleton.apply_pattern_variations(pattern, format)

  # A semantic skeleton whose date fields resolve to one of the locale's
  # standard date formats is that format from here on, number systems and
  # all; any other goes on as a semantic skeleton.
  defp effective_format(date, %Localize.DateTime.SemanticSkeleton{} = semantic, locale_id) do
    case Localize.DateTime.SemanticSkeleton.standard_date_format(
           semantic,
           locale_id,
           cldr_calendar_for(date)
         ) do
      {:ok, standard, nil} -> standard
      _other -> semantic
    end
  end

  defp effective_format(_date, format, _locale_id), do: format

  defp find_format(_date, format, _locale_id, _options) when is_binary(format) do
    {:ok, format}
  end

  # A semantic skeleton names the meaning wanted rather than the fields; it
  # resolves to a classical skeleton and takes the same path from there.
  defp find_format(date, %Localize.DateTime.SemanticSkeleton{} = semantic, locale_id, options) do
    cldr_calendar = cldr_calendar_for(date)

    with {:ok, skeleton} <-
           Localize.DateTime.SemanticSkeleton.classical_skeleton(
             semantic,
             locale_id,
             cldr_calendar,
             date
           ) do
      [skeleton: skeleton, locale_id: locale_id, calendar: cldr_calendar, options: options]
      |> resolve_skeleton()
      |> Localize.DateTime.Formatter.explain_unresolved(date, skeleton)
    end
  end

  defp find_format(date, format, locale_id, options) when is_atom(format) do
    cldr_calendar = cldr_calendar_for(date)

    cond do
      # For standard formats on full dates, resolve via the standard format map
      format in @standard_formats and is_full_date(date) ->
        Localize.DateTime.Format.resolve_format(:date, format, locale_id, cldr_calendar, options)

      # A standard format names a format, not a skeleton: a date holding
      # fewer than the fields its pattern writes has no pattern of that
      # length. Callers derive a skeleton from the fields the value does hold
      # (`resolve_partial_format/2`) rather than matching the name.
      format in @standard_formats ->
        {:error,
         Localize.DateTimeUnresolvedFormatError.exception(format: format, locale: locale_id)}

      # Skeleton format — look up in available_formats
      true ->
        date
        |> resolve_date_skeleton(format, locale_id, options)
        |> Localize.DateTime.Formatter.explain_unresolved(date, format)
    end
  end

  defp find_format(_date, format, _locale_id, _options) do
    {:error, Localize.DateTimeFormatError.exception(format: format, reason: :invalid_format)}
  end

  @doc false
  # The pattern a skeleton of date fields resolves to for `date`, the
  # skeleton an atom or a string: `Localize.DateTime` resolves the date half
  # of a skeleton here.
  @spec resolve_date_skeleton(map(), atom() | String.t(), Localize.locale(), Keyword.t()) ::
          {:ok, String.t()} | {:error, Exception.t()}
  def resolve_date_skeleton(date, skeleton, locale_id, options) do
    resolve_skeleton(
      skeleton: skeleton,
      locale_id: locale_id,
      calendar: cldr_calendar_for(date),
      options: options
    )
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

  # The CLDR calendar whose data formats a value: its calendar's answer for
  # the value's date.
  defp cldr_calendar_for(value) when is_map(value),
    do: Localize.Calendar.date_calendar_type(value)

  defp cldr_calendar_for(_value), do: :gregorian

  # The locale a caller's options name, which is the canonical tag form where
  # they carry one, and the resolved id otherwise. The options reach here as a
  # keyword list or a map depending on the caller.
  defp locale_from_options(options, fallback) when is_list(options),
    do: Keyword.get(options, :locale, fallback)

  defp locale_from_options(%{} = options, fallback), do: Map.get(options, :locale, fallback)
  defp locale_from_options(_options, fallback), do: fallback

  defp resolve_skeleton(request) when is_list(request) do
    skeleton = Keyword.fetch!(request, :skeleton)
    locale_id = Keyword.fetch!(request, :locale_id)
    calendar = Keyword.get(request, :calendar, :gregorian)
    options = Keyword.get(request, :options, [])
    # Internal: skeletons already attempted in this resolution
    # chain. Prevents an infinite loop where `best_match`
    # returns the same skeleton it was given because the
    # candidate set already contains it (and we then re-look-up
    # in the calendar's available_formats where it's missing).
    seen = Keyword.get(request, :seen, MapSet.new())

    with {:ok, available} <-
           Localize.DateTime.Format.available_formats(
             locale_from_options(options, locale_id),
             calendar
           ) do
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
  # 2. If best_match for the calendar finds nothing, ask the
  #    formats the calendar inherits, and then append the
  #    fields no format carries (`inherited_or_appended/4`).
  #
  # The recursion of step 1 is guarded by a `seen` set so a
  # degenerate match cycle (`a → b → a`) terminates.
  # TR35 matches a skeleton to the closest available format and then adjusts
  # that format's field widths to the ones actually requested. Only the first
  # half was happening, and the difference shows wherever CLDR ships no entry
  # at the requested width: `en` has an `MMM` format and no `MMMM`, so asking
  # for `:MMMM` matched `MMM` and rendered "Jul" where the literal pattern
  # `"MMMM"` renders "July". The match was right; the width was not.
  defp adjust_to_requested_widths(pattern, requested, matched_id) do
    {:ok, tokens} = Localize.DateTime.Format.Match.tokenize_skeleton(requested)
    Localize.DateTime.Format.Match.adjust_field_lengths(pattern, tokens, matched_id)
  end

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
          resolve_matched_skeleton(skeleton, matched_id, locale_id, calendar, options, seen)

        {:ok, {_date_id, _time_id}} ->
          # Combined date+time skeleton — not applicable for
          # date-only formatting.
          {:error,
           Localize.DateTimeUnresolvedFormatError.exception(
             format: skeleton,
             locale: locale_id
           )}

        _no_match ->
          inherited_or_appended(skeleton, locale_id, calendar, options)
      end
    end
  end

  # No format of the calendar's own carries the skeleton's fields, so the
  # formats it inherits are asked, the Gregorian calendar's for most
  # calendars (`Localize.DateTime.Format.AppendItems.format_calendars/2`):
  # the format of that name, as a Hebrew date's `yw` is the Gregorian "week
  # 39 of 5786", or the closest, as `Yw` is. The values written are still
  # the calendar's own, since a pattern's fields are read from the date's
  # calendar. Where none carries them either, the closest format of fewer
  # fields is found among them all and the rest appended, TR35's Missing
  # Skeleton Fields, which was reached in the Gregorian calendar alone: a
  # Hebrew `yMMMdw` was an error, where the Gregorian is "Jun 16, 2026
  # (week: 25)".
  defp inherited_or_appended(skeleton, locale_id, calendar, options) do
    alias Localize.DateTime.Format.AppendItems

    case AppendItems.inherited_pattern(skeleton, locale_id, calendar, options) do
      {:ok, pattern} -> {:ok, pattern}
      nil -> append_items_or_error(skeleton, locale_id, calendar, options)
    end
  end

  defp resolve_matched_skeleton(skeleton, matched_id, locale_id, calendar, options, seen) do
    with {:ok, pattern} <-
           resolve_skeleton(
             skeleton: matched_id,
             locale_id: locale_id,
             calendar: calendar,
             options: options,
             seen: seen
           ) do
      adjust_to_requested_widths(pattern, skeleton, matched_id)
    end
  end

  # TR35's last resort before failing: no available format carries every
  # requested field, so match the closest format that is a subset of the
  # request and append the fields it lacks from the locale's append-item
  # templates. `en` has no quarter format, so `:yMMMdQ` becomes
  # "Jul 6, 2024 (quarter: Q3)" rather than an error.
  defp append_items_or_error(skeleton, locale_id, calendar, options) do
    case Localize.DateTime.Format.AppendItems.augment(skeleton, locale_id, calendar, options) do
      {:ok, pattern} ->
        {:ok, pattern}

      _unresolvable ->
        {:error,
         Localize.DateTimeUnresolvedFormatError.exception(
           format: skeleton,
           locale: locale_id
         )}
    end
  end

  @doc false
  # The skeleton is built from fixed symbols, so only a handful of atoms
  # can result, whatever the value holds.
  def derive_format_id(date, format \\ @default_format) do
    @date_fields_ordered
    |> Enum.filter(fn {field, _symbol} -> Map.has_key?(date, field) end)
    |> Enum.map_join(fn
      {:month, _symbol} -> month_symbol(format)
      {_field, symbol} -> symbol
    end)
    |> String.to_atom()
  end

  defp month_symbol(:short), do: "M"
  defp month_symbol(:medium), do: "MMM"
  defp month_symbol(_long_or_full), do: "MMMM"

  # ── Locale resolution ──────────────────────────────────────

  @doc """
  Parses a localized date string.

  Accepts any shape the locale accepts, including the locale's CLDR short,
  medium, long and full patterns and ISO 8601.

  A date in another calendar is parsed by passing that calendar's module
  as `:calendar`; the companion
  [calendrical](https://hex.pm/packages/calendrical) package supplies the
  calendars Localize formats for.

  ### Arguments

  * `string` is a string in any shape the locale accepts, including the
    locale's CLDR short, medium, long and full patterns and ISO 8601.

  * `options` is a keyword list of options.

  ### Options

  * `:locale` is a locale identifier. The default is the locale returned by
    `Localize.get_locale/0`.

  * `:calendar` is a calendar module, such as `Calendar.ISO` (the
    default), `Calendrical.Gregorian` or `Calendrical.Hebrew`. The input is
    read with the locale's patterns for the calendar's CLDR type, and the
    date is built and returned in this module. A week date, in any
    form ISO 8601 writes one in (`"2024-W05-4"`, `"2024W054"` and the
    week alone, `"2024-W05"`), is the calendar's own: every calendar
    answers `date_from_week_date/3`, so it is ISO 8601's week for
    `Calendar.ISO` and the fifth week of its own year for a calendar
    built of weeks. Text that none of the calendar's own formats reads
    is read in the calendar its `info/0` names as `:parsing_calendar`, and
    converted: a calendar built of weeks, whose months are `"M02"` and
    not `"Feb"`, names `Calendar.ISO`, so `"Feb 1, 2024"` is 1 February
    2024 in it. A composite calendar, whose dates are written with the
    formats of whichever of its calendars was in effect, names those
    calendars with its `parsing_calendars/0`, and a date is then
    read in each and converted, held to the calendar its day is written
    in. A calendar's own formats come before ISO 8601: a year, a
    month and a day between hyphens that any of them reads, as CLDR's
    root short date of the Chinese calendar does (`r-MM-dd`), is the
    calendar's own date, and where none does it is an ISO 8601 date,
    converted into the calendar. Anything that is not a calendar module,
    including a CLDR calendar name such as `:hebrew` or `"gregorian"`, and
    a module that implements only the `Calendar` behaviour, returns a
    `t:Localize.UnknownCalendarError.t/0`.

  * `:format` is the format the text was written with, as `to_string/2` takes it: a standard format (`:short`, `:medium`, `:long` or `:full`), a skeleton atom such as `:yMd`, a `Localize.DateTime.SemanticSkeleton` or a pattern string such as `"d/M/y"`. The text is read with that format and no other, after the calendar's own notation, so a date written by a skeleton whose fields stand in another order than the locale's standard formats' reads back as itself: `mt`'s `:yMd` writes 3 April 2024 as "4/3/2024", which is 4 March where no format is given. A pattern string is read before the notation, which is never what it writes, and the notation where the pattern reads nothing. A format of fewer fields than a date has, such as `:yMMM`, needs `as: :map`. The default is `nil`: the text is read in whichever of the locale's formats reads it first.

  * `:reference_date` is the `t:Date.t/0` that partial input is completed
    against, taken in the calendar the input is read in. A week written
    without its year is a week of the reference date's week-based year,
    which is not the year of its days about the new year. The default is
    today.

  * `:as` is `:struct` or `:map`. `:map` returns only the fields the input
    actually carried, rather than completing them. They must still be
    fields some date has, so `"June 31"` is an error in both forms while
    `"February 29"` is a partial date. A date read in another calendar and
    converted, as a composite calendar reads one of an earlier calendar,
    comes back whole, as a partial date has no fields in the other
    calendar. What names no day to convert is the exception: a year is
    `%{year: 2026}`, and a year and a quarter are the two. The default is
    `:struct`.

  ### Returns

  * `{:ok, value}` where `value` is a `t:Date.t/0`, or

  * `{:error, exception}` if the string does not parse, a
    `Localize.DateTimeFormatError` or a
    `Localize.DateTimeUnresolvedFormatError` if `:format` is no
    format of a date, or a `t:Localize.InvalidValueError.t/0` if `string`
    is not a string or an option is malformed.

  ### Examples

      iex> Localize.Date.parse("22.03.2026", locale: :de)
      {:ok, ~D[2026-03-22]}

      iex> Localize.Date.parse("March 22, 2026", locale: :en)
      {:ok, ~D[2026-03-22]}

      iex> Localize.Date.parse("4/3/2024", locale: :en)
      {:ok, ~D[2024-04-03]}

      iex> Localize.Date.parse("4/3/2024", locale: :en, format: "d/M/y")
      {:ok, ~D[2024-03-04]}

  """
  @spec parse(String.t(), Keyword.t()) :: {:ok, Date.t()} | {:error, Exception.t()}
  def parse(string, options \\ []) do
    with :ok <- Localize.DateTime.ParseOptions.validate(string, options) do
      Localize.Date.Parser.parse(string, options)
    end
  end

  @doc """
  Parses a date written with a `Calendar.strftime/3` format.

  The format is translated into the pattern the locale is read with by
  `Localize.DateTime.Strptime.pattern/2`, and the text read with it by
  `parse/2`, so a date `Calendar.strftime/3` writes with
  `Localize.Calendar.strftime_options!/1` reads back in the same locale,
  as does text from C, Python or Ruby. The [strptime guide](strptime.html)
  lists the directives and where the reading differs from C's
  `strptime(3)`.

  ### Arguments

  * `string` is the text to parse.

  * `format` is a `Calendar.strftime/3` format string, such as
    `"%d %B %Y"`.

  * `options` is a keyword list of options.

  ### Options

  * `:preferred_datetime`, `:preferred_date` and `:preferred_time` are
    the formats `%c`, `%x` and `%X` stand for, as `Calendar.strftime/3`
    takes them.

  * Every option of `parse/2` but `:format`: `:locale`, `:calendar`,
    `:reference_date` and `:as`.

  ### Returns

  * `{:ok, date}`, as `parse/2` returns it, or

  * `{:error, exception}`, a `t:Localize.DateTimeFormatError.t/0` where
    the format has a directive Localize does not read, or the error
    `parse/2` returns where the text does not parse.

  ### Examples

      iex> Localize.Date.strptime("04/03/2026", "%d/%m/%Y", locale: :en)
      {:ok, ~D[2026-03-04]}

      iex> Localize.Date.strptime("4 mars 2026", "%e %B %Y", locale: :fr)
      {:ok, ~D[2026-03-04]}

      iex> Localize.Date.strptime("2026-063", "%Y-%j", locale: :en)
      {:ok, ~D[2026-03-04]}

  """
  @spec strptime(String.t(), String.t(), Keyword.t()) :: {:ok, Date.t()} | {:error, Exception.t()}
  def strptime(string, format, options \\ []) do
    with {:ok, pattern} <- Localize.DateTime.Strptime.pattern(format, options) do
      parse(string, Localize.DateTime.Strptime.parse_options(options, pattern))
    end
  end
end
