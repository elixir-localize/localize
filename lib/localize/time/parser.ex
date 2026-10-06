defmodule Localize.Time.Parser do
  @moduledoc false

  # Locale-aware parser for user-typed time strings.
  #
  # Public entry point: `Localize.Time.parse/2`. Mirrors the
  # structure of `Localize.Date.Parser` — try bare ISO-8601
  # first, then the locale's CLDR `:short` / `:medium` / `:long`
  # / `:full` time patterns.
  #
  # Implements the parts of [TR35 §Parsing Dates
  # Times](https://unicode.org/reports/tr35/tr35-dates.html#Parsing_Dates_Times)
  # and [§Parsing Day
  # Periods](https://unicode.org/reports/tr35/tr35-dates.html#Parsing_Day_Periods)
  # that matter for time-only input:
  #
  # * Numeric hour tokens `h` (1-12), `H` (0-23), `K` (0-11),
  # `k` (1-24) — relaxed to 1-2 digits regardless of pattern
  # count: TR35 has a pattern parsed leniently ("accept 9, 09").
  #
  # * Minute `m`/`mm` and second `s`/`ss` — relaxed similarly.
  #
  # * Fractional seconds `S` — variable-precision; we capture
  # 1-9 digits and store as microseconds.
  #
  # * Day-period tokens `a` (AM/PM) and `b` (AM/PM + noon /
  # midnight) — case-insensitive match against the locale's
  # `day_periods` data plus the universal ASCII forms
  # (`am`/`pm`/`a.m.`/`p.m.`/`AM`/`PM`).
  #
  # * Locale's CLDR `lenient-scope-date` data drives separator
  # equivalences for `:`, fractional separator, and surrounding
  # whitespace.
  #
  # Time-zone tokens (`z`, `Z`, `v`, `V`, `x`, `X`, `O`) read any
  # form of zone the locale writes, as
  # `Localize.DateTime.Timezone.parse_zone/2` recognises them. A
  # `Time` carries no zone; `Localize.DateTime.Parser` resolves
  # it for a date-time.
  #

  alias Localize.Calendar, as: LCalendar
  alias Localize.DateTime.Format
  alias Localize.TimeParseError

  # CLDR commonly uses NBSP / NNBSP / narrow-NBSP / ideographic
  # space between time fields and AM/PM markers. Accept any of
  # them where the pattern has a space.
  @space_class "[    　]*"

  @doc """
  Parses `input` as a locale-formatted time string.

  See `Localize.Time.parse/2` for the public contract.
  """
  @spec parse(String.t(), Keyword.t()) ::
          {:ok, Time.t() | map()} | {:error, Exception.t()}
  def parse(input, options \\ []) when is_binary(input) do
    case parse_with_zone(input, options) do
      {:ok, value, _zone} -> {:ok, value}
      {:error, _} = err -> err
    end
  end

  @doc """
  Same as `parse/2` but also returns the captured time-zone
  string (or `nil` when the input carried no zone), an ISO 8601
  time's offset or `Z` included. The
  `Localize.DateTime.Parser` resolves that zone with
  `Localize.DateTime.Timezone.resolve/3` when it builds a
  `DateTime`.

  In `as: :map` mode the first element is the field map (with
  `:time_zone` already embedded when a zone was captured); the
  zone is also returned as the third element for callers that
  need the raw string.
  """
  @spec parse_with_zone(String.t(), Keyword.t()) ::
          {:ok, Time.t() | map(), String.t() | nil} | {:error, Exception.t()}
  def parse_with_zone(input, options \\ []) when is_binary(input) do
    locale = Keyword.get(options, :locale) || Localize.get_locale()
    as = Keyword.get(options, :as, :struct)
    input = Localize.Date.Parser.normalise_input(input)

    with {:ok, calendar} <- Localize.Date.Parser.calendar_option(options) do
      case Keyword.get(options, :format) do
        nil ->
          read_in_any_format(input, locale, calendar, as, options)

        format ->
          input
          |> read_in_format(format, {locale, calendar}, as, options)
          |> put_map_zone_fields(options)
      end
    end
  end

  defp read_in_any_format(input, locale, calendar, as, options) do
    case try_iso(input) do
      {:ok, time, unwritten, zone} ->
        fields = time |> finalise_time(as) |> without_unwritten(unwritten, as)
        put_map_zone_fields({:ok, fields, zone}, options)

      :error ->
        input
        |> try_locale_patterns(locale, cldr_calendars(calendar), as)
        |> put_map_zone_fields(options)
    end
  end

  # The input in the format it was written with, which `:format` names as
  # it names the format `Localize.Time.to_string/2` writes with: a standard
  # format, a skeleton or a pattern. The text is read with that format and
  # no other, neither ISO 8601 nor another of the locale's formats, as
  # `Localize.Date.parse/2` reads a date with its format.
  defp read_in_format(input, format, {locale, calendar}, as, options) do
    with {:ok, patterns} <- format_patterns(format, locale, calendar, options),
         {:ok, day_periods} <- calendar_day_periods(locale, cldr_calendars(calendar)) do
      day_periods = Map.put(day_periods, :rules, day_period_rules(locale))
      lenient = load_lenient_date(locale)
      entries = Enum.map(patterns, &{:format, &1})
      regexes = Map.new(entries, &compile_pattern_entry(&1, day_periods, lenient))

      input
      |> Localize.Date.Parser.transliterate_digits(locale)
      |> match_patterns(entries, regexes, day_periods, as, locale)
      |> Kernel.||(
        {:error, TimeParseError.exception(input: input, locale: locale, format: format)}
      )
    end
  end

  # The patterns the formatter writes a time with for a format: the one it
  # writes a time with no zone with, which for a `:long` or a `:full` format
  # is the format's fields without its zone, and the one it writes a time in
  # a zone with. A format the formatter cannot write a time with is an
  # error, as it is to `Localize.Time.to_string/2`: a quote left open, a
  # letter that is no field, a field of a date, or a field longer than any
  # format writes, which is written as U+FFFD.
  #
  # A semantic skeleton of optional minutes writes a time on the hour
  # without them, "2 PM" beside "2:30 PM", so the patterns are those of a
  # time with minutes and of one on the hour; for any other format the two
  # are one pattern.
  defp format_patterns(format, locale, calendar, options) do
    time = %{calendar: calendar, hour: 10, minute: 30, second: 45, microsecond: {0, 6}}
    on_the_hour = %{time | minute: 0, second: 0}
    zone = %{time_zone: "Etc/UTC", zone_abbr: "UTC", utc_offset: 0, std_offset: 0}
    times = [time, Map.merge(time, zone), on_the_hour, Map.merge(on_the_hour, zone)]

    time_options =
      options |> Keyword.take([:prefer]) |> Keyword.merge(format: format, locale: locale)

    with {:ok, written} <- Localize.Time.to_string(time, time_options),
         false <- String.contains?(written, "�"),
         {:ok, patterns} <- resolved_patterns(times, format, locale, options) do
      {:ok, Enum.uniq(patterns)}
    else
      true ->
        {:error, Localize.DateTimeFormatError.exception(format: format, reason: :invalid_format)}

      {:error, _exception} = error ->
        error
    end
  end

  defp resolved_patterns(times, format, locale, options) do
    Enum.reduce_while(times, {:ok, []}, fn time, {:ok, patterns} ->
      case Localize.Time.resolve_pattern(time, format, locale, options) do
        {:ok, pattern} -> {:cont, {:ok, patterns ++ [pattern]}}
        {:error, _exception} = error -> {:halt, error}
      end
    end)
  end

  # A time is read in the time formats of the calendar it is written for,
  # which the formatter writes it with (`de`'s Chinese `Bh` "10 vorm."), and
  # then in the Gregorian calendar's ("10 Uhr vorm.").
  defp cldr_calendars(calendar),
    do: Enum.uniq([Localize.Calendar.cldr_calendar_type(calendar), :gregorian])

  # A zone captured in the map form carries the fields it resolves to
  # without a date — a fixed offset's `DateTime` zone fields, or else the
  # zone it names (see `Localize.DateTime.Parser.zone_fields_for_map/3`).
  defp put_map_zone_fields({:ok, %{} = map, zone}, options)
       when is_binary(zone) and not is_struct(map) do
    zone_fields = Localize.DateTime.Parser.zone_fields_for_map(zone, nil, options)
    {:ok, Map.merge(map, zone_fields), zone}
  end

  defp put_map_zone_fields(result, _options), do: result

  # An ISO 8601 time as a map has its hour, minute and second, less the
  # ones the text left out (`without_unwritten/3`). Microsecond is
  # included only when the input actually supplied fractional
  # precision — `{n, 0}` means "no fraction specified" and is omitted.
  defp finalise_time(%Time{} = time, :struct), do: time

  defp finalise_time(%Time{hour: h, minute: m, second: s, microsecond: us}, :map) do
    base = %{hour: h, minute: m, second: s}

    case us do
      {_, 0} -> base
      other -> Map.put(base, :microsecond, other)
    end
  end

  # A map holds the fields the text gave, so not the seconds or the minutes
  # an ISO 8601 time left out ("T10:30"), as the locale's "10:30" has none.
  defp without_unwritten(map, unwritten, :map), do: Map.drop(map, unwritten)
  defp without_unwritten(time, _unwritten, :struct), do: time

  # ── ISO 8601 ─────────────────────────────────────────────────

  # An ISO 8601 time, the fields of it the text left out and its offset:
  # the form Elixir reads, a time between colons with its seconds, and
  # then the others ISO 8601 writes.
  defp try_iso(input) do
    case Time.from_iso8601(input) do
      {:ok, time} -> {:ok, time, [], iso_offset(input)}
      _ -> other_iso(input)
    end
  end

  # ISO 8601 writes a time after its time designator, `T`, with its seconds,
  # or its minutes and seconds, left out, and with its separators or
  # without them: "T10:30", "T1030", "T10", "T103045". The designator may
  # be left off a time between colons, so "10:30" is ISO 8601's in every
  # locale, where a locale that writes "10.30" has no format that reads it.
  # Digits alone are no time without it: "1030" is as much a year, and
  # "10" is the locale's to read. The time is filled out to the form Elixir
  # reads, which judges it as it judges a time written in full.
  defp other_iso(input) do
    {designated?, text} = without_designator(input)

    with {:ok, extended, unwritten} <- extended_iso8601(text),
         true <- designated? or Regex.match?(~r/\A[0-9]{2}:/, text),
         {:ok, time} <- Time.from_iso8601(extended) do
      {:ok, time, unwritten, iso_offset(extended)}
    else
      _no_time -> :error
    end
  end

  defp without_designator(<<designator, text::binary>>) when designator in ~c"Tt",
    do: {true, text}

  defp without_designator(text), do: {false, text}

  # The offset, or `Z`, that ISO 8601 writes hard against a time.
  # `Time.from_iso8601/1` reads a time that carries one and discards it, so
  # it is taken from the text: a date and time read through the locale's
  # patterns ("11/22/2023 14:30:45+02:00") keeps the offset its time was
  # written with, where it was dropped and the value came back naive.
  defp iso_offset(input) do
    case Regex.run(~r/(?:Z|[+\-−]\d{2}(?::?\d{2})?)\z/u, input) do
      [offset] -> offset
      nil -> nil
    end
  end

  @iso_time ~r/\A(?<hour>[0-9]{2})(?:(?<separator>:?)(?<minute>[0-9]{2})(?:\k<separator>(?<second>[0-9]{2})(?<fraction>[.,][0-9]+)?)?)?(?<offset>[Zz]|[+\-−][0-9]{2}(?::?[0-9]{2})?)?\z/u

  @doc false
  # A time as ISO 8601 writes one after a date's `T`, in the one form Elixir
  # reads, its hours, minutes and seconds between colons. ISO 8601 also
  # writes them with nothing between them ("103045") and leaves out the
  # seconds, or the minutes and the seconds ("10:30", "1030", "10"); those
  # are filled in here and named in the result, so a caller knows which
  # fields the text held. `Z` may be `z` (RFC 3339) and an offset's minus
  # sign U+2212, as ISO 8601 writes it, or a hyphen.
  #
  # A time's separators are all there or all absent ("10:3045" is no time),
  # and a fraction is the second's alone: a fraction of a minute or of an
  # hour ("10:30,5") is not read. Whether the result is a time at all is
  # Elixir's to judge, as it judges a time written in full: an hour of 24, a
  # second of 60 and an offset of "-00:00" are none.
  @spec extended_iso8601(String.t()) :: {:ok, String.t(), [:minute | :second]} | :error
  def extended_iso8601(input) when is_binary(input) do
    case Regex.named_captures(@iso_time, input) do
      %{"hour" => hour, "minute" => minute, "second" => second, "fraction" => fraction} = fields ->
        time = Enum.map_join([hour, minute, second], ":", &written_or_zero/1)
        offset = fields |> Map.get("offset", "") |> extended_offset()

        {:ok, time <> fraction <> offset, unwritten(minute, second)}

      nil ->
        :error
    end
  end

  defp written_or_zero(""), do: "00"
  defp written_or_zero(digits), do: digits

  defp unwritten("", _second), do: [:minute, :second]
  defp unwritten(_minute, ""), do: [:second]
  defp unwritten(_minute, _second), do: []

  defp extended_offset("z"), do: "Z"
  defp extended_offset("−" <> digits), do: "-" <> digits
  defp extended_offset(offset), do: offset

  # ── Locale patterns (stubbed; filled out by subsequent edits)─

  # The first pattern to read the input wins, so they are taken in a fixed
  # order (see `pattern_specificity/2`) rather than the order of the map
  # the available formats come from. So `ms` "11:59 PTG" is its short
  # "h:mm a", 23:59, not "HH:mm v" in a zone "PTG", and "11:59:59 PM" is
  # not read by a `B` pattern whose locale names no flexible day periods.
  defp try_locale_patterns(input, locale, cldr_calendars, as) do
    with {:ok, available} <- available_formats(locale, cldr_calendars),
         {:ok, day_periods} <- calendar_day_periods(locale, cldr_calendars) do
      standard =
        cldr_calendars
        |> Enum.flat_map(&Format.standard_format_entries(locale, &1))
        |> collect_patterns()

      standard_patterns = MapSet.new(standard, fn {_skeleton, pattern} -> pattern end)

      patterns =
        standard
        |> Enum.concat(collect_patterns(available))
        |> Enum.uniq_by(fn {_skeleton, pattern} -> pattern end)
        |> Enum.sort_by(fn {_skeleton, pattern} ->
          pattern_specificity(pattern, standard_patterns)
        end)
        |> with_hour_cycle(locale)

      day_periods = Map.put(day_periods, :rules, day_period_rules(locale))
      lenient = load_lenient_date(locale)
      regexes = pattern_regexes(patterns, locale, cldr_calendars, day_periods, lenient)

      # A time is written in the digits of the locale's number system, as
      # `bn`'s "১০:০৫ AM" and `fa`'s "۱۰:۰۵" are, and read as the date
      # parser reads them.
      input
      |> Localize.Date.Parser.transliterate_digits(locale)
      |> match_patterns(patterns, regexes, day_periods, as, locale)
      |> Kernel.||({:error, no_match_error(input, locale)})
    end
  end

  # The available formats of each calendar, the calendar asked for first. A
  # calendar the locale has no formats for adds none; the Gregorian
  # calendar's are the locale's.
  defp available_formats(locale, cldr_calendars) do
    with {:ok, gregorian} <- Format.available_formats(locale, :gregorian) do
      own =
        for cldr_calendar <- cldr_calendars,
            cldr_calendar != :gregorian,
            {:ok, available} <- [Format.available_formats(locale, cldr_calendar)],
            entry <- available,
            do: entry

      {:ok, own ++ Enum.to_list(gregorian)}
    end
  end

  # The day periods of the calendar asked for, or the Gregorian calendar's.
  defp calendar_day_periods(locale, [cldr_calendar | _gregorian]) do
    case LCalendar.day_periods(locale, cldr_calendar) do
      {:ok, day_periods} -> {:ok, day_periods}
      {:error, _no_day_periods} -> LCalendar.day_periods(locale, :gregorian)
    end
  end

  # Under a `-u-hc-` hour cycle, times format with the cycle's hour symbol
  # ("24:30" for h24, "午前12:30" for ja h12), so those forms of the
  # locale's patterns are tried first.
  defp with_hour_cycle(patterns, locale) do
    case Localize.validate_locale(locale) do
      {:ok, %Localize.LanguageTag{locale: %{hc: hour_cycle}} = language_tag}
      when not is_nil(hour_cycle) ->
        converted =
          for {skeleton, pattern} <- patterns,
              hour_cycle_pattern = Localize.Time.apply_hour_cycle(pattern, language_tag),
              hour_cycle_pattern != pattern,
              do: {skeleton, hour_cycle_pattern}

        converted ++ patterns

      _no_hour_cycle ->
        patterns
    end
  end

  # A pattern with a zone reads free text into it, so every pattern without
  # one comes first. Among each, the locale's standard formats, which the
  # formatter writes, come before its available formats; a flexible day
  # period, which reads any words where its locale names none, after a
  # pattern without one; then the longest first, and the text keeps the
  # order fixed.
  defp pattern_specificity(pattern, standard_patterns) do
    fields = String.replace(pattern, ~r/'[^']*'/u, "")

    {rank(String.match?(fields, ~r/[zZvVxXO]/)),
     rank(not MapSet.member?(standard_patterns, pattern)), rank(String.contains?(fields, "B")),
     -String.length(pattern), pattern}
  end

  defp rank(true), do: 1
  defp rank(false), do: 0

  # The dayPeriodRules a flexible day period's 12-hour hour is resolved
  # against, keyed by the locale's language as the formatter keys them.
  defp day_period_rules(locale) do
    case Localize.Locale.cldr_locale_id_from(locale) do
      {:ok, locale_id} ->
        language = locale_id |> Kernel.to_string() |> String.split("-") |> hd()
        Map.get(Localize.SupplementalData.day_periods().format, language)

      {:error, _reason} ->
        nil
    end
  end

  # The first pattern that matches the input, or nil when none does.
  defp match_patterns(input, patterns, regexes, day_periods, as, locale) do
    Enum.find_value(patterns, fn {_kind, pattern} ->
      {regex, tokens} = Map.get(regexes, pattern, {nil, nil})

      case match_pattern(input, regex, tokens, day_periods, as, locale) do
        {:ok, value, zone} -> {:ok, value, zone}
        :error -> nil
      end
    end)
  end

  # %{pattern => {compiled_regex_or_nil, tokens}} cached in :persistent_term
  # keyed by locale and the calendars whose patterns are read. The regex and
  # tokens are pure functions of the patterns, the day-period names and the
  # lenient rules, so each set is built once.
  defp pattern_regexes(patterns, locale, cldr_calendars, day_periods, lenient) do
    key = {__MODULE__, :pattern_regexes, locale, cldr_calendars}

    case :persistent_term.get(key, nil) do
      nil ->
        compiled = Map.new(patterns, &compile_pattern_entry(&1, day_periods, lenient))
        Localize.LiteralMemory.cache(key, compiled)
        compiled

      compiled ->
        compiled
    end
  end

  defp compile_pattern_entry({_kind, pattern}, day_periods, lenient) do
    tokens = tokenize_pattern(pattern)
    regex_string = compile_regex(tokens, day_periods, lenient)

    regex =
      case Regex.compile(regex_string, "u") do
        {:ok, regex} -> regex
        {:error, _reason} -> nil
      end

    {pattern, {regex, tokens}}
  end

  # Iterate every parseable CLDR pattern in `availableFormats`.
  # CLDR's `timeStyle` standards (`:short`/`:medium`/`:long`/
  # `:full`) are just references INTO `availableFormats` —
  # `:short` for en is `:ahmm`, and `:ahmm` is itself a key
  # in `availableFormats`. So iterating `availableFormats`
  # covers the standard four AND the broader skeleton set
  # in one pass.
  #
  # Skeletons that lack hour/minute fields don't construct a
  # Time and fall through naturally.
  # A standard format's pattern is often also an `availableFormats` entry,
  # so the same pair can arrive twice.
  defp collect_patterns(available) do
    for {skeleton, pattern_data} <- available,
        pattern <- resolve_pattern_variants(pattern_data),
        uniq: true,
        do: {skeleton, pattern}
  end

  defp resolve_pattern_variants(nil), do: []
  defp resolve_pattern_variants(pattern) when is_binary(pattern), do: [pattern]

  defp resolve_pattern_variants(%{variant: variant, standard: standard})
       when is_binary(variant) and is_binary(standard),
       do: [variant, standard]

  defp resolve_pattern_variants(%{unicode: u, ascii: a}) when is_binary(u) and is_binary(a),
    do: [u, a]

  defp resolve_pattern_variants(%{format: pattern}) when is_binary(pattern), do: [pattern]

  # Plural-variant maps (`%{one: ..., other: ...}`) — accept
  # every binary variant.
  defp resolve_pattern_variants(%{} = map) do
    map
    |> Map.values()
    |> Enum.filter(&is_binary/1)
    |> Enum.uniq()
  end

  defp resolve_pattern_variants(_), do: []

  defp load_lenient_date(locale) do
    case Localize.Locale.get(locale, [:lenient_parse, :date]) do
      {:ok, data} when is_map(data) -> build_equivalence_map(data)
      _ -> %{}
    end
  end

  defp build_equivalence_map(data) do
    Enum.reduce(data, %{}, fn {_key, set_string}, acc ->
      case parse_cldr_set(set_string) do
        [] -> acc
        chars -> Enum.reduce(chars, acc, &Map.put(&2, &1, chars))
      end
    end)
  end

  defp parse_cldr_set(set) when is_binary(set) do
    case Regex.run(~r/^\[(.*)\]$/u, set) do
      [_, inner] ->
        inner
        |> String.replace("\\-", "-")
        |> String.graphemes()
        |> Enum.reject(&(&1 == " "))
        |> Enum.uniq()

      _ ->
        []
    end
  end

  defp parse_cldr_set(_), do: []

  defp no_match_error(input, locale) do
    TimeParseError.exception(input: input, locale: locale)
  end

  # ── Pattern → regex ──────────────────────────────────────────

  defp match_pattern(input, regex, tokens, day_periods, as, locale) do
    with %Regex{} <- regex,
         %{} = caps <- Regex.named_captures(regex, input),
         {:ok, hour} <- extract_hour(caps, tokens, day_periods),
         {:ok, zone} <- zone_capture(caps, locale) do
      build_match(as, caps, hour, zone)
    else
      _ -> :error
    end
  end

  # A zone field reads any text, so the pattern matches only where that
  # text is a zone the locale writes, in any of TR35's forms. A number
  # after the GMT literal needs its sign here, since the text around the
  # field has numbers of its own (`parse_zone_field/2`).
  defp zone_capture(caps, locale) do
    case extract_zone(caps) do
      nil ->
        {:ok, nil}

      zone ->
        case Localize.DateTime.Timezone.parse_zone_field(zone, locale: locale) do
          {:ok, _parsed_zone} -> {:ok, zone}
          {:error, _not_a_zone} -> :error
        end
    end
  end

  # The map carries only the fields the input gave, and they must still
  # make a time: a minute or second no time has (61) does not match.
  defp build_match(:map, caps, hour, zone) do
    map = build_time_map(caps, hour, zone)
    minute = Map.get(map, :minute, 0)
    second = Map.get(map, :second, 0)
    microsecond = Map.get(map, :microsecond, {0, 0})

    case Time.new(hour, minute, second, microsecond) do
      {:ok, _time} -> {:ok, map, zone}
      {:error, _reason} -> :error
    end
  end

  defp build_match(:struct, caps, hour, zone) do
    with {:ok, minute} <- extract_field(caps, "minute", 0),
         {:ok, second} <- extract_field(caps, "second", 0),
         {:ok, microsecond} <- extract_microsecond(caps),
         {:ok, time} <- Time.new(hour, minute, second, microsecond) do
      {:ok, time, zone}
    else
      _ -> :error
    end
  end

  defp extract_zone(caps) do
    case Map.get(caps, "zone") do
      z when is_binary(z) and z != "" -> z
      _ -> nil
    end
  end

  # Build a map containing only the fields the input actually
  # supplied. Hour is mandatory (no time pattern lacks it);
  # minute, second, microsecond, and time_zone are added only
  # if captured.
  defp build_time_map(caps, hour, zone) do
    %{hour: hour}
    |> maybe_put_int(caps, "minute", :minute)
    |> maybe_put_int(caps, "second", :second)
    |> maybe_put_microsecond(caps)
    |> maybe_put_zone(zone)
  end

  defp maybe_put_int(map, caps, key, dest_key) do
    case caps[key] do
      raw when is_binary(raw) and raw != "" ->
        case Integer.parse(raw) do
          {n, ""} -> Map.put(map, dest_key, n)
          _ -> map
        end

      _ ->
        map
    end
  end

  defp maybe_put_microsecond(map, caps) do
    case extract_microsecond(caps) do
      {:ok, {_, 0}} -> map
      {:ok, microsecond} -> Map.put(map, :microsecond, microsecond)
      _ -> map
    end
  end

  defp maybe_put_zone(map, nil), do: map
  defp maybe_put_zone(map, zone), do: Map.put(map, :time_zone, zone)

  # Walk a CLDR pattern string and emit alternating literal /
  # field tokens. Fields are runs of identical CLDR letters
  # (h H K k m s S a b B z Z v V x X O).
  # A pattern is read by code points, as `Localize.Date.Parser` reads one:
  # a combining mark beside a quote or a pattern letter is literal text.
  defp tokenize_pattern(pattern) do
    pattern
    |> String.codepoints()
    |> tokenize([], nil)
    |> Enum.reverse()
  end

  defp tokenize([], acc, nil), do: acc
  defp tokenize([], acc, current), do: [field_token(current) | acc]

  # TR35: "Two adjacent single vertical quotes (''), which represent a
  # literal single quote, either inside or outside quoted text". mt.xml's
  # week of the year is "w 'ġimgħa' 'ta''' Y", whose "ta'" was read as "ta"
  # and its text, "25 ġimgħa ta' 2026", as nothing.
  defp tokenize(["'", "'" | rest], acc, current) do
    acc = if current, do: [field_token(current) | acc], else: acc
    tokenize(rest, prepend_literal(acc, "'"), nil)
  end

  defp tokenize(["'" | rest], acc, current) do
    {literal, rest} = take_quoted(rest, [])
    acc = if current, do: [field_token(current) | acc], else: acc
    tokenize(rest, [{:lit, literal} | acc], nil)
  end

  defp tokenize([char | rest], acc, current) do
    if cldr_letter?(char) do
      case current do
        {^char, count} -> tokenize(rest, acc, {char, count + 1})
        nil -> tokenize(rest, acc, {char, 1})
        other -> tokenize(rest, [field_token(other) | acc], {char, 1})
      end
    else
      acc = if current, do: [field_token(current) | acc], else: acc
      tokenize(rest, prepend_literal(acc, char), nil)
    end
  end

  defp take_quoted(["'", "'" | rest], acc), do: take_quoted(rest, ["'" | acc])
  defp take_quoted(["'" | rest], acc), do: {acc |> Enum.reverse() |> Enum.join(), rest}
  defp take_quoted([char | rest], acc), do: take_quoted(rest, [char | acc])
  defp take_quoted([], acc), do: {acc |> Enum.reverse() |> Enum.join(), []}

  defp prepend_literal([{:lit, prev} | rest], char), do: [{:lit, prev <> char} | rest]
  defp prepend_literal(acc, char), do: [{:lit, char} | acc]

  defp field_token({char, count}), do: {String.to_atom(char), count}

  defp cldr_letter?(char) when char in ~w(h H K k m s S a b B z Z v V x X O), do: true
  defp cldr_letter?(_), do: false

  defp compile_regex(tokens, day_periods, lenient) do
    parts =
      tokens
      |> Enum.map(fn token -> field_regex(token, day_periods, lenient) end)

    "\\A" <> Enum.join(parts) <> "\\z"
  end

  # Numeric hour fields — relaxed to 1-2 digits regardless of
  # `h` vs `hh`, as TR35's lenient parse of a pattern accepts "9, 09".
  defp field_regex({letter, _count}, _dp, _lenient) when letter in [:h, :H, :K, :k] do
    "(?P<hour_#{letter}>\\d{1,2})"
  end

  defp field_regex({:m, _count}, _dp, _lenient), do: "(?P<minute>\\d{1,2})"
  defp field_regex({:s, _count}, _dp, _lenient), do: "(?P<second>\\d{1,2})"

  # Fractional second — variable precision 1-9 digits.
  defp field_regex({:S, count}, _dp, _lenient) do
    max = max(count, 9)
    "(?P<microsecond>\\d{1,#{max}})"
  end

  # Day period (a) — match locale's wide / abbreviated / narrow
  # AM/PM names plus universal ASCII forms. `b` adds noon /
  # midnight markers (CLDR ≥ 41).
  defp field_regex({letter, _count}, day_periods, _lenient) when letter in [:a, :b] do
    day_period_regex(day_periods, letter)
  end

  # Flexible day period (B) — `morning1`, `afternoon1`,
  # `evening1`, `night1`, plus the absolute markers
  # `noon` and `midnight` (TR35 §Parsing Day Periods).
  # Capture the matched period so `resolve_hour` can use
  # it to disambiguate AM/PM for 12-hour cycles when no
  # explicit `a` marker was supplied.
  defp field_regex({:B, _count}, day_periods, _lenient),
    do: flex_period_regex(day_periods)

  # Time zones (TR35 §Time Zone Parsing). A zone is written in
  # a locale's own words and spelling — "heure d’été de l’Est
  # nord-américain", "UTC−4", "غرينتش-4", "heure : New York" —
  # so the field captures the text the rest of the pattern
  # leaves, and `zone_capture/2` keeps the match only where
  # that text is a zone the locale writes, in any of TR35's
  # forms, whichever the pattern's letter asks for.
  defp field_regex({letter, _count}, _dp, _lenient) when letter in [:z, :Z, :v, :V, :x, :X, :O] do
    "(?P<zone>.+?)"
  end

  # Literal text — expand each char via lenient equivalence.
  defp field_regex({:lit, text}, _dp, lenient) do
    text
    |> String.graphemes()
    |> Enum.map_join(&expand_char(&1, lenient))
  end

  defp expand_char(char, lenient) do
    if space_char?(char) do
      @space_class
    else
      case Map.get(lenient, char) do
        nil -> Regex.escape(char)
        [_ | _] = chars -> "[" <> Enum.map_join(chars, &Regex.escape/1) <> "]"
      end
    end
  end

  defp space_char?(" "), do: true
  defp space_char?(" "), do: true
  defp space_char?(" "), do: true
  defp space_char?(" "), do: true
  defp space_char?("　"), do: true
  defp space_char?(_), do: false

  # ── Day-period regex (a / b) ────────────────────────────────

  # AM/PM names per locale plus a baseline of universal ASCII
  # forms (`AM`, `PM`, `a.m.`, `p.m.`, mixed case). Captured
  # in a single named group, value resolved against the
  # locale's day_period map at extract time.
  defp day_period_regex(day_periods, letter) do
    names =
      collect_period_names(day_periods, letter) ++
        ~w(AM PM am pm A.M. P.M. a.m. p.m.)

    alternation =
      names
      |> Enum.uniq()
      |> Enum.sort_by(&(-byte_size(&1)))
      |> Enum.map_join("|", &escape_with_flexible_spaces/1)

    # `(?i:...)` per CLDR TR35 §6.5 — day-period name matching
    # is case-insensitive so "am" matches "AM", "Du matin"
    # matches "du matin", etc.
    #
    # Trailing `(?![\p{L}])` prevents narrow forms (en's "a"/"p")
    # from consuming the first letter of an adjacent capture —
    # without it, `"11:30 PST"` against `h:mm a v` matches
    # day_period="P" and zone="ST" instead of zone="PST". The
    # assertion requires the match to be followed by a non-letter
    # (or end of input).
    "(?P<day_period>(?i:#{alternation}))(?![\\p{L}])"
  end

  # CLDR ships some day-period names with NBSP or narrow NBSP
  # (es "a.\u202Fm."), but users type ASCII spaces. Escape each
  # non-space segment and accept any space flavour between them.
  defp escape_with_flexible_spaces(name) do
    name
    |> String.split(~r/[\s\x{00A0}\x{202F}]+/u)
    |> Enum.map_join("[\\s\\x{00A0}\\x{202F}]", &Regex.escape/1)
  end

  defp collect_period_names(day_periods, letter) do
    widths =
      case letter do
        :a -> [:wide, :abbreviated, :narrow]
        :b -> [:wide, :abbreviated, :narrow]
      end

    keys =
      case letter do
        :a -> [:am, :pm]
        :b -> [:am, :pm, :noon, :midnight]
      end

    contexts = [:format, :stand_alone]

    for context <- contexts,
        width <- widths,
        {period, entry} <- get_in(day_periods, [context, width]) || %{},
        period in keys,
        name <- entry_to_names(entry),
        do: name
  end

  # Day-period entries are either bare strings (`"noon"`)
  # or `%{default: ..., variant: ...}` maps (`am`/`pm`).
  # Expand both into a flat list of binaries.
  defp entry_to_names(name) when is_binary(name), do: [name]

  defp entry_to_names(%{} = map),
    do: Enum.filter(Map.values(map), &is_binary/1)

  defp entry_to_names(_), do: []

  # ── Flex day period regex (B) ────────────────────────────────

  @flex_period_keys [
    :morning1,
    :morning2,
    :afternoon1,
    :afternoon2,
    :evening1,
    :evening2,
    :night1,
    :night2,
    :noon,
    :midnight
  ]

  # A name can name more than one period — `fr`'s "matin" is morning1 and
  # night1 — so it is captured whole, longest first, and resolved against
  # each period it names (see `flex_periods/2`). The formatter writes a
  # period the locale gives no name, and every period in a locale without
  # day-period rules, as AM or PM, so those names are read as `a` reads
  # them. Case-insensitive per CLDR TR35 §6.5.
  defp flex_period_regex(day_periods) do
    am_pm = day_period_regex(day_periods, :a)

    case day_periods |> collect_flex_period_pairs() |> Enum.map(&elem(&1, 1)) |> Enum.uniq() do
      [] ->
        am_pm

      names ->
        alternation =
          names
          |> Enum.sort_by(&(-byte_size(&1)))
          |> Enum.map_join("|", &escape_with_flexible_spaces/1)

        "(?:(?P<flex_period>(?i:#{alternation}))(?![\\p{L}])|#{am_pm})"
    end
  end

  defp collect_flex_period_pairs(day_periods) do
    widths = [:wide, :abbreviated, :narrow]
    contexts = [:format, :stand_alone]

    for context <- contexts,
        width <- widths,
        {key, entry} <- get_in(day_periods, [context, width]) || %{},
        key in @flex_period_keys,
        name <- entry_to_names(entry),
        do: {key, name}
  end

  # ── Field extraction ────────────────────────────────────────

  defp extract_hour(caps, tokens, day_periods) do
    # Find which hour-letter actually fired. We named each as
    # `hour_h` / `hour_H` / `hour_K` / `hour_k` so we can
    # discriminate.
    hour_field =
      Enum.find(["hour_h", "hour_H", "hour_K", "hour_k"], fn key ->
        Map.get(caps, key, "") != ""
      end)

    with raw when is_binary(raw) and raw != "" <- caps[hour_field],
         {n, ""} <- Integer.parse(raw) do
      letter = hour_field |> String.replace_prefix("hour_", "") |> String.to_atom()
      resolve_hour(n, letter, caps, tokens, day_periods)
    else
      _ -> :error
    end
  end

  # Resolve 12-hour vs 24-hour and AM/PM. CLDR conventions:
  #   h: 1-12, paired with a/b for AM/PM disambiguation
  #   H: 0-23, no AM/PM
  #   K: 0-11, paired with a/b
  #   k: 1-24 (k=24 == midnight start of day)
  #
  # A number beyond a field's hours is no hour of that field. TR35 gives
  # each field its hours, `h` "Hour [1-12]", `H` "[0-23]", `K` "[0-11]" and
  # `k` "[1-24]", and its parsing notes have it that "a number larger than
  # the largest month cannot be a month". So "13:30 AM" is no time, "45:30"
  # is none where a locale's only pattern for it is "h:mm", and neither are
  # `h`'s 0 and `K`'s 12: `ja` writes half past noon "午後0:30", and "午前
  # 12:30" is no time of its "aK:mm". Those two were read, 0 as `h`'s 12
  # and 12 as twelve hours on from `K`'s 0, which is ICU's reading when it
  # is lenient and not TR35's.
  defp resolve_hour(n, :H, caps, _tokens, day_periods) when n in 0..23,
    do: consistent_hour(n, caps, day_periods)

  defp resolve_hour(24, :k, caps, _tokens, day_periods),
    do: consistent_hour(0, caps, day_periods)

  defp resolve_hour(n, :k, caps, _tokens, day_periods) when n in 1..23,
    do: consistent_hour(n, caps, day_periods)

  defp resolve_hour(n, letter, caps, _tokens, day_periods)
       when (letter == :h and n in 1..12) or (letter == :K and n in 0..11) do
    base = if letter == :h, do: rem(n, 12), else: n

    period = caps |> Map.get("day_period", "") |> String.downcase()
    flexes = flex_periods(caps, day_periods)

    case day_period_half(period, flexes, day_periods) do
      :pm -> {:ok, base + 12}
      :am -> {:ok, base}
      :flex -> resolve_flex_period_hour(base, flexes, day_periods)
    end
  end

  defp resolve_hour(_, _, _, _, _), do: :error

  # A 24-hour hour beside a day period. TR35 says a 24-hour pattern "should
  # not include fields with day period characters", but CLDR 49's `Hmsv` for
  # `ksh` is "H:mm:ss a v", and TR35's parsing of day periods has "the
  # dayperiod … checked for consistency with the hour". An hour its day
  # period does not hold is no reading of the pattern: "4:00:00 n.M.", four
  # in the afternoon, was 04:00 to that one, and is left to a 12-hour
  # pattern. A pattern with no day period, or text with none, has nothing to
  # check.
  defp consistent_hour(hour, caps, day_periods) do
    period = caps |> Map.get("day_period", "") |> String.downcase()
    flexes = flex_periods(caps, day_periods)

    cond do
      period == "" and flexes == [] ->
        {:ok, hour}

      hour_in_half?(hour, day_period_half(period, flexes, day_periods), flexes, day_periods) ->
        {:ok, hour}

      true ->
        :error
    end
  end

  defp hour_in_half?(hour, :am, _flexes, _day_periods), do: hour < 12
  defp hour_in_half?(hour, :pm, _flexes, _day_periods), do: hour >= 12

  # A flexible day period holds the hour where one of its rules does, and
  # any hour where the locale has no rule for it.
  defp hour_in_half?(hour, :flex, flexes, day_periods) do
    rules = for flex <- flexes, rule = get_in(day_periods, [:rules, flex]), do: rule
    rules == [] or Enum.any?(rules, &hour_in_period?(hour, &1))
  end

  # Which half of the day a captured day-period name puts the hour in, or
  # `:flex` when only a flexible day period (B) can decide.
  defp day_period_half(period, flexes, day_periods) do
    locale_kind = locale_period_kind(period, day_periods)

    cond do
      period in ["pm", "p.m."] ->
        :pm

      # Locale day-period names that carry no ASCII am/pm signal
      # (ja 午前/午後, el π.μ./μ.μ., narrow "a"/"p") resolve
      # against the locale's own am/pm name sets.
      locale_kind in [:am, :pm] ->
        locale_kind

      period in ["am", "a.m.", ""] and flexes == [] ->
        :am

      # Locale-specific day-period name — look up via heuristic.
      String.contains?(period, "pm") or String.contains?(period, "p.m") ->
        :pm

      true ->
        :flex
    end
  end

  # No explicit AM/PM marker but a flex period (B) was captured. TR35
  # §Parsing Day Periods checks the day period for consistency with the
  # hour, so the hour is whichever of its two 12-hour readings falls within
  # the dayPeriodRule of a period the name names: ja "夜中0:30" (night2,
  # 23:00–04:00) is 00:30, en "1 at night" (night1, 21:00–06:00) is 01:00,
  # and fr "9:05 matin" (morning1, 04:00–12:00, not night1, 00:00–04:00) is
  # 09:05. Where both readings or neither fall within one, the first
  # period's name decides.
  defp resolve_flex_period_hour(base, flexes, day_periods) do
    readings =
      for flex <- flexes,
          hour <- [base, base + 12],
          hour_in_period?(hour, get_in(day_periods, [:rules, flex])),
          uniq: true,
          do: hour

    case readings do
      [hour] -> {:ok, hour}
      _both_or_neither -> named_period_hour(base, List.first(flexes))
    end
  end

  defp hour_in_period?(hour, %{from: from, before: before}) when from < before do
    hour * 60 >= from and hour * 60 < before
  end

  defp hour_in_period?(hour, %{from: from, before: before}) do
    hour * 60 >= from or hour * 60 < before
  end

  # Noon and midnight name an instant, so the hour is theirs: `gl`'s
  # "12 da noite" names midnight as well as night1, and is 00:00.
  defp hour_in_period?(hour, %{at: at}), do: hour * 60 == at

  defp hour_in_period?(_hour, _rule), do: false

  defp named_period_hour(base, flex) do
    cond do
      flex in [:morning1, :morning2] ->
        {:ok, base}

      flex in [:afternoon1, :afternoon2, :evening1, :evening2, :night1, :night2] ->
        {:ok, base + 12}

      flex == :noon ->
        {:ok, 12}

      flex == :midnight ->
        {:ok, 0}

      true ->
        # No PM signal — treat as morning (12-hour with no period
        # is ambiguous; we pick AM as the conservative default).
        {:ok, base}
    end
  end

  # Classifies a captured day-period string against the locale's
  # am/pm names (all contexts and widths, case-insensitive).
  defp locale_period_kind("", _day_periods), do: nil

  defp locale_period_kind(period, day_periods) do
    period = normalize_period_spaces(period)

    cond do
      period in downcased_period_names(day_periods, :pm) -> :pm
      period in downcased_period_names(day_periods, :am) -> :am
      true -> nil
    end
  end

  defp downcased_period_names(day_periods, key) do
    for context <- [:format, :stand_alone],
        width <- [:wide, :abbreviated, :narrow],
        {period, entry} <- get_in(day_periods, [context, width]) || %{},
        period == key,
        name <- entry_to_names(entry),
        do: name |> String.downcase() |> normalize_period_spaces()
  end

  # CLDR names may use NBSP or narrow NBSP where users type ASCII
  # spaces; compare with all space flavours collapsed.
  defp normalize_period_spaces(text) do
    String.replace(text, ~r/[\s\x{00A0}\x{202F}]+/u, " ")
  end

  # The flexible periods a captured `B` name names, in `@flex_period_keys`
  # order, or none when the field read an AM/PM name or nothing.
  defp flex_periods(caps, day_periods) do
    case Map.get(caps, "flex_period", "") do
      "" ->
        []

      name ->
        name = name |> String.downcase() |> normalize_period_spaces()

        named =
          for {key, candidate} <- collect_flex_period_pairs(day_periods),
              candidate |> String.downcase() |> normalize_period_spaces() == name,
              do: key

        Enum.filter(@flex_period_keys, &(&1 in named))
    end
  end

  defp extract_field(caps, key, default) do
    case caps[key] do
      nil when is_integer(default) ->
        {:ok, default}

      raw when is_binary(raw) and raw != "" ->
        case Integer.parse(raw) do
          {n, ""} -> {:ok, n}
          _ -> :error
        end

      _ when is_integer(default) ->
        {:ok, default}

      _ ->
        :error
    end
  end

  defp extract_microsecond(caps) do
    case caps["microsecond"] do
      nil ->
        {:ok, {0, 0}}

      "" ->
        {:ok, {0, 0}}

      raw ->
        # CLDR `S` is decimal-truncated, not rounded. Pad / trim
        # to 6 digits for Elixir's `Time` microsecond field.
        precision = min(String.length(raw), 6)
        padded = String.pad_trailing(String.slice(raw, 0, 6), 6, "0")

        case Integer.parse(padded) do
          {n, ""} -> {:ok, {n, precision}}
          _ -> :error
        end
    end
  end
end
