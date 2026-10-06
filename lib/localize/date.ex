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
    and wide at `:long` and `:full`. A date in a calendar of weeks,
    such as `Calendrical.ISOWeek`, is written at every standard
    format in the calendar's own notation, as its `date_to_string/3`
    writes it, `"2026-W25-2"`, which parses back as itself. Its
    month field holds a week, so a year and a week of it is written
    as the locale writes a week of the year, `"week 25 of 2026"`,
    and a skeleton's month is its week and its day the weekday:
    `:yMMMd` writes `"Tue, week 25 of 2026"`.

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
         {:ok, pattern, locale_id, formatter_options} <- formatting_plan(date, options) do
      Localize.DateTime.Formatter.format(date, pattern, locale_id, formatter_options)
    end
  end

  # Resolves the format pattern, locale, and formatter options for a
  # date — the shared front half of `to_string/2` and `to_parts/2`.
  defp formatting_plan(%{year: _, month: _, day: _} = date, options)
       when is_keyword_list(options) do
    locale = Keyword.get(options, :locale, Localize.get_locale())
    format = Keyword.get(options, :format, @default_format)

    with {:ok, locale_id} <- resolve_locale_id(locale),
         effective = effective_format(date, format, locale_id),
         {:ok, pattern} <- find_format(date, effective, locale_id, options) do
      overrides = number_system_overrides_for(date, effective, locale_id)

      formatter_options =
        options
        |> Map.new()
        |> Map.put_new(:locale, locale)
        |> merge_number_system_overrides(overrides)

      {:ok, pattern_variations(pattern, format), locale_id, formatter_options}
    end
  end

  # Partial date
  defp formatting_plan(date, options) when has_date_field(date) and is_keyword_list(options) do
    locale = Keyword.get(options, :locale, Localize.get_locale())
    format = Keyword.get(options, :format)

    with {:ok, locale_id} <- resolve_locale_id(locale) do
      resolved_format = resolve_partial_format(format, date)
      options = Keyword.put_new(options, :locale, locale)
      partial_formatting_plan(resolved_format, date, format, locale_id, options)
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

  defp partial_formatting_plan(resolved_format, date, format, locale_id, options) do
    with {:ok, pattern} <- find_format(date, resolved_format, locale_id, options) do
      overrides = number_system_overrides_for(date, resolved_format, locale_id)

      formatter_options =
        options |> Map.new() |> merge_number_system_overrides(overrides)

      {:ok, pattern_variations(pattern, format), locale_id, formatter_options}
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

    # For standard formats on full dates, resolve via the standard format map
    if format in @standard_formats and is_full_date(date) do
      standard_date_format(date, format, locale_id, cldr_calendar, options)
    else
      # Skeleton format — look up in available_formats
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
  @spec resolve_date_skeleton(map(), atom() | String.t(), atom(), Keyword.t()) ::
          {:ok, String.t()} | {:error, Exception.t()}
  def resolve_date_skeleton(date, skeleton, locale_id, options) do
    {skeleton, calendar} = own_fields(date, skeleton)

    resolve_skeleton(
      skeleton: skeleton,
      locale_id: locale_id,
      calendar: calendar,
      options: options
    )
  end

  @doc false
  # The skeleton a date's own fields are written with, and the CLDR calendar
  # whose formats write it. A skeleton names fields, and a calendar of weeks
  # holds other things in two of them: a week in its month field and the day
  # of that week in its day field (user, 2026-10-04: "For week based
  # calendars we need to interpret `:month` as `:week` and pick the correct
  # skeleton accordingly"). So a skeleton's month is the date's week and its
  # day the weekday: `yMMMd` is `ywE`, "Tue, week 25 of 2026" for
  # "2026-W25-2" (user, 2026-10-06). A skeleton that names a week, its own
  # or the month's, is written with the formats of the calendar the dates
  # are read in (`parsing_calendar/0`), which are the ones that name a week.
  # The calendar's period and day number, written as a month and a day of
  # the month, "M06 2, 2026 AD", named no week and read back as no date; a
  # pattern still writes them, and so does a skeleton that names a week
  # beside its month (`MMMMW`), whose month is then the period.
  @spec own_fields(map(), atom() | String.t()) :: {atom() | String.t(), atom()}
  def own_fields(date, skeleton) do
    with %{calendar: calendar} <- date,
         :ok <- Localize.Calendar.validate_calendar(date),
         {:ok, parsing} when parsing != calendar <- Localize.Calendar.parsing_calendar(calendar) do
      weeks = week_skeleton(skeleton)

      if names_week?(weeks),
        do: {weeks, Localize.Calendar.cldr_calendar_type(parsing)},
        else: {weeks, cldr_calendar_for(date)}
    else
      _the_fields_it_names -> {skeleton, cldr_calendar_for(date)}
    end
  end

  # A skeleton with its month as a week, unless it names a week already, and
  # its day as a weekday, unless it names one. No atom is made: a skeleton no
  # format is named by is matched as a string.
  defp week_skeleton(skeleton) do
    letters = skeleton_letters(skeleton)
    week? = names_week?(skeleton)
    weekday? = Enum.any?(letters, &(&1 in ["E", "e", "c"]))

    weeks =
      letters
      |> Enum.chunk_by(& &1)
      |> Enum.map_join(fn
        [letter | _rest] = run when letter in ["M", "L"] ->
          if week?, do: Enum.join(run), else: "w"

        ["d" | _rest] ->
          if weekday?, do: "", else: "E"

        run ->
          Enum.join(run)
      end)

    cond do
      weeks == Kernel.to_string(skeleton) -> skeleton
      atom = Localize.Utils.Helpers.existing_atom(weeks) -> atom
      true -> weeks
    end
  end

  defp names_week?(skeleton), do: Enum.any?(skeleton_letters(skeleton), &(&1 in ["w", "W"]))

  defp skeleton_letters(skeleton), do: skeleton |> Kernel.to_string() |> String.graphemes()

  # A standard format is the locale's standard date format of that length,
  # unless the date's calendar writes its dates in a notation of its own:
  # then it is that notation at every length, "2026-W25-2" for a calendar of
  # weeks, quoted so the formatter writes it as the calendar wrote it.
  defp standard_date_format(date, format, locale_id, cldr_calendar, options) do
    case Localize.Calendar.notation(date) do
      {:ok, notation} ->
        {:ok, "'" <> String.replace(notation, "'", "''") <> "'"}

      :none ->
        Localize.DateTime.Format.resolve_format(:date, format, locale_id, cldr_calendar, options)

      {:error, _exception} = error ->
        error
    end
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

        _no_match ->
          append_items_or_error(skeleton, locale_id, calendar, options)
      end
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
    week? = week_in_month_field?(date)

    @date_fields_ordered
    |> Enum.filter(fn {field, _symbol} -> Map.has_key?(date, field) end)
    |> Enum.map_join(fn
      {:month, _symbol} -> if week?, do: "w", else: month_symbol(format)
      {_field, symbol} -> symbol
    end)
    |> String.to_atom()
  end

  # A calendar of weeks holds a week in its dates' month field, and a date
  # of it without a day is that week: written as the locale writes a week
  # of the year (`yw`, "week 25 of 2026"), where a month is written by its
  # name. A calendar of weeks is one that writes its whole dates in a
  # notation of its own (`Localize.Calendar.own_notation?/1`).
  defp week_in_month_field?(%{calendar: calendar} = date) when not is_map_key(date, :day) do
    Localize.Calendar.validate_calendar(date) == :ok and
      match?({:ok, true}, Localize.Calendar.own_notation?(calendar))
  end

  defp week_in_month_field?(_date), do: false

  defp month_symbol(:short), do: "M"
  defp month_symbol(:medium), do: "MMM"
  defp month_symbol(_long_or_full), do: "MMMM"

  # ── Locale resolution ──────────────────────────────────────

  defp resolve_locale_id(locale), do: Localize.Locale.cldr_locale_id_from(locale)

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
    date is built and returned in this module. A calendar of weeks, such
    as `Calendrical.ISOWeek`, reads its own notation as it writes it,
    `"2024-W05-4"`, and any other input as a Gregorian date, as its
    `parsing_calendar/0` says, since a written month and day name no
    single week; the date is converted into it, so `"Feb 1, 2024"` is
    2024-W05-4. A calendar's own formats come before ISO 8601: a year, a
    month and a day between hyphens that any of them reads, as CLDR's
    root short date of the Chinese calendar does (`r-MM-dd`), is the
    calendar's own date, and where none does it is an ISO 8601 date,
    converted into the calendar. Anything that is not a calendar module,
    including a CLDR calendar name such as `:hebrew` or `"gregorian"`, and
    a module that implements only the `Calendar` behaviour, returns a
    `t:Localize.UnknownCalendarError.t/0`.

  * `:format` is the format the text was written with, as `to_string/2` takes it: a standard format (`:short`, `:medium`, `:long` or `:full`), a skeleton atom such as `:yMd`, a `Localize.DateTime.SemanticSkeleton` or a pattern string such as `"d/M/y"`. The text is read with that format and no other, after the calendar's own notation, so a date written by a skeleton whose fields stand in another order than the locale's standard formats' reads back as itself: `mt`'s `:yMd` writes 3 April 2024 as "4/3/2024", which is 4 March where no format is given. A format of fewer fields than a date has, such as `:yMMM`, needs `as: :map`. The default is `nil`: the text is read in whichever of the locale's formats reads it first.

  * `:reference_date` is the `t:Date.t/0` that partial input is completed
    against, taken in the calendar the input is read in. The default is
    today.

  * `:as` is `:struct` or `:map`. `:map` returns only the fields the input
    actually carried, rather than completing them. They must still be
    fields some date has, so `"June 31"` is an error in both forms while
    `"February 29"` is a partial date. A date read in another calendar and
    converted, as a calendar of weeks reads one, comes back whole, as a
    partial date has no fields in the other calendar. A week is the
    exception: it names no day, and a calendar of weeks holds it in its
    month field, so `"week 25 of 2026"` is `%{year: 2026, month: 25}`, the
    value `to_string/2` writes it from. The default is `:struct`.

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
end
