defmodule Localize.Date.Parser do
  @moduledoc false

  # Locale-aware parser for user-typed date strings, with full
  # multi-calendar support.
  #
  # Public entry point: `Localize.Date.parse/2`. This module
  # is the underlying engine.
  #
  # Strategy, in order:
  #
  # * Bare ISO-8601 (`YYYY-MM-DD`) — accepted in every locale.
  # This is the wire format and the unambiguous escape hatch.
  #
  # * Locale-specific CLDR patterns. The parser pulls
  # `:short`, `:medium`, `:long`, `:full` for the (locale,
  # calendar) tuple and tries each as a regex template. CLDR
  # encodes the locale's preferred field order
  # (`M/d/yy` in `en`, `dd.MM.y` in `de`, `Gy年M月d日` in
  # Japanese imperial), so the same input may parse to
  # different dates under different locales — by design.
  #
  # ### Calendar support
  #
  # Any CLDR calendar that has a `Calendrical.*` module
  # implementation: `:gregorian`, `:buddhist`, `:islamic_civil`,
  # `:islamic_umalqura`, `:islamic_tbla`, `:islamic_rgsa`,
  # `:islamic`, `:japanese`, `:persian`, `:hebrew`, `:coptic`,
  # `:ethiopic`, `:ethiopic_amete_alem`, `:indian`, `:roc`,
  # `:chinese`, `:dangi`.
  #
  # The `:calendar` option says **what calendar to interpret
  # the input as**. The result is always a `t:Date.t/0` whose
  # `:calendar` field is the corresponding Calendrical module
  # (or `Calendar.ISO` for `:gregorian`). Convert to ISO with
  # `Date.convert/2` if needed.
  #
  # ### Lenient matching
  #
  # * `dd` and `MM` accept 1–2 digits (so `3/4/26` parses
  # under `en-GB`'s `dd/MM/y`).
  #
  # * Any 2-digit typed year pivots into the 80-back/20-forward
  # window relative to the reference year (overridable via
  # `:reference_date`).
  #
  # * Literal separators in the format pattern expand to the
  # locale's CLDR `lenient-scope-date` equivalence class —
  # `-`, `/`, `.`, non-breaking hyphen, etc. all match in
  # locales where CLDR considers them equivalent.
  #
  # * Spaces between adjacent fields are accepted regardless of
  # whether the pattern includes them — so
  # `民國 115年5月16日` (with a space after the era marker)
  # parses correctly under the CLDR pattern `Gy年M月d日`.
  #
  # * Non-Latin digits are transliterated to Latin before
  # integer parsing using the locale's default number system.
  # `٢٤` (Arabic-Indic 24) and `24` both parse identically.
  #
  # ### Era handling
  #
  # For era-aware calendars (Japanese imperial, Islamic Hijri,
  # ROC, etc.), the `G` field in CLDR patterns marks the era
  # marker (`平成`, `هـ`, `AH`, `BCE`, `民國`). The parser
  # captures the era name, resolves it via
  # `Localize.Calendar.eras/2`, and computes the calendar-year
  # from the era-year for calendars that need it (Japanese).
  #

  alias Localize.{DateParseError, DateRangeParseError}
  alias Localize.Calendar, as: LCalendar
  alias Localize.DateTime.Format

  @month_name_widths %{3 => :abbreviated, 4 => :wide, 5 => :narrow}
  @era_widths %{1 => :abbreviated, 2 => :abbreviated, 3 => :abbreviated, 4 => :wide, 5 => :narrow}

  # Range/separator dashes treated as interchangeable in lenient
  # parsing. CLDR interval patterns use U+2013 EN DASH; users
  # routinely type ASCII hyphen `-` instead. We also include
  # U+2014 EM DASH, U+2212 MINUS SIGN, and U+2011 NON-BREAKING
  # HYPHEN. When a pattern literal is any of these, the compiled
  # regex accepts all of them — and any CLDR `lenient-scope-date`
  # equivalences for that char (e.g., `.`, `/`) are unioned in.
  @dash_chars ["-", "‑", "–", "—", "−"]

  # CLDR formats often use narrow no-break space (U+2009),
  # NBSP (U+00A0), narrow NBSP (U+202F), and ideographic
  # space (U+3000) around separators. Real-world input uses
  # plain ASCII space. Accept any of them as the same slot.
  @space_class "[    　]*"
  @literal_space_class "[    　]+"

  @doc """
  Parses `input` as a locale-formatted date.

  See `Localize.Date.parse/2` for the public contract.
  """
  @spec parse(String.t(), Keyword.t()) ::
          {:ok, Date.t() | map()} | {:error, Exception.t()}
  def parse(input, options \\ []) when is_binary(input) do
    locale = Keyword.get(options, :locale) || Localize.get_locale()
    cldr_calendar = normalise_calendar(Keyword.get(options, :calendar, :gregorian))
    reference_year = (Keyword.get(options, :reference_date) || Date.utc_today()).year
    return_module = resolve_return_calendar(options, cldr_calendar)
    as = Keyword.get(options, :as, :struct)

    input =
      input
      |> normalise_input()
      |> preprocess_safe(locale, cldr_calendar)

    attempt = fn current ->
      case try_iso(current, return_module) do
        {:ok, date} ->
          {:ok, finalise_date(date, as)}

        :error ->
          try_locale_patterns(
            current,
            locale,
            cldr_calendar,
            reference_year,
            return_module,
            as
          )
      end
    end

    case attempt.(input) do
      {:ok, _} = ok ->
        ok

      {:error, _} = err ->
        retry_without_ordinal_affixes(attempt, input, locale, err)
    end
  end

  # Retry with ordinal affixes stripped. Only fires if the
  # original input couldn't be parsed, so CLDR-baked
  # ordinal text (e.g. `"2nd quarter"` quarter-wide name)
  # is preserved on the first attempt.
  defp retry_without_ordinal_affixes(attempt, input, locale, original_error) do
    stripped = strip_ordinal_affixes(input, locale)

    if stripped == input do
      original_error
    else
      case attempt.(stripped) do
        {:ok, _} = ok -> ok
        {:error, _} -> original_error
      end
    end
  end

  # Trim leading/trailing whitespace AND collapse interior runs of
  # ASCII space / tab to a single space, so inputs like
  # `"02/21/2018  9:37:42 AM"` (double space) and
  # `"Fri Mar  2 09:01:57 2018"` (Unix `date` output) parse without
  # the parser having to model every possible whitespace variant.
  # Only ASCII space + tab are collapsed; NBSP / NNBSP / ideographic
  # space remain because CLDR patterns use them with semantic intent.
  @doc false
  def normalise_input(input) when is_binary(input) do
    input
    |> String.trim()
    |> String.replace(~r/[ \t]{2,}/, " ")
  end

  # Two-stage locale-aware preprocessing.
  #
  # * `preprocess_safe/3` runs upfront — weekday-prefix stripping
  #   plus any other pass that can't conflict with CLDR-baked
  #   literals. Safe because CLDR patterns spell weekdays as
  #   `E`/`c` tokens, never as inline literal text.
  #
  # * `strip_ordinal_affixes/2` runs only as a fallback, after
  #   the first parse attempt fails. Necessary because CLDR DOES
  #   bake ordinals into some literal text — `"2nd quarter"` is
  #   the wide form of quarter 2 in `:en`. Stripping unconditionally
  #   would rewrite that to `"2 quarter"`, breaking the pattern
  #   match. Inputs the unmodified parser handles (CLDR-shipped
  #   patterns) keep working; inputs only achievable via lenient
  #   rewrites (`"1st January"`) succeed on the retry.
  @doc false
  def preprocess_safe(input, locale, cldr_calendar) when is_binary(input) do
    strip_weekday_prefix(input, locale, cldr_calendar)
  end

  # Strip a recognised weekday name from the start of `input`,
  # along with optional `.`/`,`/`;` punctuation immediately
  # after it. Trailing whitespace (or end-of-input) is required
  # so that single-letter narrow forms — which would otherwise
  # match the first letter of any token — don't strip
  # accidentally; narrow widths are also excluded from the
  # alternation for the same reason.
  defp strip_weekday_prefix(input, locale, cldr_calendar) do
    case Localize.Calendar.days(locale, cldr_calendar) do
      {:ok, %{} = days_data} ->
        names = collect_weekday_names(days_data)

        if names == [] do
          input
        else
          alternation = Enum.map_join(names, "|", &Regex.escape/1)
          regex = Regex.compile!("\\A(?i:" <> alternation <> ")[\\.,;]?(?:\\s+|\\z)", "u")
          Regex.replace(regex, input, "", global: false)
        end

      _ ->
        input
    end
  end

  # Wide + abbreviated + short, format + stand_alone. Narrow
  # excluded (single-letter, too easy to false-match). For
  # abbreviated/short variants where the CLDR name carries a
  # trailing period (fr "lun.", de format "Mo."), include both
  # the literal and the period-stripped form so input that
  # either has or lacks the period matches.
  defp collect_weekday_names(days_data) do
    for ctx <- [:format, :stand_alone],
        width <- [:wide, :abbreviated, :short],
        name_map = get_in(days_data, [ctx, width]) || %{},
        {_index, name} when is_binary(name) <- name_map,
        variant <- weekday_name_variants(name) do
      variant
    end
    |> Enum.uniq()
    |> Enum.sort_by(&(-String.length(&1)))
  end

  defp weekday_name_variants(name) do
    trimmed = String.trim_trailing(name, ".")
    if trimmed != name and trimmed != "", do: [name, trimmed], else: [name]
  end

  # Ordinal stripping is RBNF-driven: we probe `digits-ordinal`
  # with a representative set of digits, diff each render
  # against the bare digit to recover the locale's suffix(es)
  # and prefix(es), then strip them from digit runs in the
  # input. Locales without a `digits-ordinal` rule (de spellout-
  # only, ru bare-digit) yield empty affix sets and short-
  # circuit to a no-op. Suffix capture is lenient about an
  # optional `.` between digit and indicator (Spanish/Portuguese
  # `1.º` shape) which CLDR doesn't ship but real input often
  # carries.
  defp strip_ordinal_affixes(input, locale) do
    {suffixes, prefixes} = ordinal_affixes(locale)

    input
    |> strip_ordinal_suffixes(suffixes)
    |> strip_ordinal_prefixes(prefixes)
  end

  defp strip_ordinal_suffixes(input, []), do: input

  defp strip_ordinal_suffixes(input, suffixes) do
    alternation = Enum.map_join(suffixes, "|", &Regex.escape/1)
    regex = Regex.compile!("(\\d+)\\.?(?:" <> alternation <> ")(?=\\b|\\s|$)", "u")
    Regex.replace(regex, input, "\\1")
  end

  defp strip_ordinal_prefixes(input, []), do: input

  defp strip_ordinal_prefixes(input, prefixes) do
    alternation = Enum.map_join(prefixes, "|", &Regex.escape/1)
    regex = Regex.compile!("(?:" <> alternation <> ")(\\d+)", "u")
    Regex.replace(regex, input, "\\1")
  end

  @ordinal_probe_digits [1, 2, 3, 4, 11, 12, 13, 21, 22, 23, 31]

  # Locales known to render `digits-ordinal` as just digit + `.`
  # (de) collide with the period as a date-field separator —
  # stripping the period after every digit would mangle
  # `"16.05.2026"`. We reject any suffix that's empty or that
  # consists only of date-separator characters (`.`, `-`, `/`,
  # `_`) once leading periods have been peeled (Spanish-style
  # `"1.º"` peels to `"º"` which is a real, unambiguous
  # indicator).
  # The ordinal suffixes/prefixes are a pure function of locale (derived by
  # probing RBNF `digits-ordinal`), so the result is cached. Without this,
  # every failing parse re-ran ~11 RBNF conversions to rediscover them.
  defp ordinal_affixes(locale) do
    key = {__MODULE__, :ordinal_affixes, locale}

    case :persistent_term.get(key, nil) do
      nil ->
        affixes = compute_ordinal_affixes(locale)
        :persistent_term.put(key, affixes)
        affixes

      affixes ->
        affixes
    end
  end

  defp compute_ordinal_affixes(locale) do
    Enum.reduce(@ordinal_probe_digits, {[], []}, fn n, {suffs, prefs} ->
      case Localize.Number.Rbnf.to_string(n, "digits-ordinal", locale: locale) do
        {:ok, rendered} -> collect_ordinal_affix(rendered, n, {suffs, prefs})
        _ -> {suffs, prefs}
      end
    end)
    |> then(fn {s, p} -> {Enum.uniq(s), Enum.uniq(p)} end)
  end

  # Diff one RBNF render against its bare digit: a residue
  # before the digit accumulates as a prefix, a residue after
  # it (period-normalised) as a suffix.
  defp collect_ordinal_affix(rendered, n, {suffs, prefs}) do
    digit_str = Integer.to_string(n)

    case String.split(rendered, digit_str, parts: 2) do
      ["", suffix] when suffix != "" ->
        case normalise_ordinal_suffix(suffix) do
          nil -> {suffs, prefs}
          normalised -> {[normalised | suffs], prefs}
        end

      [prefix, ""] when prefix != "" ->
        {suffs, [prefix | prefs]}

      _ ->
        {suffs, prefs}
    end
  end

  defp normalise_ordinal_suffix(suffix) do
    case String.trim_leading(suffix, ".") do
      "" -> nil
      other -> if separator_only?(other), do: nil, else: other
    end
  end

  defp separator_only?(string) do
    string |> String.graphemes() |> Enum.all?(&(&1 in [".", "-", "/", "_"]))
  end

  # When `as: :map`, surface the bare fields rather than a
  # `%Date{}`. The ISO path always produces a complete date, so
  # the map is full (year+month+day+calendar); the locale-
  # patterns path may yield a partial map when the input
  # omitted fields (e.g. `"May 5"` → `%{month: 5, day: 5,
  # calendar: …}`).
  defp finalise_date(%Date{} = date, :struct), do: date
  defp finalise_date(%Date{} = date, :map), do: date_to_map(date)

  defp date_to_map(%Date{year: y, month: m, day: d, calendar: cal}) do
    %{year: y, month: m, day: d, calendar: cal}
  end

  # Resolve the target calendar module for the returned Date.
  # The `:return_calendar` option accepts:
  #
  #   * `:native` (default) — return the Date in whatever
  #     calendar the `:calendar` option named. So
  #     `parse("2026-05-17", calendar: :hebrew)` returns
  #     `~D[5786-10-01 Cldr.Calendar.Hebrew]`. This is the
  #     natural behavior — the `:calendar` option says
  #     "interpret AND return in this calendar".
  #
  #   * `:iso` — force the result into `Calendar.ISO`
  #     (Gregorian). Use this when a downstream consumer
  #     (e.g. an Ecto `:date` cast) requires ISO.
  #
  #   * a calendar module implementing `Calendar` —
  #     return the Date in that specific calendar regardless
  #     of `:calendar`.
  #
  defp resolve_return_calendar(options, cldr_calendar) do
    case Keyword.get(options, :return_calendar, :native) do
      :iso -> Calendar.ISO
      :native -> elem(resolve_calendar_module(cldr_calendar), 1)
      module when is_atom(module) -> module
    end
  end

  @doc """
  Parses a single-string date range. See
  `Localize.Date.parse_range/2` for the public contract.
  """
  @spec parse_range(String.t(), Keyword.t()) ::
          {:ok, Date.Range.t() | {map(), map()}} | {:error, Exception.t()}
  def parse_range(input, options \\ []) when is_binary(input) do
    options = normalise_calendar_option(options)
    locale = Keyword.get(options, :locale) || Localize.get_locale()
    cldr_calendar = Keyword.get(options, :calendar, :gregorian)
    reference_year = (Keyword.get(options, :reference_date) || Date.utc_today()).year
    allow_inverted = Keyword.get(options, :allow_inverted, false)
    as = Keyword.get(options, :as, :struct)

    # Range inputs are pre-split internally by interval-pattern
    # matching, and each endpoint goes through `parse/2` for the
    # split-and-parse fallback — so endpoint-level ordinal
    # stripping is handled by `parse/2`. Range-level interval
    # patterns don't bake ordinals into their literals (CLDR's
    # interval patterns share the field set with regular date
    # patterns), so safe-pass preprocessing is sufficient here.
    input =
      input
      |> normalise_input()
      |> preprocess_safe(locale, cldr_calendar)

    # Strategy:
    # 1. Try the locale's CLDR interval patterns first — these
    #    are the only way to parse inputs where one endpoint is
    #    partial (e.g. "May 5 – May 10, 2026" where left has no
    #    year and inherits from right).
    # 2. Fall back to a naive split-then-parse-each-side. Catches
    #    inputs the interval patterns don't cover (e.g. mixed
    #    formats, ISO endpoints).
    case match_any_interval_pattern(input, locale, cldr_calendar, reference_year, as) do
      {:ok, from, to} ->
        finalise_range(from, to, allow_inverted, as)

      :error ->
        case split_on_interval_separator(input, locale, cldr_calendar) do
          {:ok, from_string, to_string} ->
            parse_range_pair(from_string, to_string, options)

          :error ->
            {:error,
             DateRangeParseError.exception(
               input: input,
               reason: :no_separator,
               locale: locale
             )}
        end
    end
  end

  # In `:map` mode there's no `Date.Range` to build and no
  # `Date.compare/2` to run for inversion checking — the
  # partial maps may not have enough fields to compare. We
  # return the pair as-is and let the caller decide.
  defp finalise_range(%Date{} = from, %Date{} = to, allow_inverted, :struct) do
    build_range(from, to, allow_inverted)
  end

  defp finalise_range(%{} = from, %{} = to, _allow_inverted, :map) do
    {:ok, {from, to}}
  end

  # ── Interval pattern matching (skeleton inheritance) ─────────

  # Walk every interval pattern published for the locale's
  # standard date skeletons (`:yMd`, `:yMMMd`, `:yMMMMd`,
  # `:Md`, `:MMMd`, `:MMMMd`, `:GyMd`, etc.) and try each one
  # against the full input. The CLDR convention is that the
  # *first* occurrence of each field belongs to the left
  # endpoint and the *second* occurrence (after the implicit
  # separator) belongs to the right endpoint. Endpoint-1
  # fields not present in the pattern inherit from endpoint-2
  # (and vice versa), which is how `"May 5 – May 10, 2026"`
  # parses correctly even though the left side has no year.
  defp match_any_interval_pattern(input, locale, cldr_calendar, reference_year, as) do
    with {:ok, intervals} <- Format.interval_formats(locale, cldr_calendar),
         {:ok, months_data} <- LCalendar.months(locale, cldr_calendar) do
      lenient = load_lenient_date(locale)
      transliterated = transliterate_digits(input, locale)
      eras_data = maybe_load_eras(locale, cldr_calendar)

      cldr_patterns =
        for {skeleton, by_field} <- intervals,
            is_atom(skeleton),
            is_map(by_field),
            {_field, pattern} <- by_field,
            is_binary(pattern) do
          pattern
        end

      # Each CLDR pattern is tried as-is, then also through a set
      # of day-first variants (see `synthesize_day_first_variants/1`)
      # so informal orderings like `"23 - 25 May, 2026"` and
      # `"5 May – 10 June, 2026"` parse alongside the CLDR-canonical
      # `"May 23 – 25, 2026"`.
      # Try day-bearing patterns before month/year-only ones, longest
      # first within each group. The CLDR interval data arrives as a
      # map whose iteration order is arbitrary, and without this an
      # M/y pattern can claim "May 5 – May 10" in map mode as
      # year 5 / year 2010 depending on which pattern happens to be
      # tried first.
      patterns =
        cldr_patterns
        |> Enum.flat_map(fn p -> [p | synthesize_day_first_variants(p)] end)
        |> Enum.uniq()
        |> Enum.sort_by(&interval_pattern_specificity/1)

      Enum.find_value(patterns, :error, fn pattern ->
        case match_interval_pattern(
               transliterated,
               pattern,
               months_data,
               eras_data,
               lenient,
               reference_year,
               cldr_calendar,
               as
             ) do
          {:ok, left, right} -> {:ok, left, right}
          :error -> nil
        end
      end)
    else
      _ -> :error
    end
  end

  defp match_interval_pattern(
         input,
         pattern,
         months_data,
         eras_data,
         lenient,
         reference_year,
         cldr_calendar,
         as
       ) do
    {tokens_l, tokens_r} = split_interval_tokens(tokenize_pattern(pattern))

    if tokens_r == [] do
      # Pattern with no repeating field — not a usable interval
      # pattern (would parse only a single endpoint).
      :error
    else
      with {:ok, regex} <-
             compile_interval_regex(tokens_l, tokens_r, months_data, eras_data, lenient),
           %{} = caps <- Regex.named_captures(regex, input),
           {:ok, left_partial} <- extract_partial(caps, "left_", reference_year, cldr_calendar),
           {:ok, right_partial} <- extract_partial(caps, "right_", reference_year, cldr_calendar) do
        interval_endpoints_for(as, left_partial, right_partial, cldr_calendar)
      else
        _ -> :error
      end
    end
  end

  defp compile_interval_regex(tokens_l, tokens_r, months_data, eras_data, lenient) do
    left_regex =
      compile_capture_regex(tokens_l, months_data, eras_data, lenient, "left_")

    right_regex =
      compile_capture_regex(tokens_r, months_data, eras_data, lenient, "right_")

    Regex.compile("\\A" <> left_regex <> right_regex <> "\\z", "u")
  end

  defp interval_endpoints_for(:struct, left_partial, right_partial, cldr_calendar) do
    with {:ok, left_date} <- materialise(left_partial, right_partial, cldr_calendar),
         {:ok, right_date} <- materialise(right_partial, left_partial, cldr_calendar) do
      {:ok, left_date, right_date}
    else
      _ -> :error
    end
  end

  defp interval_endpoints_for(:map, left_partial, right_partial, cldr_calendar) do
    {:ok, calendar_module} = resolve_calendar_module(cldr_calendar)
    left_map = partial_to_map(left_partial, right_partial, calendar_module)
    right_map = partial_to_map(right_partial, left_partial, calendar_module)

    if interval_partial_meaningful?(left_partial) and
         interval_partial_meaningful?(right_partial) do
      {:ok, left_map, right_map}
    else
      :error
    end
  end

  # Build the partial map for one interval endpoint. Missing
  # fields inherit from the other endpoint (CLDR interval
  # convention) just like `materialise/3` does for the struct
  # path; the difference is we stop after inheritance and skip
  # the Date construction.
  defp partial_to_map(side, inherit_from, calendar_module) do
    year = side.year || inherit_from.year
    month = side.month || inherit_from.month
    day = side.day || inherit_from.day

    %{calendar: calendar_module}
    |> maybe_put(:year, year)
    |> maybe_put(:month, month)
    |> maybe_put(:day, day)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  # Reject regex matches where one side captured no date fields
  # at all — that's a malformed interval, not a legitimate
  # partial.
  defp interval_partial_meaningful?(%{year: nil, month: nil, day: nil}), do: false
  defp interval_partial_meaningful?(_), do: true

  # Sort key: day-bearing patterns first, then longer (more
  # specific) patterns within each group. Quoted literals are
  # stripped so a literal "d" in text does not count as a field.
  defp interval_pattern_specificity(pattern) do
    fields = String.replace(pattern, ~r/'[^']*'/u, "")
    {if(String.contains?(fields, "d"), do: 0, else: 1), -String.length(pattern)}
  end

  # Walk the token stream: a field that's already been seen
  # marks the start of the right endpoint. The tokens between
  # the first and second occurrence of any field (typically
  # just literal separator text) get appended to the left
  # side. We accept day-of-week (`E`/`c`) repeats as well as
  # the date fields.
  defp split_interval_tokens(tokens) do
    {left, right, _} =
      Enum.reduce(tokens, {[], [], MapSet.new()}, fn token, {l, r, seen} ->
        case classify_token(token) do
          {:field, letter} ->
            if MapSet.member?(seen, letter) or r != [] do
              {l, r ++ [token], seen}
            else
              {l ++ [token], r, MapSet.put(seen, letter)}
            end

          :literal ->
            if r == [] do
              {l ++ [token], r, seen}
            else
              {l, r ++ [token], seen}
            end
        end
      end)

    {left, right}
  end

  defp classify_token({:lit, _}), do: :literal
  defp classify_token({letter, _count}) when is_atom(letter), do: {:field, letter}

  # ── Day-first synthesized variants ──────────────────────────
  #
  # CLDR ships interval patterns in the field order each locale's
  # CLDR data prefers (e.g., English uses `"MMM d, y – MMM d, y"`
  # — month before day). Real-world input often uses informal
  # orderings:
  #
  #   * `"23 May – 25 May, 2026"` (day before month, per endpoint)
  #
  #   * `"23 – 25 May, 2026"`     (day before month + month moved
  #                                 to the end so it inherits
  #                                 across both endpoints)
  #
  # We generate these by structural transformation of the
  # tokenised CLDR pattern. Two moves are applied:
  #
  #   * **per-endpoint swap** — for each side independently,
  #     swap any adjacent `(MMM, whitespace, d)` to `(d,
  #     whitespace, MMM)`. Applies to widths `3..5` for both
  #     `:M` and `:L`.
  #
  #   * **cross-endpoint shift** — if MMM appears on only one
  #     side, remove it (with its adjacent space) from that side
  #     and re-insert it on the *other* side, immediately
  #     before any trailing year/literal cluster.
  #
  # The two moves combine to yield 0–3 variants per source
  # pattern. They're tried in addition to (not in place of) the
  # CLDR-canonical patterns.
  defp synthesize_day_first_variants(pattern_string) do
    tokens = tokenize_pattern(pattern_string)
    {left, right} = split_interval_tokens(tokens)

    swap_variants =
      [
        {swap_md_tokens(left), right},
        {left, swap_md_tokens(right)},
        {swap_md_tokens(left), swap_md_tokens(right)}
      ]
      |> Enum.reject(fn {l, r} -> l == left and r == right end)

    shift_variants = cross_endpoint_shift(left, right)

    (swap_variants ++ shift_variants)
    |> Enum.uniq()
    |> Enum.map(fn {l, r} -> detokenize_pattern(l ++ r) end)
    |> Enum.reject(&(&1 == pattern_string))
    |> Enum.uniq()
  end

  # Swap any (MMM-or-LLL, whitespace-only literal, d) sequence
  # to (d, same-whitespace, MMM-or-LLL). Works on the
  # token-list side returned by `split_interval_tokens/1`;
  # named differently from the existing single-pattern
  # `swap_month_day/1` to avoid arity-1 clause collision.
  defp swap_md_tokens(tokens), do: do_swap_md(tokens, [])

  defp do_swap_md([], acc), do: Enum.reverse(acc)

  defp do_swap_md([{letter, count} = m, {:lit, sp} = lit, {:d, _} = d | rest], acc)
       when letter in [:M, :L] and count in 3..5 do
    if String.trim(sp) == "" do
      # Reverse order: prepend in (m, lit, d) sequence so that
      # `Enum.reverse(acc)` yields (d, lit, m).
      do_swap_md(rest, [m, lit, d | acc])
    else
      do_swap_md([lit, d | rest], [m | acc])
    end
  end

  defp do_swap_md([head | rest], acc), do: do_swap_md(rest, [head | acc])

  # If exactly one side has a month token, lift it off that side
  # and insert it into the other side just before any trailing
  # year/literal cluster.
  defp cross_endpoint_shift(left, right) do
    cond do
      has_month?(left) and not has_month?(right) ->
        shift_month_to_right(left, right)

      has_month?(right) and not has_month?(left) ->
        shift_month_to_left(left, right)

      true ->
        []
    end
  end

  defp shift_month_to_right(left, right) do
    case extract_month(left) do
      {nil, _} -> []
      {month, left_without} -> [{left_without, insert_month_before_trailer(right, month)}]
    end
  end

  defp shift_month_to_left(left, right) do
    case extract_month(right) do
      {nil, _} -> []
      {month, right_without} -> [{insert_month_before_trailer(left, month), right_without}]
    end
  end

  defp has_month?(tokens) do
    Enum.any?(tokens, fn
      {letter, count} when letter in [:M, :L] and count in 3..5 -> true
      _ -> false
    end)
  end

  # Extract the first month token from a side, also removing the
  # whitespace-only literal that's adjacent to it (preferring the
  # one that *follows* it, since CLDR conventions put `MMM `
  # before the day). Returns `{month_token | nil, remaining_tokens}`.
  defp extract_month(tokens), do: do_extract_month(tokens, [])

  defp do_extract_month([], acc), do: {nil, Enum.reverse(acc)}

  defp do_extract_month([{letter, count} = m, {:lit, sp} | rest], acc)
       when letter in [:M, :L] and count in 3..5 do
    if String.trim(sp) == "" do
      {m, Enum.reverse(acc) ++ rest}
    else
      do_extract_month(rest, [{:lit, sp}, m | acc])
    end
  end

  defp do_extract_month([{:lit, sp}, {letter, count} = m | rest], acc)
       when letter in [:M, :L] and count in 3..5 do
    if String.trim(sp) == "" do
      {m, Enum.reverse(acc) ++ rest}
    else
      do_extract_month([m | rest], [{:lit, sp} | acc])
    end
  end

  defp do_extract_month([head | rest], acc), do: do_extract_month(rest, [head | acc])

  # Insert `(space, month)` into a side just before any trailing
  # year-or-literal cluster. The trailing cluster is the longest
  # suffix made up of `:lit` and `:y` tokens; we insert before
  # the first literal of that cluster. If the side has no such
  # trailing cluster, append at the end.
  defp insert_month_before_trailer(tokens, month) do
    idx = trailer_start_index(tokens)
    {before_trailer, trailer} = Enum.split(tokens, idx)
    before_trailer ++ [{:lit, " "}, month] ++ trailer
  end

  defp trailer_start_index(tokens) do
    tokens
    |> Enum.reverse()
    |> Enum.reduce_while({length(tokens), false}, fn token, {idx, saw_field} ->
      cond do
        match?({:y, _}, token) -> {:cont, {idx - 1, true}}
        match?({:lit, _}, token) -> {:cont, {idx - 1, saw_field}}
        saw_field -> {:halt, {idx, true}}
        true -> {:halt, {length(tokens), false}}
      end
    end)
    |> case do
      {idx, true} -> idx
      _ -> length(tokens)
    end
  end

  # Like compile_regex/4 but each capture is prefixed (so
  # left/right halves of the interval pattern produce
  # distinguishable captures in the same regex). Lenient-gap
  # injection between adjacent field tokens applies here too.
  defp compile_capture_regex(tokens, months_data, eras_data, lenient, prefix, ctx \\ %{}) do
    tokens
    |> build_regex_parts(months_data, eras_data, lenient, prefix, ctx)
    |> Enum.join()
  end

  # Rewrite a single `(?P<name>...)` capture group's name to
  # `<prefix><name>` so left- and right-half captures don't
  # collide.
  defp rename_capture(regex, prefix) do
    Regex.replace(~r/\(\?P<([^>]+)>/, regex, fn _, name ->
      "(?P<#{prefix}#{name}>"
    end)
  end

  # Extract the `{year, month, day}` triple for one side of an
  # interval. Any field may be absent (missing from this
  # endpoint's portion of the pattern); represented as `nil`
  # so `materialise/3` can fill from the other side.
  defp extract_partial(caps, prefix, reference_year, cldr_calendar) do
    year = extract_partial_year(caps, prefix, reference_year, cldr_calendar)
    month = extract_partial_month(caps, prefix)
    day = extract_partial_day(caps, prefix)
    era_index = extract_partial_era_index(caps, prefix)
    year = apply_partial_era_year(year, era_index, cldr_calendar)

    {:ok, %{year: year, month: month, day: day}}
  end

  defp extract_partial_year(caps, prefix, reference_year, cldr_calendar) do
    case Map.get(caps, prefix <> "year") do
      nil ->
        nil

      "" ->
        nil

      raw ->
        case Integer.parse(raw) do
          {n, ""} -> maybe_pivot_two_digit_year(n, raw, reference_year, cldr_calendar)
          _ -> nil
        end
    end
  end

  # The 2-digit-year pivot is a Gregorian convention (see the
  # note on `extract_year_field/3`). Non-Gregorian years are
  # taken literally.
  defp maybe_pivot_two_digit_year(n, raw, reference_year, cldr_calendar) do
    if cldr_calendar == :gregorian and String.length(raw) == 2 do
      pivot_year(n, reference_year)
    else
      n
    end
  end

  defp extract_partial_month(caps, prefix) do
    case Map.get(caps, prefix <> "month") do
      raw when is_binary(raw) and raw != "" ->
        case Integer.parse(raw) do
          {n, ""} when n in 1..13 -> n
          _ -> nil
        end

      _ ->
        # No numeric-month capture (nil or ""), so look for a
        # name-based month capture (`__mN__` with the prefix).
        extract_month_by_name(caps, prefix)
    end
  end

  defp extract_partial_day(caps, prefix) do
    case Map.get(caps, prefix <> "day") do
      nil ->
        nil

      "" ->
        nil

      raw ->
        case Integer.parse(raw) do
          {n, ""} when n in 1..31 -> n
          _ -> nil
        end
    end
  end

  # Era field (Japanese imperial) — capture index, use it to
  # convert era_year into Gregorian year.
  defp extract_partial_era_index(caps, prefix) do
    prefixed_indexed_capture(caps, prefix, "__e", ~r/__e(\d+)__$/)
  end

  defp apply_partial_era_year(year, era_index, cldr_calendar) do
    case {cldr_calendar, era_index, year} do
      {:japanese, era, y} when is_integer(era) and is_integer(y) ->
        case japanese_era_start_year(era) do
          {:ok, start_year} -> start_year + y - 1
          :error -> y
        end

      _ ->
        year
    end
  end

  defp extract_month_by_name(caps, prefix) do
    case prefixed_indexed_capture(caps, prefix, "__m", ~r/__m(\d+)__$/) do
      n when is_integer(n) and n in 1..13 -> n
      _ -> nil
    end
  end

  # Find the first non-empty capture whose name starts with
  # `<prefix><marker>` (a `(?P<prefix__mN__>...)`-style named
  # branch) and return the integer index `N` embedded in the
  # capture name, or `nil`.
  defp prefixed_indexed_capture(caps, prefix, marker, index_regex) do
    with {key, _value} <-
           Enum.find(caps, fn
             {key, value} -> String.starts_with?(key, prefix <> marker) and value != ""
             _ -> false
           end),
         [_, index_str] <- Regex.run(index_regex, key),
         {n, ""} <- Integer.parse(index_str) do
      n
    else
      _ -> nil
    end
  end

  # Fill missing fields from `inherit_from`, then construct
  # the date in the requested calendar. The returned date
  # keeps the requested calendar — both interval endpoints
  # are materialised under the same calendar so the resulting
  # `Date.Range` is well-formed for any calendar, not just ISO.
  defp materialise(%{year: y, month: m, day: d}, inherit_from, cldr_calendar) do
    year = y || inherit_from.year
    month = m || inherit_from.month
    day = d || inherit_from.day

    if is_nil(year) or is_nil(month) or is_nil(day) do
      :error
    else
      with {:ok, calendar_module} <- resolve_calendar_module(cldr_calendar),
           {:ok, date} <- build_date(year, month, day, calendar_module) do
        {:ok, date}
      else
        _ -> :error
      end
    end
  end

  @doc """
  Parses pre-split range endpoints. See
  `Localize.Date.parse_range/2` for the public contract.
  """
  @spec parse_range_pair(String.t(), String.t(), Keyword.t()) ::
          {:ok, Date.Range.t() | {map(), map()}} | {:error, Exception.t()}
  def parse_range_pair(from_string, to_string, options)
      when is_binary(from_string) and is_binary(to_string) do
    options = normalise_calendar_option(options)
    allow_inverted = Keyword.get(options, :allow_inverted, false)
    as = Keyword.get(options, :as, :struct)

    with {:ok, from} <- parse_or_wrap(from_string, options, :from_parse_failed),
         {:ok, to} <- parse_or_wrap(to_string, options, :to_parse_failed) do
      finalise_range(from, to, allow_inverted, as)
    end
  end

  defp parse_or_wrap(string, options, reason_tag) do
    # `Date.Range` supports any calendar as long as both
    # endpoints share the same one. We let `parse/2` return
    # whatever `:calendar` the caller asked for and rely on
    # both endpoints being parsed under the same option. In
    # `:map` mode both endpoints come back as maps with the
    # `:calendar` key set to the same module.
    case parse(string, options) do
      {:ok, %Date{} = date} ->
        {:ok, date}

      {:ok, %{} = map} ->
        {:ok, map}

      {:error, %DateParseError{} = err} ->
        {:error,
         DateRangeParseError.exception(
           input: string,
           reason: reason_tag,
           cause: err
         )}
    end
  end

  defp build_range(from, to, allow_inverted) do
    case Date.compare(from, to) do
      :gt when not allow_inverted ->
        {:error,
         DateRangeParseError.exception(
           input: {from, to},
           reason: :inverted,
           from: from,
           to: to
         )}

      :gt ->
        {:ok, Date.range(from, to, -1)}

      _ ->
        {:ok, Date.range(from, to)}
    end
  end

  # Find the interval separator for this locale by consulting
  # CLDR's `intervalFormatFallback` (`[0, separator, 1]`).
  # Lenient: also accept `-`, `/`, `~`, `〜`, the en/em dashes,
  # and the locale separator with optional surrounding
  # whitespace.
  defp split_on_interval_separator(input, locale, cldr_calendar) do
    cldr_sep = lookup_interval_separator(locale, cldr_calendar)

    candidates =
      [cldr_sep | ["–", "—", "−", "〜", "~", "to", " - ", " / "]]
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    Enum.find_value(candidates, :error, fn sep ->
      case String.split(input, sep, parts: 2) do
        [left, right] ->
          left = String.trim(left)
          right = String.trim(right)

          if left != "" and right != "" do
            {:ok, left, right}
          else
            nil
          end

        _ ->
          nil
      end
    end)
  end

  defp lookup_interval_separator(locale, cldr_calendar) do
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

  # ── ISO 8601 ─────────────────────────────────────────────────

  defp try_iso(input, return_module) do
    with :error <- try_iso_extended(input),
         :error <- try_iso_basic(input),
         :error <- try_iso_ordinal(input),
         :error <- try_iso_week_date(input) do
      :error
    else
      {:ok, date} -> {:ok, convert_to(date, return_module)}
    end
  end

  # `YYYY-MM-DD` (extended). Delegated to stdlib.
  defp try_iso_extended(input) do
    case Date.from_iso8601(input) do
      {:ok, date} -> {:ok, date}
      _ -> :error
    end
  end

  # `YYYYMMDD` (basic, no separators). The 4+2+2 shape is
  # unambiguous and ISO 8601-conformant. The stdlib parser
  # rejects this; we accept it as a wire format.
  defp try_iso_basic(input) do
    case input do
      <<y::binary-size(4), m::binary-size(2), d::binary-size(2)>> ->
        with {year, ""} <- Integer.parse(y),
             {month, ""} <- Integer.parse(m),
             {day, ""} <- Integer.parse(d),
             {:ok, date} <- Date.new(year, month, day) do
          {:ok, date}
        else
          _ -> :error
        end

      _ ->
        :error
    end
  end

  # `YYYY-DDD` (ordinal date — year + day-of-year, 1..366).
  defp try_iso_ordinal(input) do
    with [_, y, d] <- Regex.run(~r/\A(\d{4})-(\d{3})\z/u, input),
         {year, ""} <- Integer.parse(y),
         {day_of_year, ""} <- Integer.parse(d),
         days = days_in_iso_year(year),
         true <- day_of_year in 1..days,
         {:ok, jan_1} <- Date.new(year, 1, 1) do
      {:ok, Date.add(jan_1, day_of_year - 1)}
    else
      _ -> :error
    end
  end

  defp days_in_iso_year(year) do
    if Calendar.ISO.leap_year?(year), do: 366, else: 365
  end

  # `YYYY-Www-D` (ISO week date — week-based year + week
  # number + day-of-week 1..7, Monday=1). Resolved against
  # `Calendar.ISO`'s week numbering.
  defp try_iso_week_date(input) do
    with [_, y, w, d] <- Regex.run(~r/\A(\d{4})-W(\d{2})-(\d)\z/u, input),
         {year, ""} <- Integer.parse(y),
         {week, ""} <- Integer.parse(w),
         {day, ""} <- Integer.parse(d),
         true <- week in 1..53,
         true <- day in 1..7,
         {:ok, date} <- iso_week_date_to_date(year, week, day) do
      {:ok, date}
    else
      _ -> :error
    end
  end

  # ISO 8601 week 01 is the week containing the first Thursday
  # of the year (equivalently, the week containing Jan 4).
  defp iso_week_date_to_date(year, week, day) do
    case Date.new(year, 1, 4) do
      {:ok, jan_4} ->
        jan_4_day_of_week = Date.day_of_week(jan_4)
        week_1_monday = Date.add(jan_4, -(jan_4_day_of_week - 1))
        candidate = Date.add(week_1_monday, (week - 1) * 7 + (day - 1))

        # Validate that the resulting date's week-based year
        # matches the requested year (rejects e.g. `2026-W53-1`
        # for years with only 52 weeks).
        case :calendar.iso_week_number({candidate.year, candidate.month, candidate.day}) do
          {^year, ^week} -> {:ok, candidate}
          _ -> :error
        end

      _ ->
        :error
    end
  end

  # ── Locale patterns ──────────────────────────────────────────

  defp try_locale_patterns(input, locale, cldr_calendar, reference_year, return_module, as) do
    with {:ok, calendar_module} <- resolve_calendar_module(cldr_calendar),
         {:ok, available} <- Format.available_formats(locale, cldr_calendar),
         {:ok, months_data} <- LCalendar.months(locale, cldr_calendar) do
      eras_data = maybe_load_eras(locale, cldr_calendar)
      quarters_data = maybe_load_quarters(locale, cldr_calendar)
      days_data = maybe_load_days(locale, cldr_calendar)
      lenient = load_lenient_date(locale)
      transliterated = transliterate_digits(input, locale)
      patterns = collect_patterns(available)

      ctx = %{
        quarters: quarters_data,
        days: days_data,
        locale: locale,
        cldr_calendar: cldr_calendar,
        months: months_data,
        eras: eras_data,
        lenient: lenient,
        reference_year: reference_year,
        calendar_module: calendar_module
      }

      # The compiled regex for each pattern is a pure function of
      # (locale, calendar) — the CLDR name data and lenient rules are
      # both derived from them — so the whole set is built once and
      # cached. Without this every parse (especially a *failing* one,
      # which exhausts all ~60 patterns) rebuilds and recompiles them.
      ctx = Map.put(ctx, :regexes, pattern_regexes(patterns, ctx))

      result =
        case as do
          :struct ->
            run_locale_pass(patterns, transliterated, ctx, return_module, :struct)

          :map ->
            # Pass 1 — strict: only accept a pattern whose fields
            # construct a valid date. This filters out misleading
            # regex matches like `MMM y` against "May 5" (which
            # would yield month=5, year=5). The winning pattern's
            # fields are then surfaced as a map, with the
            # synthesised year stripped if the user didn't supply
            # one.
            #
            # Pass 2 — lax: needed for legitimately partial inputs
            # that can't construct a date even with the reference
            # year (e.g. `"2026"` alone, or `"May"` alone).
            run_locale_pass(patterns, transliterated, ctx, return_module, {:map, :strict}) ||
              run_locale_pass(patterns, transliterated, ctx, return_module, {:map, :lax})
        end

      result || {:error, no_match_error(input, locale, cldr_calendar)}
    end
  end

  defp run_locale_pass(patterns, input, ctx, return_module, pass_as) do
    Enum.find_value(patterns, fn {_kind, pattern} ->
      case match_pattern(input, pattern, ctx, pass_as) do
        {:ok, %Date{} = date} -> {:ok, convert_to(date, return_module)}
        {:ok, %{} = map} -> {:ok, map}
        :error -> nil
      end
    end)
  end

  defp resolve_calendar_module(:gregorian), do: {:ok, Calendar.ISO}

  # A non-Gregorian CLDR calendar names a calendar module that lives
  # outside this library — `calendrical` supplies them. Its absence is
  # not an error: the parse still succeeds, in `Calendar.ISO`, which is
  # what the previous mapping did for an unknown calendar anyway.
  defp resolve_calendar_module(cldr_calendar) do
    case Localize.OptionalDependency.call(
           "Calendrical",
           :calendar_from_cldr_calendar_type,
           [cldr_calendar],
           package: "calendrical",
           operation: "parsing a date in the #{inspect(cldr_calendar)} calendar"
         ) do
      {:ok, module} -> {:ok, module}
      _no_calendar_module -> {:ok, Calendar.ISO}
    end
  end

  # The `:calendar` option accepts either a CLDR calendar type
  # atom (`:gregorian`, `:hebrew`, …) or a calendar module
  # (`Calendar.ISO`, or any `Calendar` implementation). Modules are
  # coerced to their CLDR atom via the `cldr_calendar_type/0`
  # callback; `Calendar.ISO` is the stdlib alias for
  # proleptic-Gregorian and maps to `:gregorian`.
  @doc false
  def normalise_calendar_option(options) do
    case Keyword.fetch(options, :calendar) do
      :error -> options
      {:ok, value} -> Keyword.put(options, :calendar, normalise_calendar(value))
    end
  end

  @doc false
  def normalise_calendar(Calendar.ISO), do: :gregorian

  def normalise_calendar(value) when is_atom(value) do
    if Code.ensure_loaded?(value) and function_exported?(value, :cldr_calendar_type, 0) do
      value.cldr_calendar_type()
    else
      value
    end
  end

  def normalise_calendar(other), do: other

  # Convert `date` into `target_module`, gracefully degrading
  # on conversion failure (returns the original date so the
  # parse still succeeds — better than turning a successful
  # parse into an error over a calendar arithmetic edge case).
  defp convert_to(%Date{calendar: target} = date, target), do: date

  defp convert_to(%Date{} = date, target_module) do
    case Date.convert(date, target_module) do
      {:ok, converted} -> converted
      _ -> date
    end
  end

  # ── Digit transliteration ────────────────────────────────────

  # Translate non-Latin digit runs to Latin before integer
  # parsing. Walk the locale's default number system; for
  # numeric systems with custom digit sets, build the
  # translation table on the fly.
  defp transliterate_digits(input, locale) do
    with {:ok, system} <- Localize.Number.System.number_system_from_locale(locale),
         {:ok, digits} when is_binary(digits) and byte_size(digits) > 0 <-
           Localize.Number.System.number_system_digits(system) do
      digit_translate(input, digits)
    else
      _ -> input
    end
  end

  defp digit_translate(input, "0123456789"), do: input

  defp digit_translate(input, digits) do
    table =
      digits
      |> String.graphemes()
      |> Enum.with_index()
      |> Map.new(fn {char, index} -> {char, Integer.to_string(index)} end)

    input
    |> String.graphemes()
    |> Enum.map_join(fn char -> Map.get(table, char, char) end)
  end

  # ── Lenient-scope-date equivalence map ──────────────────────

  defp load_lenient_date(locale) do
    key = {__MODULE__, :lenient_date, locale}

    case :persistent_term.get(key, nil) do
      nil ->
        map =
          case Localize.Locale.get(locale, [:lenient_parse, :date]) do
            {:ok, data} when is_map(data) -> build_equivalence_map(data)
            _ -> %{}
          end

        :persistent_term.put(key, map)
        map

      map ->
        map
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

  # ── Eras ─────────────────────────────────────────────────────

  defp maybe_load_eras(locale, calendar) do
    case LCalendar.eras(locale, calendar) do
      {:ok, data} -> data
      _ -> %{}
    end
  end

  defp maybe_load_quarters(locale, calendar) do
    case LCalendar.quarters(locale, calendar) do
      {:ok, data} -> data
      _ -> %{}
    end
  end

  defp maybe_load_days(locale, calendar) do
    case LCalendar.days(locale, calendar) do
      {:ok, data} -> data
      _ -> %{}
    end
  end

  # Iterate every parseable CLDR pattern in `availableFormats`.
  # CLDR's `dateStyle` standards (`:short`/`:medium`/`:long`/
  # `:full`) are just references INTO `availableFormats` —
  # `:medium` for en is `:yMMMd`, and `:yMMMd` is itself a
  # key in `availableFormats`. So iterating
  # `availableFormats` covers the standard four AND the
  # broader skeleton set in one pass.
  #
  # Skeletons that lack the fields needed to build a Date
  # (year-only patterns, weekday-only patterns, etc.) won't
  # successfully construct one and fall through naturally.
  defp collect_patterns(available) do
    base =
      for {skeleton, pattern_data} <- available,
          pattern <- resolve_pattern_variants(pattern_data),
          do: {skeleton, pattern}

    synthesised = synthesise_month_day_swaps(base)

    Enum.uniq(base ++ synthesised)
  end

  # For every pattern with a name-form month (`MMM`/`MMMM`/
  # `MMMMM`) AND a numeric day field, generate the same pattern
  # with the M and d tokens swapped. Name-form month + day is
  # unambiguous in either order, so we want "May 23" to parse in
  # `:fr` (CLDR has `d MMM`) and "23 May" to parse in `:en` (CLDR
  # has `MMM d, y`). Other tokens (year, era, weekday) and the
  # literal text between them stay in place — only the M↔d
  # positions exchange. Numeric M (count 1–2) is skipped because
  # the swap would be genuinely ambiguous with d.
  defp synthesise_month_day_swaps(patterns) do
    for {skeleton, pattern} <- patterns,
        swapped <- swap_month_day_variants(pattern),
        uniq: true,
        do: {skeleton, swapped}
  end

  # Variants per swappable pattern (CLDR `:en` `MMM d, y` is the
  # canonical example):
  #
  # * Naive swap with literals kept in place — `d MMM, y`. Matches
  #   `"23 Feb, 2013"`.
  #
  # * Comma-stripped swap — `d MMM y`. Matches `"23 Feb 2013"` and
  #   `"01 February 2013"`, the natural English reverse-order
  #   forms that idiomatically drop the comma.
  #
  # * Inter-field space → `-`/`/`/`.` substitutions on the
  #   comma-stripped swap — `d-MMM-y`, `d/MMM/y`, `d.MMM.y`.
  #   Match `"01-Feb-18"`, `"01/Jun./2018"`, `"01.Feb.2018"` etc.
  #   These forms are common in admin UIs, log lines, and ad-hoc
  #   input but aren't shipped as CLDR patterns.
  defp swap_month_day_variants(pattern) do
    case swap_month_day(pattern) do
      nil ->
        []

      swapped when swapped == pattern ->
        []

      swapped ->
        decommaed = strip_commas_in_literals(swapped)

        base =
          if decommaed != swapped,
            do: [swapped, decommaed],
            else: [swapped]

        separator_variants =
          for sep <- ["-", "/", "."],
              variant = replace_spaces_in_literals(decommaed, sep),
              variant != decommaed do
            variant
          end

        base ++ separator_variants
    end
  end

  defp replace_spaces_in_literals(pattern, sep) do
    pattern
    |> tokenize_pattern()
    |> Enum.map(fn
      {:lit, text} -> {:lit, String.replace(text, " ", sep)}
      other -> other
    end)
    |> detokenize_pattern()
  end

  defp swap_month_day(pattern) do
    tokens = tokenize_pattern(pattern)

    m_tokens =
      tokens |> Enum.with_index() |> Enum.filter(&match?({{:M, _}, _}, &1))

    d_tokens =
      tokens |> Enum.with_index() |> Enum.filter(&match?({{:d, _}, _}, &1))

    case {m_tokens, d_tokens} do
      {[{{:M, m_count}, m_idx}], [{{:d, d_count}, d_idx}]} when m_count >= 3 ->
        tokens
        |> List.replace_at(m_idx, {:d, d_count})
        |> List.replace_at(d_idx, {:M, m_count})
        |> detokenize_pattern()

      _ ->
        nil
    end
  end

  defp strip_commas_in_literals(pattern) do
    pattern
    |> tokenize_pattern()
    |> Enum.map(fn
      {:lit, text} -> {:lit, String.replace(text, ",", "")}
      other -> other
    end)
    |> detokenize_pattern()
  end

  defp detokenize_pattern(tokens) do
    Enum.map_join(tokens, "", &detokenize_token/1)
  end

  defp detokenize_token({:lit, ""}), do: ""

  defp detokenize_token({:lit, text}) when is_binary(text) do
    if Regex.match?(~r/[yYMdEGLcQqwWDeF]/u, text) do
      # CLDR letters inside the literal need quoting so the
      # re-tokenizer treats them as text, not field letters.
      # Escape internal single quotes with `''` per CLDR.
      "'" <> String.replace(text, "'", "''") <> "'"
    else
      text
    end
  end

  defp detokenize_token({letter, count}) when is_atom(letter) and is_integer(count) do
    String.duplicate(Atom.to_string(letter), count)
  end

  defp resolve_pattern_variants(nil), do: []
  defp resolve_pattern_variants(pattern) when is_binary(pattern), do: [pattern]

  defp resolve_pattern_variants(%{variant: variant, standard: standard})
       when is_binary(variant) and is_binary(standard),
       do: [variant, standard]

  defp resolve_pattern_variants(%{format: pattern}) when is_binary(pattern),
    do: [pattern]

  # Plural-variant maps (CLDR `availableFormats` ships some
  # week-bearing skeletons as `%{other: ..., one: ..., few:
  # ..., many: ..., zero: ..., two: ...}`). Dedupe binaries
  # across all variants.
  defp resolve_pattern_variants(%{} = map) do
    map
    |> Map.values()
    |> Enum.filter(&is_binary/1)
    |> Enum.uniq()
  end

  defp resolve_pattern_variants(_), do: []

  # ── Pattern → regex ──────────────────────────────────────────

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

  defp cldr_letter?(char) when char in ~w(y Y M d E G L c Q q w W D e F), do: true
  defp cldr_letter?(_), do: false

  defp compile_regex(tokens, months_data, eras_data, lenient, ctx) do
    parts = build_regex_parts(tokens, months_data, eras_data, lenient, "", ctx)
    "\\A" <> Enum.join(parts) <> "\\z"
  end

  # Build the list of regex fragments, inserting optional
  # whitespace between adjacent *field* tokens where the
  # pattern has no literal separator. This makes
  # `民國 115年5月16日` (with a space after the era marker)
  # parse under the CLDR pattern `Gy年M月d日`. Literal
  # separators in the pattern keep their natural-vs-lenient
  # equivalence — only the *empty* gap between fields is
  # relaxed.
  defp build_regex_parts(tokens, months_data, eras_data, lenient, prefix, ctx) do
    tokens
    |> Enum.reduce({[], nil}, fn token, {acc, prev_kind} ->
      {kind, regex} =
        case field_regex(token, months_data, eras_data, lenient, ctx) do
          {:capture, _name, regex} -> {:field, maybe_prefix_capture(regex, prefix)}
          {:plain, regex} -> {classify_plain(token), regex}
        end

      regex_with_gap =
        if prev_kind == :field and kind == :field do
          @space_class <> regex
        else
          regex
        end

      {[regex_with_gap | acc], kind}
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp classify_plain({:lit, _}), do: :literal
  defp classify_plain(_), do: :field

  defp maybe_prefix_capture(regex, ""), do: regex
  defp maybe_prefix_capture(regex, prefix), do: rename_capture(regex, prefix)

  defp field_regex({:lit, text}, _months, _eras, lenient, _ctx) do
    {:plain, expand_literal(text, lenient)}
  end

  defp field_regex({:y, count}, _months, _eras, _lenient, _ctx) do
    regex =
      case count do
        2 -> "(?P<year>\\d{2})"
        _ -> "(?P<year>\\d{1,4})"
      end

    {:capture, :year, regex}
  end

  # `Y` is the *week-based* year — used jointly with `w`
  # (week of year). Distinct named capture so the field
  # extractor can route it through the week-numbering
  # builder rather than the calendar-year builder.
  defp field_regex({:Y, count}, _months, _eras, _lenient, _ctx) do
    regex =
      case count do
        2 -> "(?P<week_based_year>\\d{2})"
        _ -> "(?P<week_based_year>\\d{1,4})"
      end

    {:capture, :week_based_year, regex}
  end

  defp field_regex({:M, count}, _months, _eras, _lenient, _ctx) when count <= 2 do
    {:capture, :month, "(?P<month>\\d{1,2})"}
  end

  defp field_regex({:M, count}, months, _eras, _lenient, _ctx) when count in 3..5 do
    {:capture, :month, month_name_regex(months, @month_name_widths[count])}
  end

  defp field_regex({:L, count}, months, eras, lenient, ctx),
    do: field_regex({:M, count}, months, eras, lenient, ctx)

  defp field_regex({:d, _count}, _months, _eras, _lenient, _ctx) do
    {:capture, :day, "(?P<day>\\d{1,2})"}
  end

  # `D` — day of year. 1..366 across the standard range.
  defp field_regex({:D, _count}, _months, _eras, _lenient, _ctx) do
    {:capture, :day_of_year, "(?P<day_of_year>\\d{1,3})"}
  end

  # `w` — week of year. 1..53.
  defp field_regex({:w, _count}, _months, _eras, _lenient, _ctx) do
    {:capture, :week_of_year, "(?P<week_of_year>\\d{1,2})"}
  end

  # `W` — week of month. 1..6.
  defp field_regex({:W, _count}, _months, _eras, _lenient, _ctx) do
    {:capture, :week_of_month, "(?P<week_of_month>\\d)"}
  end

  # `F` — day-of-week-in-month, e.g. "2nd Tuesday". The
  # numeric value alone (without an accompanying `E`) doesn't
  # uniquely identify a date; capture and surface to the
  # builder which combines it with month + weekday.
  defp field_regex({:F, _count}, _months, _eras, _lenient, _ctx) do
    {:capture, :day_of_week_in_month, "(?P<day_of_week_in_month>\\d)"}
  end

  # `e` — local day of week, format context. Width 1..2 is
  # numeric (in the locale's `firstDayOfWeek`-relative
  # numbering, so 1 = the locale's first day, not always
  # Monday). Width 3..6 matches the locale's day names.
  defp field_regex({:e, count}, _months, _eras, _lenient, _ctx) when count <= 2 do
    {:capture, :day_of_week_numeric, "(?P<day_of_week_numeric>\\d{1,2})"}
  end

  defp field_regex({:e, count}, _months, _eras, _lenient, ctx) when count in 3..6 do
    days_data = Map.get(ctx, :days)
    day_name_field(days_data, day_name_width(count), :format)
  end

  # `c` — standalone day of week. Same widths as `e`. `cc`
  # is not used in CLDR (singular `c` is rare too); fall
  # back to numeric on widths 1..2.
  defp field_regex({:c, count}, _months, _eras, _lenient, _ctx) when count <= 2 do
    {:capture, :day_of_week_numeric, "(?P<day_of_week_numeric>\\d{1,2})"}
  end

  defp field_regex({:c, count}, _months, _eras, _lenient, ctx) when count in 3..6 do
    days_data = Map.get(ctx, :days)
    day_name_field(days_data, day_name_width(count), :stand_alone)
  end

  # `E` — day of week (format context). Width 1..3 ⇒
  # abbreviated, 4 ⇒ wide, 5 ⇒ narrow, 6 ⇒ short. Captured
  # so the builder can validate the weekday matches the
  # constructed date.
  defp field_regex({:E, count}, _months, _eras, _lenient, ctx) do
    days_data = Map.get(ctx, :days)
    day_name_field(days_data, day_name_width(count), :format)
  end

  # `Q` / `q` — quarter (format / standalone). Widths 1..2
  # numeric, 3..4 names (e.g. "Q1" / "1st quarter"), 5 narrow.
  defp field_regex({letter, count}, _months, _eras, _lenient, _ctx)
       when letter in [:Q, :q] and count <= 2 do
    {:capture, :quarter, "(?P<quarter>\\d)"}
  end

  defp field_regex({letter, count}, _months, _eras, _lenient, ctx)
       when letter in [:Q, :q] and count in 3..5 do
    quarters_data = Map.get(ctx, :quarters)
    context = if letter == :Q, do: :format, else: :stand_alone
    quarter_name_field(quarters_data, quarter_name_width(count), context)
  end

  # Era marker. Try to capture against the locale's era names
  # so we can resolve era → year offset for Japanese imperial.
  # If no era names are available, fall back to tolerate-and-skip.
  defp field_regex({:G, count}, _months, eras, _lenient, _ctx) do
    width = Map.get(@era_widths, count, :abbreviated)

    case era_name_regex(eras, width) do
      {:branches, regex} -> {:capture, :era, regex}
      :none -> {:plain, "[\\p{L}\\.]+"}
    end
  end

  defp expand_literal(text, lenient) do
    text
    |> String.graphemes()
    |> Enum.map_join(&expand_char(&1, lenient))
  end

  defp expand_char(char, lenient) do
    cond do
      space_char?(char) ->
        # A literal space in the CLDR pattern requires at least
        # one whitespace character in the input. Inter-field
        # gaps (with no pattern literal between them) use the
        # `*` form via `@space_class` elsewhere.
        @literal_space_class

      char == "," ->
        # CLDR patterns embed `,` as a structural punctuation
        # marker (e.g., `MMM d, y` between day and year), but
        # informal input routinely drops it (`"May 5 2026"`).
        # Make every literal comma optional in the compiled
        # regex; the surrounding space-class still requires at
        # least one whitespace char, so `"May d,y"` (comma but
        # no space) still won't false-match.
        ",?"

      char in @dash_chars ->
        # Union @dash_chars with any CLDR lenient equivalence
        # for this char (en's `-` already maps to `[. /]` via
        # `lenient-scope-date`). En-dash and friends inherit the
        # same date-component leniency by being in the same
        # class.
        cldr_class = Map.get(lenient, char, [char])
        combined = Enum.uniq(@dash_chars ++ cldr_class)
        "[" <> Enum.map_join(combined, &Regex.escape/1) <> "]"

      true ->
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

  defp month_name_regex(months_data, _declared_width) do
    # CLDR TR35 §6.5 (lenient parsing): the pattern declares a
    # width (`MMM` = abbreviated, `MMMM` = wide), but real-world
    # input may use any of them. We accept both wide and
    # abbreviated names regardless of the pattern's declared
    # width. Narrow forms are deliberately excluded — they're
    # single-letter display forms (en's `:narrow` is "J" for both
    # January and June), useless for parsing.
    #
    # Each index gets exactly ONE named capture group, with
    # internal alternation across the widths' name forms.
    # Duplicate names across widths (en's "May" is the same in
    # both) are deduplicated. Longest-form-first inside the group
    # so the regex prefers `"June"` over `"Jun"` when both could
    # match a prefix of input.
    by_index =
      [:wide, :abbreviated]
      |> Enum.flat_map(fn width ->
        names =
          get_in(months_data, [:format, width]) ||
            get_in(months_data, [:stand_alone, width]) ||
            %{}

        Enum.map(names, fn {index, name} -> {index, name, width} end)
      end)
      |> Enum.group_by(fn {index, _name, _w} -> index end, fn {_index, name, w} -> {name, w} end)

    branches =
      by_index
      |> Enum.map(fn {index, name_widths} ->
        forms =
          name_widths
          |> Enum.uniq_by(fn {name, _w} -> name end)
          |> Enum.sort_by(fn {name, _w} -> -byte_size(name) end)
          |> Enum.map_join("|", &name_form/1)

        "(?P<__m#{index}__>#{forms})"
      end)

    # `(?i:...)` per CLDR TR35 §6.5 — month-name matching is
    # case-insensitive, so French "Mai" matches lowercase "mai"
    # in CLDR data, English "MAY" matches "May", etc.
    "(?i:" <> Enum.join(branches, "|") <> ")"
  end

  # The literal form one branch contributes to the alternation
  # inside its month's capture group. Abbreviated names may carry
  # a trailing `.` in some locales (fr's `"janv."`); we trim and
  # then make the period optional so both `"janv"` and `"janv."`
  # match. Wide names go in verbatim.
  defp name_form({name, :abbreviated}) do
    Regex.escape(String.trim_trailing(name, ".")) <> "\\.?"
  end

  defp name_form({name, _width}), do: Regex.escape(name)

  defp era_name_regex(eras_data, width) when is_map(eras_data) do
    names =
      eras_data
      |> get_era_names_for_width(width)

    if Enum.empty?(names) do
      :none
    else
      branches =
        names
        |> Enum.sort_by(fn {_index, name} -> -byte_size(name) end)
        |> Enum.map(fn {index, name} -> "(?P<__e#{index}__>#{Regex.escape(name)})" end)

      {:branches, "(?i:" <> Enum.join(branches, "|") <> ")"}
    end
  end

  # `Localize.Calendar.eras/2` returns `%{width => %{index =>
  # name}}` — top-level keys are width atoms (`:wide`,
  # `:abbreviated`, `:narrow`), inner maps are
  # `era_index => era_name`.
  defp get_era_names_for_width(eras_data, width) do
    inner = Map.get(eras_data, width) || Map.get(eras_data, :abbreviated) || %{}

    Enum.flat_map(inner, fn
      {index, name} when is_integer(index) and is_binary(name) -> [{index, name}]
      _ -> []
    end)
  end

  # CLDR width map for `E`/`e`/`c` letters.
  defp day_name_width(1), do: :abbreviated
  defp day_name_width(2), do: :abbreviated
  defp day_name_width(3), do: :abbreviated
  defp day_name_width(4), do: :wide
  defp day_name_width(5), do: :narrow
  defp day_name_width(6), do: :short
  defp day_name_width(_), do: :abbreviated

  # CLDR width map for `Q`/`q` letters.
  defp quarter_name_width(3), do: :abbreviated
  defp quarter_name_width(4), do: :wide
  defp quarter_name_width(5), do: :narrow
  defp quarter_name_width(_), do: :abbreviated

  # Build a regex branch for day-of-week names. Capture the
  # ISO weekday index (1 = Monday … 7 = Sunday) so the
  # builder can validate or derive a date from it.
  defp day_name_field(days_data, width, context) when is_map(days_data) do
    inner =
      get_in(days_data, [context, width]) ||
        get_in(days_data, [:format, width]) ||
        %{}

    branches =
      inner
      |> Enum.filter(fn
        {index, name} when is_integer(index) and is_binary(name) -> true
        _ -> false
      end)
      |> Enum.sort_by(fn {_index, name} -> -byte_size(name) end)
      |> Enum.map(fn {index, name} ->
        "(?P<__d#{index}__>#{Regex.escape(name)})"
      end)

    case branches do
      [] -> {:plain, "[\\p{L}\\.]+"}
      _ -> {:capture, :day_of_week, "(?i:" <> Enum.join(branches, "|") <> ")"}
    end
  end

  defp day_name_field(_data, _width, _context),
    do: {:plain, "[\\p{L}\\.]+"}

  # Build a regex branch for quarter names. Capture the
  # quarter index 1..4 so the builder can derive the
  # quarter's first month.
  defp quarter_name_field(quarters_data, width, context) when is_map(quarters_data) do
    inner =
      get_in(quarters_data, [context, width]) ||
        get_in(quarters_data, [:format, width]) ||
        %{}

    branches =
      inner
      |> Enum.filter(fn
        {index, name} when is_integer(index) and is_binary(name) -> true
        _ -> false
      end)
      |> Enum.sort_by(fn {_index, name} -> -byte_size(name) end)
      |> Enum.map(fn {index, name} ->
        "(?P<__q#{index}__>#{Regex.escape(name)})"
      end)

    case branches do
      [] -> {:plain, "[\\p{L}\\d\\.\\s]+?"}
      _ -> {:capture, :quarter, "(?i:" <> Enum.join(branches, "|") <> ")"}
    end
  end

  defp quarter_name_field(_data, _width, _context),
    do: {:plain, "[\\p{L}\\d\\.\\s]+?"}

  # ── Matching ─────────────────────────────────────────────────

  # `ctx` carries the per-(locale, calendar) invariants built
  # once in `try_locale_patterns/6`: `:months`, `:eras`,
  # `:lenient`, `:reference_year`, `:calendar_module`,
  # `:cldr_calendar`, plus the `:days`/`:quarters`/`:locale`
  # keys read by `field_regex/5`.
  # Returns %{pattern => compiled_regex_or_nil} for every pattern, cached
  # in :persistent_term keyed by {locale, calendar}. One write per cold
  # (locale, calendar); every later parse reads precompiled regexes.
  defp pattern_regexes(patterns, ctx) do
    key = {__MODULE__, :pattern_regexes, ctx.locale, ctx.cldr_calendar}

    case :persistent_term.get(key, nil) do
      nil ->
        compiled =
          Map.new(patterns, fn {_kind, pattern} ->
            {pattern, build_pattern_regex(pattern, ctx)}
          end)

        :persistent_term.put(key, compiled)
        compiled

      compiled ->
        compiled
    end
  end

  defp build_pattern_regex(pattern, ctx) do
    tokens = tokenize_pattern(pattern)
    regex_string = compile_regex(tokens, ctx.months, ctx.eras, ctx.lenient, ctx)

    case Regex.compile(regex_string, "u") do
      {:ok, regex} -> regex
      {:error, _} -> nil
    end
  end

  defp match_pattern(input, pattern, ctx, as) do
    regex = Map.get(ctx.regexes, pattern)
    year_fallback = year_fallback_for(as, ctx.reference_year)

    with %Regex{} <- regex,
         %{} = caps <- Regex.named_captures(regex, input),
         {:ok, era_index} <- extract_era(caps),
         {:ok, fields} <-
           extract_fields(caps, year_fallback, ctx.cldr_calendar, era_index, ctx.calendar_module) do
      match_result_for(as, fields, caps, ctx.calendar_module)
    else
      _ -> :error
    end
  end

  # Year fallback semantics by mode:
  #
  # * `:struct` and `{:map, :strict}` use `reference_year`
  #   so `build_date_smart` has enough to construct a date.
  #   In `{:map, :strict}` the fallback year is stripped
  #   from the output map after the fact when the user
  #   didn't actually type one.
  #
  # * `{:map, :lax}` uses `nil` — pass-2 inputs like
  #   `"2026"` alone or `"May"` alone never construct a
  #   date and the caller wants what was captured, nothing
  #   synthesised.
  defp year_fallback_for({:map, :lax}, _reference_year), do: nil
  defp year_fallback_for(_as, reference_year), do: reference_year

  defp match_result_for(:struct, fields, _caps, calendar_module) do
    build_date_smart(fields, calendar_module)
  end

  defp match_result_for({:map, :strict}, fields, caps, calendar_module) do
    case build_date_smart(fields, calendar_module) do
      {:ok, _date} -> {:ok, strict_map(fields, caps, calendar_module)}
      :error -> :error
    end
  end

  defp match_result_for({:map, :lax}, fields, _caps, calendar_module) do
    {:ok, fields_to_map(fields, calendar_module)}
  end

  # Strict-pass map output: drop `:year` when it was supplied
  # by the reference-year fallback rather than the input. This
  # is what makes `"May 5"` come back as `%{month: 5, day: 5}`
  # instead of `%{month: 5, day: 5, year: <today's year>}`.
  defp strict_map(fields, caps, calendar_module) do
    map = fields_to_map(fields, calendar_module)

    if year_captured?(caps) do
      map
    else
      Map.delete(map, :year)
    end
  end

  defp year_captured?(caps) do
    non_empty?(caps, "year") or non_empty?(caps, "week_based_year")
  end

  defp non_empty?(caps, key) do
    case Map.get(caps, key) do
      v when is_binary(v) and v != "" -> true
      _ -> false
    end
  end

  # Strip nil-valued and internal-use keys, surface the
  # resolved calendar module. Output is the public shape
  # documented for `as: :map`.
  defp fields_to_map(fields, calendar_module) do
    keys = [
      :year,
      :month,
      :day,
      :quarter,
      :week_of_year,
      :week_of_month,
      :week_based_year,
      :day_of_year,
      :day_of_week,
      :day_of_week_in_month
    ]

    Enum.reduce(keys, %{calendar: calendar_module}, fn key, acc ->
      case Map.get(fields, key) do
        nil -> acc
        value -> Map.put(acc, key, value)
      end
    end)
  end

  # Pull every field the parser knows about into a single
  # struct so `build_date_smart` can pick a reconstruction
  # strategy. Most patterns supply only a subset; the
  # strategy table below resolves which combination yields a
  # full Date.
  defp extract_fields(caps, reference_year, cldr_calendar, era_index, calendar_module) do
    with {:ok, year_in_calendar} <-
           extract_year_field(caps, reference_year, cldr_calendar),
         {:ok, calendar_year} <-
           resolve_calendar_year(year_in_calendar, era_index, cldr_calendar) do
      {:ok,
       %{
         year: calendar_year,
         month: extract_optional_month(caps),
         day: extract_optional_day(caps),
         quarter: extract_optional_quarter(caps),
         week_of_year: extract_optional_int(caps, "week_of_year"),
         week_of_month: extract_optional_int(caps, "week_of_month"),
         week_based_year: extract_optional_int(caps, "week_based_year"),
         day_of_year: extract_optional_int(caps, "day_of_year"),
         day_of_week: extract_optional_day_of_week(caps),
         day_of_week_in_month: extract_optional_int(caps, "day_of_week_in_month"),
         weekday_name_index: extract_optional_weekday_name(caps),
         calendar_module: calendar_module,
         cldr_calendar: cldr_calendar
       }}
    end
  end

  # The 2-digit-year pivot is a Gregorian convention. For era-
  # aware calendars (Japanese imperial, ROC, etc.) the year
  # value is meant literally (`平成12年` = Heisei year 12,
  # not "the year '12 ≈ 2012"), so pivoting would corrupt the
  # input.
  # Year field is required by `extract_fields`. Falls back to
  # `year_fallback` when no `y`/`Y` was captured: in `:struct`
  # mode this is the reference year (so patterns like `MMM d`
  # parse against the current year); in `:map` mode it's `nil`
  # (so the year stays absent from the result map).
  defp extract_year_field(caps, year_fallback, cldr_calendar) do
    case Map.get(caps, "year") || Map.get(caps, "week_based_year") do
      raw when is_binary(raw) and raw != "" ->
        case Integer.parse(raw) do
          {n, ""} ->
            reference_year = year_fallback || Date.utc_today().year
            {:ok, maybe_pivot_two_digit_year(n, raw, reference_year, cldr_calendar)}

          _ ->
            :error
        end

      _ ->
        {:ok, year_fallback}
    end
  end

  defp pivot_year(two_digit, reference_year) do
    century_base = div(reference_year - 80, 100) * 100
    candidate = century_base + two_digit
    if candidate < reference_year - 80, do: candidate + 100, else: candidate
  end

  defp extract_optional_month(%{"month" => raw}) when raw != "" do
    case Integer.parse(raw) do
      {n, ""} when n in 1..13 -> n
      _ -> nil
    end
  end

  defp extract_optional_month(caps) do
    case named_capture_index(caps, "__m") do
      n when is_integer(n) and n in 1..13 -> n
      _ -> nil
    end
  end

  defp extract_optional_day(%{"day" => raw}) when raw != "" do
    case Integer.parse(raw) do
      {n, ""} when n in 1..31 -> n
      _ -> nil
    end
  end

  defp extract_optional_day(_), do: nil

  # Quarter capture comes in two flavors: numeric capture
  # under `quarter`, or one of the named branches
  # `__q1__` / `__q2__` / `__q3__` / `__q4__`. Return
  # 1..4 or `nil`.
  defp extract_optional_quarter(caps) do
    case Map.get(caps, "quarter") do
      raw when is_binary(raw) and raw != "" ->
        case Integer.parse(raw) do
          {n, ""} when n in 1..4 -> n
          _ -> nil
        end

      _ ->
        extract_quarter_by_name(caps)
    end
  end

  defp extract_quarter_by_name(caps) do
    case named_capture_index(caps, "__q") do
      n when is_integer(n) and n in 1..4 -> n
      _ -> nil
    end
  end

  defp extract_optional_int(caps, key) do
    case Map.get(caps, key) do
      raw when is_binary(raw) and raw != "" ->
        case Integer.parse(raw) do
          {n, ""} -> n
          _ -> nil
        end

      _ ->
        nil
    end
  end

  # Day-of-week from numeric or name capture. Returns ISO
  # weekday 1..7 (Mon..Sun) or `nil`.
  defp extract_optional_day_of_week(caps) do
    if raw = Map.get(caps, "day_of_week_numeric") do
      parse_numeric_day_of_week(raw)
    else
      extract_day_of_week_by_name(caps)
    end
  end

  defp parse_numeric_day_of_week(raw) do
    case raw do
      "" ->
        nil

      binary when is_binary(binary) ->
        case Integer.parse(binary) do
          {n, ""} when n in 1..7 -> n
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp extract_day_of_week_by_name(caps) do
    case named_capture_index(caps, "__d") do
      n when is_integer(n) and n in 1..7 -> n
      _ -> nil
    end
  end

  # When an `E`/`c` weekday-name capture appears WITH a full
  # year/month/day, the parser should validate the supplied
  # weekday matches the computed date. Return the captured
  # weekday index (1..7) for the builder to check.
  defp extract_optional_weekday_name(caps) do
    case named_capture_index(caps, "__d") do
      n when is_integer(n) and n in 1..7 -> n
      _ -> nil
    end
  end

  defp extract_era(caps) do
    {:ok, named_capture_index(caps, "__e")}
  end

  # Find the first non-empty capture named `<marker><N>__`
  # (the `__mN__` / `__qN__` / `__dN__` / `__eN__` named
  # branches compiled by the name-based field regexes) and
  # return the integer index `N`, or `nil` when no such
  # capture matched.
  defp named_capture_index(caps, marker) do
    with {key, _value} <-
           Enum.find(caps, fn
             {key, value} -> String.starts_with?(key, marker) and value != ""
             _ -> false
           end),
         [index_str, _] <-
           key |> String.replace_prefix(marker, "") |> String.split("__", parts: 2),
         {n, ""} <- Integer.parse(index_str) do
      n
    else
      _ -> nil
    end
  end

  # When no year was captured (only possible in `:map` mode),
  # there's nothing to resolve — era arithmetic is moot.
  defp resolve_calendar_year(nil, _era_index, _calendar), do: {:ok, nil}

  # For Japanese imperial dates, the parsed `year` is the
  # year-within-era, not the Gregorian year. Convert using
  # the era's start date from CLDR supplemental data.
  defp resolve_calendar_year(year, era_index, :japanese) when is_integer(era_index) do
    case japanese_era_start_year(era_index) do
      {:ok, start_year} -> {:ok, start_year + year - 1}
      :error -> {:error, :unknown_era}
    end
  end

  # For other era-aware calendars (Islamic, Hebrew, etc.), the
  # year in input IS the calendar's year — no era arithmetic
  # needed. The era marker is presentational.
  defp resolve_calendar_year(year, _era_index, _calendar), do: {:ok, year}

  defp japanese_era_start_year(era_index) do
    case Localize.SupplementalData.calendars()
         |> get_in([:japanese, :eras]) do
      eras when is_list(eras) ->
        case Enum.find(eras, fn [idx, _] -> idx == era_index end) do
          [_idx, %{start: [year, _m, _d]}] -> {:ok, year}
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp build_date(year, month, day, Calendar.ISO) do
    case Date.new(year, month, day) do
      {:ok, date} -> {:ok, date}
      {:error, _} -> :error
    end
  end

  defp build_date(year, month, day, calendar_module) do
    case Date.new(year, month, day, calendar_module) do
      {:ok, date} -> {:ok, date}
      {:error, _} -> :error
    end
  end

  # Pick a reconstruction strategy based on which fields the
  # pattern supplied. Strategies are ordered most-specific
  # first so partial-field patterns (e.g. `yQQQ` with no
  # month or day) don't get clobbered by a strategy that
  # demands fields they don't have. Day-bearing strategies
  # are tried here; week-only and quarter strategies live in
  # `build_date_from_week_or_quarter/2`, tried in the same
  # overall order as before the split.
  defp build_date_smart(fields, calendar_module) do
    cond do
      # Year + month + day given → standard path. Validate
      # weekday if also supplied.
      has_year_month_day?(fields) ->
        build_from_year_month_day(fields, calendar_module)

      # Year + day-of-year → date by adding (D-1) days to
      # Jan 1 of that year.
      has_year_day_of_year?(fields) ->
        build_from_day_of_year(fields, calendar_module)

      # Week-based year + week of year + day of week → the
      # exact date.
      has_week_based_year_week_day?(fields) ->
        build_from_iso_week_date(fields, calendar_module)

      # Year + week of year + day of week — treat year as
      # week-based year. Common shape: `Y w E`.
      has_year_week_day?(fields) ->
        build_from_year_as_week_year(fields, calendar_module)

      true ->
        build_date_from_week_or_quarter(fields, calendar_module)
    end
  end

  # Week-only and quarter strategies — the tail of the
  # strategy table started in `build_date_smart/2`.
  defp build_date_from_week_or_quarter(fields, calendar_module) do
    cond do
      # Year + week of year only → first day of that week.
      has_year_week?(fields) ->
        date_from_iso_week(fields.year, fields.week_of_year, 1, calendar_module)

      has_week_based_year_week?(fields) ->
        date_from_iso_week(fields.week_based_year, fields.week_of_year, 1, calendar_module)

      # Year + month + day-of-week-in-month → e.g. 2nd
      # Tuesday of June.
      has_nth_weekday_of_month?(fields) ->
        build_from_nth_weekday(fields, calendar_module)

      # Year + quarter (no month) → first day of quarter.
      # Reasonable default for `yQQQ` skeletons.
      has_year_quarter?(fields) ->
        build_from_quarter(fields, calendar_module)

      true ->
        :error
    end
  end

  # Strategy predicates — verbatim truthiness checks from the
  # original strategy table (fields are integers or nil).

  defp has_year_month_day?(fields), do: fields.year && fields.month && fields.day

  defp has_year_day_of_year?(fields), do: fields.year && fields.day_of_year

  defp has_week_based_year_week_day?(fields) do
    fields.week_based_year && fields.week_of_year && fields.day_of_week
  end

  defp has_year_week_day?(fields) do
    fields.year && fields.week_of_year && fields.day_of_week
  end

  defp has_year_week?(fields), do: fields.year && fields.week_of_year

  defp has_week_based_year_week?(fields), do: fields.week_based_year && fields.week_of_year

  defp has_nth_weekday_of_month?(fields) do
    fields.year && fields.month && fields.day_of_week && fields.day_of_week_in_month
  end

  defp has_year_quarter?(fields), do: fields.year && fields.quarter

  # Strategy bodies.

  defp build_from_year_month_day(fields, calendar_module) do
    with {:ok, date} <- build_date(fields.year, fields.month, fields.day, calendar_module) do
      validate_weekday(date, fields)
    end
  end

  defp build_from_day_of_year(fields, calendar_module) do
    with {:ok, jan1} <- build_date(fields.year, 1, 1, calendar_module),
         %Date{} = date <- Date.add(jan1, fields.day_of_year - 1) do
      {:ok, date}
    else
      _ -> :error
    end
  end

  defp build_from_iso_week_date(fields, calendar_module) do
    date_from_iso_week(
      fields.week_based_year,
      fields.week_of_year,
      fields.day_of_week,
      calendar_module
    )
  end

  defp build_from_year_as_week_year(fields, calendar_module) do
    date_from_iso_week(
      fields.year,
      fields.week_of_year,
      fields.day_of_week,
      calendar_module
    )
  end

  defp build_from_nth_weekday(fields, calendar_module) do
    date_from_nth_weekday(
      fields.year,
      fields.month,
      fields.day_of_week,
      fields.day_of_week_in_month,
      calendar_module
    )
  end

  defp build_from_quarter(fields, calendar_module) do
    month = (fields.quarter - 1) * 3 + 1
    build_date(fields.year, month, 1, calendar_module)
  end

  # Verify the `E`/`c` weekday name (if any was captured)
  # matches the date's actual weekday. Mismatch → :error so
  # the parser backtracks to try a different pattern.
  defp validate_weekday(date, %{day_of_week: nil, weekday_name_index: nil}), do: {:ok, date}

  defp validate_weekday(date, %{day_of_week: nil, weekday_name_index: idx})
       when is_integer(idx) do
    if Date.day_of_week(date) == idx, do: {:ok, date}, else: :error
  end

  defp validate_weekday(date, %{day_of_week: dow}) when is_integer(dow) do
    if Date.day_of_week(date) == dow, do: {:ok, date}, else: :error
  end

  # Build a date from ISO 8601 week numbering (week 1 is the
  # week containing Jan 4). Compute in `Calendar.ISO` then
  # convert to the target calendar so we don't need
  # per-calendar week algorithms.
  defp date_from_iso_week(year, week, day_of_week, calendar_module)
       when week in 1..53 and day_of_week in 1..7 do
    case Date.new(year, 1, 4) do
      {:ok, jan4} ->
        jan4_dow = Date.day_of_week(jan4)
        week1_monday = Date.add(jan4, -(jan4_dow - 1))
        target = Date.add(week1_monday, (week - 1) * 7 + (day_of_week - 1))

        if calendar_module == Calendar.ISO do
          {:ok, target}
        else
          case Date.convert(target, calendar_module) do
            {:ok, converted} -> {:ok, converted}
            _ -> :error
          end
        end

      _ ->
        :error
    end
  end

  defp date_from_iso_week(_, _, _, _), do: :error

  # Compute the Nth occurrence of `weekday` in `month` of
  # `year`. N is 1..5; if N exceeds the month's count of
  # that weekday, return :error.
  defp date_from_nth_weekday(year, month, weekday, n, calendar_module)
       when weekday in 1..7 and n in 1..5 do
    with {:ok, first_of_month} <- build_date(year, month, 1, calendar_module),
         first_dow = Date.day_of_week(first_of_month),
         offset_to_first_occurrence = rem(weekday - first_dow + 7, 7),
         day_number = offset_to_first_occurrence + 1 + (n - 1) * 7,
         {:ok, candidate} <- build_date(year, month, day_number, calendar_module) do
      {:ok, candidate}
    else
      _ -> :error
    end
  end

  defp date_from_nth_weekday(_, _, _, _, _), do: :error

  # ── Errors ───────────────────────────────────────────────────

  defp no_match_error(input, locale, calendar) do
    DateParseError.exception(input: input, locale: locale, calendar: calendar)
  end
end
