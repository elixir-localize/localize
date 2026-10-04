defmodule Localize.DateTime.Parser do
  @moduledoc """
  Parses a locale-formatted string as whichever temporal value it turns
  out to be — a date, a time, a datetime, or a date range.

  `Localize.Date.parse/2`, `Localize.Time.parse/2`,
  `Localize.DateTime.parse/2` and `Localize.Interval.parse/2` each parse
  one shape and expect the caller to know which. `parse/2` here is for
  the case where the shape is not known up front: a single text field
  that may carry any of `"2026-05-16"`, `"14:30"`, `"May 16, 2026 2:30
  PM"` or `"May 5 – May 10, 2026"`. The caller pattern-matches on the
  returned struct to discover what was parsed.

  """

  # The module also hosts the internal datetime parser reached through
  # `Localize.DateTime.parse/2`.
  #
  # Strategy:
  #
  # 1. Try bare ISO-8601 (`YYYY-MM-DDTHH:MM:SS[.frac][Z|±HH:MM]`).
  # This is the wire format and always works.
  #
  # 2. Otherwise, consult the locale's CLDR date-time glue
  # pattern (`{1}, {0}` in `en`, `{1} {0}` in `ja`, etc.),
  # split the input on the literal glue separator, and
  # delegate to `Localize.Date.parse/2` and
  # `Localize.Time.parse/2` for the two halves.
  #
  # Where `:format`, `:date_format` or `:time_format` names the format
  # the text was written with, ISO 8601 is not tried: each half is read
  # with its part of the format alone, and a pattern of a date and time
  # is split, with the input, at the text between its date fields and
  # its time fields (`half_formats/2`).
  #
  # Implements the parts of [TR35 §Parsing Dates
  # Times](https://unicode.org/reports/tr35/tr35-dates.html#Parsing_Dates_Times)
  # that apply to date+time input. A fixed UTC offset — ISO 8601
  # (`Z`, `±HH:MM`) or the localized GMT format in any locale's
  # spelling (`GMT+10:30`, `UTC-5`) — is arithmetic and resolves
  # here. Named timezone suffixes (`EST`, `Asia/Tokyo`) carry no
  # offset of their own and need per-zone IANA-database
  # integration, which lives outside this parser.
  #
  # ### Returns
  #
  # * `{:ok, NaiveDateTime.t()}` when no zone info was present, or
  # when a named zone could not be resolved.
  # * `{:ok, DateTime.t()}` when the input carried a fixed offset.
  # * `{:error, Localize.DateTimeParseError.t()}` on failure.
  #

  alias Localize.DateTime.Format
  alias Localize.DateTimeParseError

  @standard_formats [:short, :medium, :long, :full]

  @doc """
  Parses a locale-formatted string as a date, time, datetime, or date
  range — whichever matches.

  ### Arguments

  * `input` is the string to parse.

  * `options` is a keyword list of options.

  ### Options

  * `:locale` is any locale returned by `Localize.all_locale_ids/0`.
    The default is `Localize.get_locale/0`.

  * Remaining options are passed to whichever sub-parser matches.

  ### Returns

  * `{:ok, value}` where `value` is a `t:Date.t/0`, `t:Time.t/0`,
    `t:NaiveDateTime.t/0`, `t:DateTime.t/0` or `t:Date.Range.t/0`.

  * `{:error, exception}`, a `t:Localize.DateTimeParseError.t/0` whose
    `:attempts` records what each sub-parser reported, or a
    `t:Localize.InvalidValueError.t/0` if `input` is not a string or an
    option is malformed.

  ### Examples

      iex> Localize.DateTime.Parser.parse("March 22, 2026", locale: :en)
      {:ok, ~D[2026-03-22]}

      iex> Localize.DateTime.Parser.parse("3:45 PM", locale: :en)
      {:ok, ~T[15:45:00]}

  """
  @spec parse(String.t(), Keyword.t()) ::
          {:ok,
           Date.t()
           | Time.t()
           | NaiveDateTime.t()
           | DateTime.t()
           | Date.Range.t()
           | map()
           | {map(), map()}}
          | {:error, Exception.t()}
  def parse(input, options \\ []) do
    with :ok <- Localize.DateTime.ParseOptions.validate(input, options) do
      parse_valid(input, options)
    end
  end

  # The `:calendar` option is the caller's calendar module, and the date
  # and datetime parsers build their results in it; an interval's
  # separator is the one of the calendar its dates are read in.
  defp parse_valid(input, options) do
    with {:ok, calendar_module} <- Localize.Date.Parser.calendar_option(options),
         {:ok, parsing} <- Localize.Calendar.parsing_calendar(calendar_module) do
      parse_with_calendar(input, options, parsing)
    end
  end

  defp parse_with_calendar(input, options, calendar_module) do
    locale = Keyword.get(options, :locale) || Localize.get_locale()
    trimmed = String.trim(input)

    attempts = []

    with {:next, attempts} <-
           try_interval(trimmed, locale, calendar_module, options, attempts),
         {:next, attempts} <- try_date(trimmed, options, attempts),
         {:next, attempts} <- try_time(trimmed, options, attempts),
         {:next, attempts} <- try_datetime(trimmed, options, attempts) do
      {:error,
       DateTimeParseError.exception(
         input: input,
         locale: locale,
         attempts: Enum.reverse(attempts)
       )}
    end
  end

  # ### Dispatch strategy
  #
  # `parse/2` tries each sub-parser in the following order and returns
  # the first success:
  #
  # 1. **Interval** — only attempted when the input contains an
  # interval-shaped separator (the locale's `intervalFormatFallback`
  # separator, or one of `–`, `—`, `−`, `〜`, `~`, ` - `, ` / `,
  # ` to `). Cheap fail-fast.
  #
  # 2. **Date** — whole-string anchored, so a date+time input won't
  # accidentally match.
  #
  # 3. **Time** — whole-string anchored, so a date-only input won't
  # match (no `:`).
  #
  # 4. **DateTime** — the most expensive (it splits on every glue
  # separator position and runs the date+time parsers on each half),
  # so it runs last as a fallback for inputs carrying both.
  #
  # The order encodes a tiebreaker preference: for ambiguous inputs
  # (e.g. a bare 4-digit year that could be a date or a time) the date
  # interpretation wins.

  defp try_interval(input, locale, calendar_module, options, attempts) do
    if has_interval_separator?(input, locale, calendar_module) do
      case Localize.Interval.parse(input, options) do
        {:ok, _} = ok -> ok
        {:error, err} -> {:next, [{:interval, err} | attempts]}
      end
    else
      {:next, attempts}
    end
  end

  defp try_date(input, options, attempts) do
    case Localize.Date.parse(input, options) do
      {:ok, _} = ok -> ok
      {:error, err} -> {:next, [{:date, err} | attempts]}
    end
  end

  defp try_time(input, options, attempts) do
    case Localize.Time.parse(input, options) do
      {:ok, _} = ok -> ok
      {:error, err} -> {:next, [{:time, err} | attempts]}
    end
  end

  defp try_datetime(input, options, attempts) do
    case Localize.DateTime.parse(input, options) do
      {:ok, _} = ok -> ok
      {:error, err} -> {:next, [{:datetime, err} | attempts]}
    end
  end

  # Cheap check: does the input contain an interval-shaped separator?
  # Mirrors the candidate list used by
  # `Localize.Date.Parser.split_on_interval_separator/3` so that
  # anything `Localize.Interval.parse/2` could match is also detected
  # here.
  defp has_interval_separator?(input, locale, calendar_module) do
    cldr_sep = lookup_interval_separator(locale, calendar_module)

    candidates =
      [cldr_sep | ["–", "—", "−", "〜", "~", " - ", " / ", " to "]]
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    Enum.any?(candidates, fn sep ->
      case String.split(input, sep, parts: 2) do
        [left, right] -> String.trim(left) != "" and String.trim(right) != ""
        _ -> false
      end
    end)
  end

  defp lookup_interval_separator(locale, calendar_module) do
    cldr_calendar = Localize.Date.Parser.cldr_calendar_type(calendar_module)

    case Format.interval_formats(locale, cldr_calendar) do
      {:ok, intervals} ->
        case Map.get(intervals, :interval_format_fallback) do
          [0, separator, 1] when is_binary(separator) -> String.trim(separator)
          _ -> nil
        end

      _ ->
        nil
    end
  end

  @doc false
  @spec parse_datetime(String.t(), Keyword.t()) ::
          {:ok, NaiveDateTime.t() | DateTime.t() | map()} | {:error, Exception.t()}
  def parse_datetime(input, options \\ []) when is_binary(input) do
    with {:ok, calendar_module} <- Localize.Date.Parser.calendar_option(options) do
      do_parse_datetime(input, options, calendar_module)
    end
  end

  defp do_parse_datetime(input, options, calendar_module) do
    locale = Keyword.get(options, :locale) || Localize.get_locale()

    as = Keyword.get(options, :as, :struct)

    # The input as given is tried before the input with a leading
    # weekday stripped: a CLDR pattern can carry the weekday anywhere,
    # and a weekday name can also be a month name (es "mar" is both
    # martes and marzo). Ordinal stripping doesn't need to be applied
    # here because each half is forwarded through
    # `Localize.Date.parse/2` / `Localize.Time.parse/2`, and
    # `Date.parse/2` already runs the ordinal-fallback retry per
    # endpoint.
    normalised = Localize.Date.Parser.normalise_input(input)
    stripped = Localize.Date.Parser.preprocess_safe(normalised, locale, calendar_module)
    candidates = Enum.uniq([normalised, stripped])

    # ISO 8601 writes a Gregorian date and time, which is converted into
    # the calendar asked for. The locale's patterns read the date half
    # through `Localize.Date.parse/2`, which reads it in the calendar's
    # `parsing_calendar/0` and converts it, as for a calendar of weeks. A
    # date and time in the calendar's own formats comes before either.
    #
    # Where a format names how the text was written, each half is read
    # with its part of it and with nothing else, ISO 8601 included, as
    # `Localize.Date.parse/2` and `Localize.Time.parse/2` read with one.
    case half_formats(options, locale) do
      {:ok, nil} ->
        with nil <- own_format_datetime(candidates, locale, options, as) do
          iso_or_locale_datetime(candidates, locale, options, calendar_module, as)
        end

      {:ok, halves} ->
        try_locale_glue_candidates(candidates, locale, Keyword.merge(options, halves), as)

      {:error, _exception} = error ->
        error
    end
  end

  # The format each half of a date and time was written with, as
  # `Localize.DateTime.to_string/2` writes them: `:date_format` and
  # `:time_format` where given, else the halves of `:format`. A standard
  # format is the date's and the time's alike; a skeleton is split into its
  # date fields and its time fields, which the formatter resolves on their
  # own; a pattern is split at the text between its date fields and its time
  # fields, where the input is then split too. `nil` where no format is
  # given, and the text is read in any format.
  defp half_formats(options, locale) do
    given = {Keyword.get(options, :date_format), Keyword.get(options, :time_format)}

    with {:ok, {date_half, time_half, glue}} <-
           format_halves(Keyword.get(options, :format), locale) do
      case {elem(given, 0) || date_half, elem(given, 1) || time_half} do
        {nil, nil} ->
          {:ok, nil}

        {date_format, time_format} ->
          {:ok, [format: nil, date_format: date_format, time_format: time_format, glue: glue]}
      end
    end
  end

  defp format_halves(nil, _locale), do: {:ok, {nil, nil, nil}}

  defp format_halves(format, _locale) when format in @standard_formats,
    do: {:ok, {format, format, nil}}

  # A skeleton is the caller's, so a half of it is a format only where a
  # format of that name is known already: no atom is made for it. A half
  # that is none is read in any format.
  defp format_halves(format, locale) when is_atom(format) do
    alias Localize.Utils.Helpers

    case Format.Match.separate_date_and_time(format) do
      {date_fields, time_fields} ->
        {:ok, {Helpers.existing_atom(date_fields), Helpers.existing_atom(time_fields), nil}}

      nil ->
        cond do
          Format.Match.only_fields?(format, :date) ->
            {:ok, {format, nil, nil}}

          Format.Match.only_fields?(format, :time) ->
            {:ok, {nil, format, nil}}

          true ->
            {:error,
             Localize.DateTimeUnresolvedFormatError.exception(format: format, locale: locale)}
        end
    end
  end

  defp format_halves(format, _locale) when is_binary(format), do: split_pattern(format)

  # A semantic skeleton of a date and time is not yet read as a format.
  defp format_halves(%Localize.DateTime.SemanticSkeleton{}, _locale), do: {:ok, {nil, nil, nil}}

  defp format_halves(format, _locale),
    do: {:error, Localize.DateTimeFormatError.exception(format: format, reason: :invalid_format)}

  @date_letters ~w(G y Y u U r Q q M L l w W d D F g E e c)
  @time_letters ~w(a b B h H K k j J C m s S A z Z O v V X x)

  # A pattern of a date and time writes its date fields in one run and its
  # time fields in another, with literal text between them: "d/M/y HH:mm",
  # "HH:mm 'on' d MMMM y". The halves are patterns of a date and of a time,
  # and the text between them is where the input is split. A pattern whose
  # date and time fields are not two runs, or that is no pattern, is an
  # error.
  defp split_pattern(pattern) do
    segments =
      ~r/'(?:[^']|'')*'|([a-zA-Z])\1*|[^'a-zA-Z]+/u
      |> Regex.scan(pattern)
      |> Enum.map(fn [segment | _letter] -> {segment_kind(segment), segment} end)

    kinds = for {kind, _segment} <- segments, kind != :literal, do: kind

    with true <- Enum.map_join(segments, &elem(&1, 1)) == pattern,
         [first, second] when first in [:date, :time] and second in [:date, :time] <-
           Enum.dedup(kinds) do
      {before, second_half} = Enum.split_while(segments, &(elem(&1, 0) != second))
      first_half = trim_trailing_literals(before)
      glue = Enum.drop(before, length(first_half))

      first_pattern = Enum.map_join(first_half, &elem(&1, 1))
      second_pattern = Enum.map_join(second_half, &elem(&1, 1))
      separator = glue |> Enum.map_join(&elem(&1, 1)) |> unquote_cldr_literal()

      case first do
        :date -> {:ok, {first_pattern, second_pattern, {separator, :date_first}}}
        :time -> {:ok, {second_pattern, first_pattern, {separator, :time_first}}}
      end
    else
      _not_two_runs ->
        {:error, Localize.DateTimeFormatError.exception(format: pattern, reason: :invalid_format)}
    end
  end

  defp trim_trailing_literals(segments) do
    segments
    |> Enum.reverse()
    |> Enum.drop_while(&(elem(&1, 0) == :literal))
    |> Enum.reverse()
  end

  defp segment_kind(segment) do
    letter = String.first(segment)

    cond do
      letter in @date_letters -> :date
      letter in @time_letters -> :time
      letter =~ ~r/\A[a-zA-Z]\z/ -> :unknown
      true -> :literal
    end
  end

  defp iso_or_locale_datetime(candidates, locale, options, calendar_module, as) do
    case Enum.find_value(candidates, :error, &iso_candidate/1) do
      {:ok, value} ->
        with {:ok, value} <- Localize.Date.Parser.convert_value(value, calendar_module) do
          {:ok, finalise_datetime(value, as)}
        end

      :error ->
        try_locale_glue_candidates(candidates, locale, options, as)
    end
  end

  # A date and time whose date is one of the calendar's own, as its formats
  # read a date alone ("2023-11-18 14:30:45" with the Chinese calendar's
  # `r-MM-dd`; `Localize.Date.Parser.own_format_date/2`), is that
  # calendar's: the locale's patterns read it before ISO 8601 does, its
  # offset with it. No locale's pattern joins a date to a time with ISO
  # 8601's `T`, so text with one is ISO 8601's.
  defp own_format_datetime(candidates, locale, options, as) do
    Enum.find_value(candidates, fn input ->
      with [_input, date_text] <- Regex.run(~r/\A(\d{4}-\d{2}-\d{2}) /, input),
           {:ok, _date} <- Localize.Date.Parser.own_format_date(date_text, options),
           {:ok, _value} = ok <- try_locale_glue(input, locale, options, as) do
        ok
      else
        _not_the_calendars_own -> nil
      end
    end)
  end

  defp iso_candidate(input) do
    case try_iso(input) do
      {:ok, _value} = ok -> ok
      :error -> nil
    end
  end

  # The first candidate's error is the one reported.
  defp try_locale_glue_candidates([input | rest], locale, options, as) do
    case try_locale_glue(input, locale, options, as) do
      {:ok, _value} = ok -> ok
      error -> Enum.find_value(rest, error, &glue_candidate(&1, locale, options, as))
    end
  end

  defp glue_candidate(input, locale, options, as) do
    case try_locale_glue(input, locale, options, as) do
      {:ok, _value} = ok -> ok
      _error -> nil
    end
  end

  # ISO 8601 always yields full year+month+day+hour+minute+second.
  # The map merges the date and time fields and surfaces the
  # `:time_zone` string when the input carried a `Z` or offset.
  defp finalise_datetime(%NaiveDateTime{} = ndt, :struct), do: ndt
  defp finalise_datetime(%DateTime{} = dt, :struct), do: dt

  defp finalise_datetime(%NaiveDateTime{} = ndt, :map) do
    naive_datetime_to_map(ndt)
  end

  defp finalise_datetime(%DateTime{} = dt, :map) do
    dt
    |> DateTime.to_naive()
    |> naive_datetime_to_map()
    |> Map.merge(datetime_zone_fields(dt))
  end

  defp datetime_zone_fields(%DateTime{} = datetime) do
    Map.take(datetime, [:time_zone, :utc_offset, :std_offset, :zone_abbr])
  end

  defp naive_datetime_to_map(%NaiveDateTime{
         year: y,
         month: m,
         day: d,
         hour: h,
         minute: mi,
         second: s,
         microsecond: us,
         calendar: cal
       }) do
    base = %{
      year: y,
      month: m,
      day: d,
      hour: h,
      minute: mi,
      second: s,
      calendar: cal
    }

    case us do
      {_, 0} -> base
      other -> Map.put(base, :microsecond, other)
    end
  end

  defp try_locale_glue(input, locale, options, as) do
    cldr_calendar =
      options
      |> Keyword.get(:calendar, Calendar.ISO)
      |> Localize.Date.Parser.cldr_calendar_type()

    case split_separators(Keyword.get(options, :glue), locale, cldr_calendar) do
      [] ->
        {:error, no_match_error(input, locale)}

      separators ->
        # The glue separator (e.g. `, ` in en) often appears
        # inside the date half too — `MMM d, y` puts a comma
        # between day and year. Try every split point for every
        # candidate separator and accept the first that yields
        # parseable date + time halves.
        candidates =
          for {prefix, sep, suffix, order} <- separators,
              body <- strip_glue_affixes(input, prefix, suffix),
              {left, right} <- enumerate_splits(body, sep) do
            date_and_time(order, left, right)
          end

        finder =
          case as do
            :map -> &try_split_as_map(&1, options)
            :struct -> &try_split_as_struct(&1, options)
          end

        Enum.find_value(
          candidates,
          {:error, no_match_error(input, locale)},
          finder
        )
    end
  end

  # The text is split where the locale's date-time patterns join a date to
  # a time, or, read with a pattern of a date and time, at the text that
  # pattern puts between its date fields and its time fields and nowhere
  # else: with surrounding spaces or without them, and at every place where
  # the two run together ("yyyyMMddHHmmss").
  defp split_separators(nil, locale, cldr_calendar), do: glue_separators(locale, cldr_calendar)

  defp split_separators({"", order}, _locale, _cldr_calendar), do: [{"", "", "", order}]

  defp split_separators({glue, order}, _locale, _cldr_calendar) do
    [glue, String.trim(glue)]
    |> Enum.uniq()
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&{"", &1, "", order})
  end

  # A glue pattern with the time first, as `vi`'s "{0} {1}", has its date
  # on the right of the split.
  defp date_and_time(:date_first, left, right), do: {left, right}
  defp date_and_time(:time_first, left, right), do: {right, left}

  # The input inside the literal text a glue pattern puts before its first
  # half and after its second, as `vi`'s "'lúc' {0} {1}" puts "lúc ", or
  # nothing when the input does not carry it.
  defp strip_glue_affixes(input, prefix, suffix) do
    if String.starts_with?(input, prefix) and String.ends_with?(input, suffix) do
      body = binary_part(input, byte_size(prefix), byte_size(input) - byte_size(prefix))
      body = binary_part(body, 0, byte_size(body) - byte_size(suffix))
      if body == "", do: [], else: [body]
    else
      []
    end
  end

  defp try_split_as_struct({date_text, time_text}, options) do
    # Check the time half first: it is cheaper to parse and far more
    # selective (a time needs an hour), so a failing time half
    # short-circuits the expensive date parse on every non-time split.
    with {:ok, time, zone} <-
           Localize.Time.Parser.parse_with_zone(time_text, time_options(options)),
         {:ok, date} <- Localize.Date.parse(date_text, date_options(options)),
         {:ok, ndt} <- naive_datetime(date, time) do
      case zone do
        nil -> {:ok, ndt}
        _ -> {:ok, resolve_zone(zone, ndt, options)}
      end
    else
      unread -> half_error(unread)
    end
  end

  # The date is in the calendar the input is read in and the time in
  # `Calendar.ISO`, while `NaiveDateTime.new/2` takes the two in one
  # calendar, so the fields are joined in the date's. Each half has been
  # validated by its own parser, as `NaiveDateTime.new/2` relies on.
  defp naive_datetime(%Date{} = date, %Time{} = time) do
    {:ok,
     %NaiveDateTime{
       calendar: date.calendar,
       year: date.year,
       month: date.month,
       day: date.day,
       hour: time.hour,
       minute: time.minute,
       second: time.second,
       microsecond: time.microsecond
     }}
  end

  # A fixed UTC offset — ISO 8601 (`+05:30`, `Z`) or the localized GMT
  # format in any locale's spelling (`GMT+10:30`, `UTC-5`, `غرينتش+03:00`)
  # — is arithmetic, so it resolves with no time zone database.
  #
  # A named zone (`EDT`, `Asia/Tokyo`, "heure : New York") resolves through
  # the time zone database the application configures, as
  # `Localize.DateTime.Timezone.resolve/3` describes. Where none is
  # configured the zone does not resolve, and the parse keeps the
  # `NaiveDateTime` rather than failing the whole input.
  defp resolve_zone(zone, naive_datetime, options) do
    case Localize.DateTime.Timezone.resolve(zone, naive_datetime, options) do
      {:ok, datetime} -> datetime
      {:error, _unresolved} -> naive_datetime
    end
  end

  @doc false
  # The zone fields a map-form parse carries for a captured zone, as the
  # struct form's `DateTime` has them. A fixed offset (`GMT+5`, `UTC-3:30`,
  # `Z`) is the same on every date, so it resolves whether or not the input
  # gave one. A named zone's offset depends on the date, so it resolves
  # only against `naive_datetime`, the full date and time the input gave;
  # without one, or where no time zone database resolves it, the map
  # carries the zone the name stands for.
  @spec zone_fields_for_map(String.t(), NaiveDateTime.t() | nil, Keyword.t()) :: map()
  def zone_fields_for_map(zone, naive_datetime, options) do
    case Localize.DateTime.Timezone.parse_zone(zone, options) do
      {:ok, {:offset, offset}} ->
        Localize.DateTime.Timezone.offset_zone_fields(offset)

      {:ok, {:zone, time_zone, _type}} ->
        named_zone_fields(zone, time_zone, naive_datetime, options)

      {:error, _not_a_zone} ->
        %{time_zone: zone}
    end
  end

  defp named_zone_fields(zone, time_zone, %NaiveDateTime{} = naive_datetime, options) do
    case Localize.DateTime.Timezone.resolve(zone, naive_datetime, options) do
      {:ok, datetime} -> datetime_zone_fields(datetime)
      {:error, _unresolved} -> %{time_zone: time_zone}
    end
  end

  defp named_zone_fields(_zone, time_zone, nil, _options), do: %{time_zone: time_zone}

  # The options each half of a date and time is read with: the half's
  # format, which `half_formats/2` has put under `:date_format` and
  # `:time_format`, as that parser's `:format`, or none.
  defp date_options(options), do: half_options(options, :date_format)
  defp time_options(options), do: half_options(options, :time_format)

  defp half_options(options, half) do
    format = Keyword.get(options, half)
    options = Keyword.drop(options, [:format, :date_format, :time_format, :glue])
    if is_nil(format), do: options, else: Keyword.put(options, :format, format)
  end

  # A format that is none is an error whatever the text, and is reported
  # for the first split that meets it rather than taken for text the half
  # does not read.
  @format_errors [
    Localize.DateTimeFormatError,
    Localize.DateTimeUnresolvedFormatError,
    Localize.DateTimeInvalidInputError
  ]

  defp half_error({:error, %error{}} = result) when error in @format_errors, do: result
  defp half_error(_unread), do: nil

  defp try_split_as_map({date_text, time_text}, options) do
    date_opts = options |> date_options() |> Keyword.put(:as, :map)
    time_opts = options |> time_options() |> Keyword.put(:as, :map)

    # Time half first — cheaper and more selective — so a failing time
    # half short-circuits the expensive date parse (see try_split_as_struct).
    with {:ok, %{} = time_map, zone} <-
           Localize.Time.Parser.parse_with_zone(time_text, time_opts),
         {:ok, %{} = date_map} <- Localize.Date.parse(date_text, date_opts) do
      # Date map carries `:calendar`; time map carries the time
      # fields plus the zone fields if any. Merge — date's
      # `:calendar` wins (the time map has no calendar key) — and
      # resolve a named zone against the full date when the input
      # gave one.
      merged = Map.merge(time_map, date_map)
      {:ok, put_zone_fields(merged, zone, options)}
    else
      unread -> half_error(unread)
    end
  end

  defp put_zone_fields(map, nil, _options), do: map

  defp put_zone_fields(map, zone, options),
    do: Map.merge(map, zone_fields_for_map(zone, complete_naive_datetime(map), options))

  # The full date and time a merged map gives, which a named zone's
  # offset needs; `nil` when the input left the date partial.
  defp complete_naive_datetime(
         %{year: year, month: month, day: day, hour: hour, calendar: calendar} = map
       ) do
    minute = Map.get(map, :minute, 0)
    second = Map.get(map, :second, 0)
    microsecond = Map.get(map, :microsecond, {0, 0})

    case NaiveDateTime.new(year, month, day, hour, minute, second, microsecond, calendar) do
      {:ok, naive_datetime} -> naive_datetime
      {:error, _reason} -> nil
    end
  end

  defp complete_naive_datetime(_partial_map), do: nil

  # All non-empty splits of `input` on `sep`, ordered to try
  # the latest-position split first (the "real" glue is usually
  # the last occurrence — date halves like `MMM d, y` consume
  # the earlier comma).
  defp enumerate_splits(input, sep) do
    case String.split(input, sep) do
      [_] ->
        []

      parts ->
        n = length(parts) - 1
        # For n split points, try them right-to-left.
        for i <- n..1//-1 do
          left = parts |> Enum.take(i) |> Enum.join(sep)
          right = parts |> Enum.drop(i) |> Enum.join(sep)
          {String.trim(left), String.trim(right)}
        end
        |> Enum.reject(fn {l, r} -> l == "" or r == "" end)
    end
  end

  # ── ISO 8601 ─────────────────────────────────────────────────

  @doc false
  # The ISO 8601 reading `parse/2` tries first, for a caller that takes ISO
  # 8601 alone: MessageFormat 2's date/time literals. An offset is kept with
  # the wall time it was written with, as `parse/2` keeps it.
  @spec from_iso8601(String.t()) :: {:ok, DateTime.t() | NaiveDateTime.t()} | :error
  def from_iso8601(input) when is_binary(input) do
    if String.valid?(input), do: try_iso(input), else: :error
  end

  defp try_iso(input) do
    # Shape `YYYY-MM-DD<sep>HH:MM:SS[…]` where <sep> is `T`
    # (RFC 3339 / ISO 8601) or a space (Elixir stdlib also
    # accepts; widely used by Postgres, SQLite, logs, etc.).
    if iso_datetime_shape?(input) do
      case DateTime.from_iso8601(input) do
        {:ok, datetime, offset} -> {:ok, restore_offset(datetime, offset)}
        _ -> try_iso_naive(input)
      end
    else
      :error
    end
  end

  # `DateTime.from_iso8601/1` normalises the instant to UTC and hands back
  # the offset it removed. Shifting by that offset restores the wall time
  # the input actually carried, which is then attached to the offset
  # rather than discarded — the same representation the locale-formatted
  # path produces, so one function no longer returns two different structs
  # for the same instant written two ways.
  defp restore_offset(datetime, 0), do: datetime

  defp restore_offset(datetime, offset) do
    datetime
    |> DateTime.add(offset, :second)
    |> Localize.DateTime.Timezone.offset_datetime(offset)
  end

  # `Date.from_iso8601/1` and `NaiveDateTime.from_iso8601/1`
  # only accept the *extended* format with hyphens and colons.
  # Cheap shape check to avoid handing arbitrary input to the
  # stdlib parser.
  defp iso_datetime_shape?(input) do
    Regex.match?(~r/\A\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}/u, input)
  end

  defp try_iso_naive(input) do
    case NaiveDateTime.from_iso8601(input) do
      {:ok, ndt} -> {:ok, ndt}
      _ -> :error
    end
  end

  # ── Locale glue split ───────────────────────────────────────

  # Universal fallback glues — accepted in every locale on top
  # of the CLDR-defined ones. Real-world inputs frequently use
  # these even where CLDR specifies a more elaborate separator:
  #
  #   * `" "` — bare space. Default for most locales (e.g. `ja`
  #     uses bare space) but `en` CLDR ships `, ` as the
  #     standard; accept bare space anyway so inputs like
  #     `"01/01/2018 14:44"` parse under `en`.
  #
  #   * `" - "` — common in admin UIs and exported reports.
  #
  #   * `" @ "` — common in human-written notes (`"23-05-2019 @ 10:01"`).
  #
  # Listed in descending byte-length so longer separators are
  # tried first; that prevents the bare-space fallback from
  # eating a hyphen-glued input before the `" - "` candidate
  # gets to try.
  @fallback_glue_separators [" - ", " @ ", " "]

  # A CLDR date-time glue pattern joins `{1}`, the date, and `{0}`, the
  # time, usually date first (`{1}, {0}`) but time first in some locales
  # (`vi`'s `{0} {1}`), and may put literal text around them (`vi`'s
  # `'lúc' {0} {1}`). Each glue pattern of the calendar the input is read
  # in, which the formatter joins with, and of the Gregorian calendar,
  # whose glue was the only one read before, gives a
  # `{prefix, separator, suffix, order}` entry; the caller backtracks
  # through every split point in the input to find one where both halves
  # parse.
  defp glue_separators(locale, cldr_calendar) do
    fallback = Enum.map(@fallback_glue_separators, &{"", &1, "", :date_first})

    [cldr_calendar, :gregorian]
    |> Enum.uniq()
    |> Enum.flat_map(&calendar_glue_separators(locale, &1))
    |> Kernel.++(fallback)
    |> Enum.uniq()
    |> Enum.sort_by(fn {_prefix, separator, _suffix, _order} -> -byte_size(separator) end)
  end

  defp calendar_glue_separators(locale, cldr_calendar) do
    cldr =
      case Format.date_time_formats(locale, cldr_calendar) do
        {:ok, glue_map} ->
          @standard_formats
          |> Enum.map(&Map.get(glue_map, &1))
          |> Enum.flat_map(&extract_separator/1)

        _ ->
          []
      end

    # CLDR 42+ carries a second set of glue patterns (atTime) whose
    # separators differ from the standard set — fr's full/long glue
    # is `{1} 'à' {0}` there, for example.
    at_time =
      case Format.date_time_at_formats(locale, cldr_calendar) do
        {:ok, %{standard: at_map}} when is_map(at_map) ->
          @standard_formats
          |> Enum.map(&Map.get(at_map, &1))
          |> Enum.flat_map(&extract_separator/1)

        _ ->
          []
      end

    cldr ++ at_time
  end

  # A pattern's literal text before, between and after its two halves,
  # and which half comes first, as a list for `flat_map` ergonomics.
  defp extract_separator(pattern) when is_binary(pattern) do
    case Regex.run(~r/^(.*?)\{([01])\}(.*?)\{([01])\}(.*)$/su, pattern) do
      [_, prefix, first, sep, second, suffix] when sep != "" and first != second ->
        order = if first == "1", do: :date_first, else: :time_first

        [
          {unquote_cldr_literal(prefix), unquote_cldr_literal(sep), unquote_cldr_literal(suffix),
           order}
        ]

      _ ->
        []
    end
  end

  defp extract_separator(_), do: []

  # CLDR quotes literal pattern text in single quotes (fr's glue is
  # `{1} 'à' {0}`) and escapes a real apostrophe as `''`. Without
  # unquoting, the separator ` 'à' ` never matches user input.
  defp unquote_cldr_literal(text) do
    text
    |> String.replace("''", <<0>>)
    |> String.replace(~r/'([^']*)'/u, "\\1")
    |> String.replace(<<0>>, "'")
  end

  # ── Errors ───────────────────────────────────────────────────

  defp no_match_error(input, locale) do
    DateTimeParseError.exception(input: input, locale: locale)
  end
end
