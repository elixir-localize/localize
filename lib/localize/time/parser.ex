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
  # count, matching the ICU lenient mode behaviour.
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
  # Time-zone tokens (`z`, `Z`, `v`, `V`, `x`, `X`, `O`) are
  # captured permissively but not currently resolved to an IANA
  # zone. See `Localize.DateTime.Parser` for the datetime
  # case where timezone resolution actually matters.
  #

  alias Localize.TimeParseError
  alias Localize.Calendar, as: LCalendar
  alias Localize.DateTime.Format

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
  string (or `nil` when the pattern carried no zone). The
  `Localize.DateTime.Parser` uses this to feed
  `Calendrical.TimeZone.resolve/3` for DateTime building.

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

    case try_iso(input) do
      {:ok, time} ->
        {:ok, finalise_time(time, as), nil}

      :error ->
        try_locale_patterns(input, locale, as)
    end
  end

  # ISO 8601 always carries hour+minute+second (the stdlib
  # parser rejects shorter forms), so the map always has those
  # three. Microsecond is included only when the input
  # actually supplied fractional precision — `{n, 0}` means
  # "no fraction specified" and is omitted.
  defp finalise_time(%Time{} = time, :struct), do: time

  defp finalise_time(%Time{hour: h, minute: m, second: s, microsecond: us}, :map) do
    base = %{hour: h, minute: m, second: s}

    case us do
      {_, 0} -> base
      other -> Map.put(base, :microsecond, other)
    end
  end

  # ── ISO 8601 ─────────────────────────────────────────────────

  defp try_iso(input) do
    case Time.from_iso8601(input) do
      {:ok, time} -> {:ok, time}
      _ -> :error
    end
  end

  # ── Locale patterns (stubbed; filled out by subsequent edits)─

  defp try_locale_patterns(input, locale, as) do
    with {:ok, available} <- Format.available_formats(locale, :gregorian),
         {:ok, day_periods} <- LCalendar.day_periods(locale, :gregorian) do
      patterns = collect_patterns(available)
      lenient = load_lenient_date(locale)
      regexes = pattern_regexes(patterns, locale, day_periods, lenient)

      result =
        Enum.find_value(patterns, fn {_kind, pattern} ->
          {regex, tokens} = Map.get(regexes, pattern, {nil, nil})

          case match_pattern(input, regex, tokens, day_periods, as) do
            {:ok, value, zone} -> {:ok, value, zone}
            :error -> nil
          end
        end)

      result || {:error, no_match_error(input, locale)}
    end
  end

  # %{pattern => {compiled_regex_or_nil, tokens}} cached in :persistent_term
  # keyed by locale. The regex and tokens are pure functions of the locale's
  # day-period names and lenient rules, so the whole set is built once.
  defp pattern_regexes(patterns, locale, day_periods, lenient) do
    key = {__MODULE__, :pattern_regexes, locale}

    case :persistent_term.get(key, nil) do
      nil ->
        compiled =
          Map.new(patterns, fn {_kind, pattern} ->
            tokens = tokenize_pattern(pattern)
            regex_string = compile_regex(tokens, day_periods, lenient)

            regex =
              case Regex.compile(regex_string, "u") do
                {:ok, r} -> r
                {:error, _} -> nil
              end

            {pattern, {regex, tokens}}
          end)

        :persistent_term.put(key, compiled)
        compiled

      compiled ->
        compiled
    end
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
  defp collect_patterns(available) do
    for {skeleton, pattern_data} <- available,
        pattern <- resolve_pattern_variants(pattern_data),
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

  defp match_pattern(input, regex, tokens, day_periods, as) do
    with %Regex{} <- regex,
         %{} = caps <- Regex.named_captures(regex, input),
         {:ok, hour} <- extract_hour(caps, tokens, day_periods) do
      zone = extract_zone(caps)

      case as do
        :map ->
          {:ok, build_time_map(caps, hour, zone), zone}

        :struct ->
          with {:ok, minute} <- extract_field(caps, "minute", 0),
               {:ok, second} <- extract_field(caps, "second", 0),
               {:ok, microsecond} <- extract_microsecond(caps),
               {:ok, time} <- Time.new(hour, minute, second, microsecond) do
            {:ok, time, zone}
          else
            _ -> :error
          end
      end
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
  defp tokenize_pattern(pattern) do
    pattern
    |> String.graphemes()
    |> tokenize([], nil)
    |> Enum.reverse()
  end

  defp tokenize([], acc, nil), do: acc
  defp tokenize([], acc, current), do: [field_token(current) | acc]

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
  # `h` vs `hh` per ICU lenient mode.
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

  # Time zones (TR35 §Time Zone Parsing). Captures a strictly
  # zone-shaped token under `zone`. The Time parser doesn't
  # carry zone info (Time is wall-clock) so this is just
  # validation to prevent false matches like "midnight"
  # being eaten by a zone placeholder. The `DateTime` parser
  # additionally resolves the captured value into an offset.
  #
  # Accepted shapes:
  #   * `Z` — UTC marker
  #   * `[+-]HHMM` / `[+-]HH:MM` / `[+-]HH:MM:SS` — ISO offsets
  #   * `GMT` / `GMT[+-]H[:MM]` / `UTC[+-]...` — GMT format
  #   * IANA region/city — e.g. `Asia/Tokyo` (capital letter +
  #     slash + capital letter, optional underscores)
  #   * Abbreviation — `PST`, `JST`, `BST` (3-5 uppercase letters)
  #   * Locale name — `Pacific Time`, `Greenwich Mean Time`
  #     (capital-led words; one-or-more space-separated)
  defp field_regex({letter, _count}, _dp, _lenient) when letter in [:z, :Z, :v, :V, :x, :X, :O] do
    # Abbreviation. The lookahead excludes `AM`/`PM` so a
    # generic-zone pattern like `"h:mm:ss v"` doesn't
    # cannibalise inputs ending in an AM/PM marker — those
    # belong to the `a` letter.
    "(?P<zone>" <>
      "Z" <>
      "|" <>
      "[+\\-](?:\\d{2}:?\\d{2}(?::?\\d{2})?|\\d{2})" <>
      "|" <>
      "(?:GMT|UTC|UT)(?:[+\\-]\\d{1,2}(?::?\\d{2})?)?" <>
      "|" <>
      "[A-Z][A-Za-z_]+(?:/[A-Z][A-Za-z_+\\-]+)+" <>
      "|" <>
      "(?!AM|PM|am|pm|A\\.M\\.|P\\.M\\.)[A-Z]{2,5}" <>
      "|" <>
      "[A-Z][a-z]+(?: [A-Z][a-z]+){1,4}" <>
      ")"
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

  defp flex_period_regex(day_periods) do
    pairs = collect_flex_period_pairs(day_periods)

    case pairs do
      [] ->
        # Locale carries no flex period data — fall back to a
        # permissive match so the pattern still matches but
        # contributes no AM/PM information.
        "[\\p{L}\\.\\s]+?"

      pairs ->
        # Regex requires named groups to be unique. Group all
        # name variants for the same period key under a
        # single capture so `__bp_morning1` matches "in the
        # morning" OR "morning" without duplicating the
        # named group.
        names_by_key =
          pairs
          |> Enum.group_by(fn {key, _name} -> key end, fn {_key, name} -> name end)
          |> Enum.map(fn {key, names} ->
            sorted = names |> Enum.uniq() |> Enum.sort_by(&(-byte_size(&1)))
            {key, sorted}
          end)
          # Sort groups by their longest name so e.g. "midnight"
          # is tried before "mi" (preventing premature short
          # matches on locales with very short narrow forms).
          |> Enum.sort_by(fn {_key, names} -> -byte_size(hd(names)) end)

        branches =
          Enum.map(names_by_key, fn {key, names} ->
            alternation = Enum.map_join(names, "|", &Regex.escape/1)
            # Case-insensitive per CLDR TR35 §6.5.
            "(?P<__bp_#{key}>(?i:#{alternation}))"
          end)

        "(?:" <> Enum.join(branches, "|") <> ")"
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
  defp resolve_hour(n, :H, _caps, _tokens, _day_periods) when n in 0..23, do: {:ok, n}
  defp resolve_hour(24, :k, _caps, _tokens, _day_periods), do: {:ok, 0}
  defp resolve_hour(n, :k, _caps, _tokens, _day_periods) when n in 1..23, do: {:ok, n}

  defp resolve_hour(n, letter, caps, _tokens, day_periods) when letter in [:h, :K] do
    base = if letter == :h, do: rem(n, 12), else: n

    period = caps |> Map.get("day_period", "") |> String.downcase()
    flex = flex_period_from_caps(caps)

    cond do
      period in ["pm", "p.m."] ->
        {:ok, base + 12}

      # Locale day-period names that carry no ASCII am/pm signal
      # (ja 午前/午後, el π.μ./μ.μ., narrow "a"/"p") resolve
      # against the locale's own am/pm name sets.
      locale_period_kind(period, day_periods) == :pm ->
        {:ok, base + 12}

      locale_period_kind(period, day_periods) == :am ->
        {:ok, base}

      period in ["am", "a.m.", ""] and flex == nil ->
        {:ok, base}

      # Locale-specific day-period name — look up via heuristic.
      String.contains?(period, "pm") or String.contains?(period, "p.m") ->
        {:ok, base + 12}

      true ->
        resolve_flex_period_hour(base, flex)
    end
  end

  defp resolve_hour(_, _, _, _, _), do: :error

  # No explicit AM/PM marker but a flex period (B) was captured.
  # TR35 §Parsing Day Periods: derive AM/PM from the period's
  # defining range. Conservative mapping that holds for every
  # locale CLDR ships.
  defp resolve_flex_period_hour(base, flex) do
    cond do
      flex in [:morning1, :morning2] ->
        {:ok, base}

      flex in [:afternoon1, :afternoon2, :evening1, :evening2, :night1, :night2] ->
        # `night1`/`night2` cover hours straddling midnight in
        # some locales (e.g. en covers 21:00–05:59). For the
        # typical 12-hour input "10 at night" → 22:00 we add
        # 12 when the base is below 6, and we add 12 always
        # when the typed hour is in the 6-11 range. The corner
        # case of "1 at night" meaning 01:00 is intentionally
        # mapped to 13:00 — `night1` is locale-defined and we
        # follow CLDR rather than guess.
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

  # The `B` regex emits one branch per `(period_key, name)`
  # tuple, named `__bp_<key>`. Find which one fired and
  # return its key atom.
  defp flex_period_from_caps(caps) do
    case Enum.find(caps, fn
           {"__bp_" <> _, value} -> value != ""
           _ -> false
         end) do
      {"__bp_" <> key_str, _} ->
        try do
          String.to_existing_atom(key_str)
        rescue
          _ -> nil
        end

      _ ->
        nil
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
