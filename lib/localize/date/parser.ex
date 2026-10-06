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
  # * A format of the calendar asked for, for text ISO 8601 also reads
  # (`r-MM-dd`, the Chinese calendar's short date in CLDR's root, writes
  # "2023-11-22"). A calendar's own formats come first, any of them and
  # read as leniently as below, so such text is that calendar's date
  # wherever one of its formats reads it, and reads back as the date it
  # was written from. `Calendar.ISO`'s own notation is ISO 8601.
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
  # Where `:format` names the format the text was written with, the
  # text is read with that format alone, after the calendar's own
  # notation: neither ISO 8601 nor another of the locale's formats is
  # tried, since a skeleton may write its fields in another order than
  # the standard formats do (`mt`'s `yMd` is "M/d/y" beside a short
  # date of "dd/MM/y").
  #
  # ### Calendars
  #
  # The `:calendar` option is a calendar module, `Calendar.ISO` by
  # default or one answering the Calendrical behaviour, and the date
  # comes back in it. The input is read with the patterns of the
  # calendar's CLDR type, in the calendar its `parsing_calendar/0`
  # names: itself, or `Calendar.ISO` for a calendar of weeks, whose
  # dates are then converted. A calendar of weeks' own notation, as the
  # formatter writes it ("2026-W25-2"), is read back by the calendar's
  # `parse_date/1`. The calendar's answers place everything
  # else: its months (`month_of_year/3`, `cardinal_month/1`), the
  # years of its eras, and its own weeks and quarters (`week/2`,
  # `quarter/2`), counted in the calendar asked for.
  #
  # ### Lenient matching
  #
  # * `dd` and `MM` accept 1–2 digits (so `3/4/26` parses
  # under `en-GB`'s `dd/MM/y`).
  #
  # * Any 2-digit typed year pivots into the 80-back/20-forward
  # window relative to the reference year, the year of the
  # reference date in the calendar the input is read in
  # (overridable via `:reference_date`).
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
  # A pattern that writes its fields in another numbering
  # reads them in it: `ja`'s Chinese calendar writes 16 as
  # 一六 (`hanidec`) and `zh`'s writes day 21 as 廿一
  # (`hanidays`).
  #
  # ### Lunisolar dates
  #
  # A lunisolar date is read as the formatter writes it: its
  # related Gregorian year (`r`), its cyclic year name (`U`,
  # the year of that name nearest the reference year), a leap
  # month in the locale's leap-month pattern ("Mo2bis",
  # "闰二月", "2bis"), and a month written as a number as its
  # traditional number. Where a locale writes the year both as
  # the calendar's year and as the related year, the reading
  # nearer the reference year is taken.
  #
  # ### Era handling
  #
  # For era-aware calendars (Japanese imperial, Islamic Hijri,
  # ROC, etc.), the `G` field in CLDR patterns marks the era
  # marker (`平成`, `هـ`, `AH`, `BCE`, `民國`). The parser
  # captures the era name, resolves it via
  # `Localize.Calendar.eras/2`, and computes the calendar-year
  # from the year of that era: from the era's start year in
  # the Japanese calendar, and in any other as the year the
  # formatter writes that way, so "1 BC" is year 0. A year
  # its era qualifies is taken as written, never pivoted.
  # Era names come from the calendar's `era_calendar_type/0`
  # where it has one, and in a calendar that writes its
  # years as years of an era, a year written without one is
  # of the reference date's era, as ICU reads it.
  #

  alias Localize.Calendar, as: LCalendar
  alias Localize.DateParseError
  alias Localize.DateRangeParseError
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
    read_for_calendar(options, &do_parse(input, &1, &2), &finalise_date/2)
  end

  defp do_parse(input, options, calendar_module) do
    locale = Keyword.get(options, :locale) || Localize.get_locale()
    reference = reference_date(options, calendar_module)
    own_calendar = own_calendar(options, calendar_module)
    as = Keyword.get(options, :as, :struct)

    normalised = normalise_input(input)
    candidates = Enum.uniq([normalised, preprocess_safe(normalised, locale, calendar_module)])
    reading = {locale, calendar_module, own_calendar, reference}

    attempt =
      case Keyword.get(options, :format) do
        nil -> &read_in_any_format(&1, reading, as)
        format -> &read_in_format(&1, format, options, reading, as)
      end

    case attempt.(candidates) do
      {:ok, _} = ok ->
        ok

      {:error, _} = err ->
        retry_without_ordinal_affixes(attempt, candidates, locale, err)
    end
  end

  # The input as its calendar's notation, in one of the calendar's own
  # formats or as ISO 8601 writes a date, and else in whichever of the
  # locale's patterns reads it first.
  defp read_in_any_format(inputs, {locale, calendar_module, own_calendar, reference}, as) do
    own_format = &own_format_reading(&1, locale, calendar_module, own_calendar, reference)

    case Enum.find_value(inputs, &written_date(&1, calendar_module, own_calendar, own_format)) do
      {:ok, date} ->
        {:ok, finalise_date(date, as)}

      {:error, _exception} = error ->
        error

      nil ->
        # ISO 8601 at reduced precision is the whole of the input as it was
        # given: with a leading weekday stripped, `es`'s "mar 2024", March or
        # a Tuesday, would be the year 2024.
        given = hd(inputs)

        iso_week(given, calendar_module, as) || iso_year_or_month(given, calendar_module, as) ||
          try_locale_patterns(inputs, locale, calendar_module, own_calendar, reference, as)
    end
  end

  # `YYYY-MM` and `YYYY`, ISO 8601's month and year at reduced precision.
  # Neither is a date, so they are read only as the fields they hold, and
  # only in `Calendar.ISO`, whose notation ISO 8601 is: a year and a month
  # of it are no fields of another calendar. They are read so in every
  # locale, where a locale's own patterns read one or the other.
  defp iso_year_or_month(input, Calendar.ISO, :map) do
    case Regex.run(~r/\A(\d{4})(?:-(0[1-9]|1[0-2]))?\z/, input) do
      [_, year] ->
        {:ok, %{calendar: Calendar.ISO, year: String.to_integer(year)}}

      [_, year, month] ->
        {:ok,
         %{calendar: Calendar.ISO, year: String.to_integer(year), month: String.to_integer(month)}}

      nil ->
        nil
    end
  end

  defp iso_year_or_month(_input, _calendar_module, _as), do: nil

  # `YYYY-Www` and `YYYYWww`, ISO 8601's week at reduced precision: the week
  # of that number in ISO 8601's weeks, from Monday and with at least four
  # days of the year, whatever the weeks of the locale or of the calendar
  # asked for, as an ISO 8601 week date is. It names no day, so as a date it
  # is the week's first day, in the calendar asked for, and as a map in
  # `Calendar.ISO`, whose notation ISO 8601 is, its week-based year and week.
  # A week the year does not have is no week.
  defp iso_week(input, calendar_module, as) do
    with [_, y, w] <- Regex.run(~r/\A(\d{4})-?W(\d{2})\z/, input),
         {year, ""} <- Integer.parse(y),
         {week, ""} <- Integer.parse(w),
         %Date.Range{first: monday} <- Localize.Calendar.ISO.week(year, week) do
      iso_week_value(monday, {year, week}, calendar_module, as)
    else
      _not_a_week -> nil
    end
  end

  defp iso_week_value(_monday, {year, week}, Calendar.ISO, :map) do
    {:ok, %{calendar: Calendar.ISO, year: year, week_based_year: year, week_of_year: week}}
  end

  defp iso_week_value(monday, _year_and_week, calendar_module, as) do
    with {:ok, date} <- in_calendar(monday, calendar_module) do
      {:ok, finalise_date(date, as)}
    end
  end

  # The input in the format it was written with, which `:format` names as
  # it names the format `Localize.Date.to_string/2` writes with: a standard
  # format, a skeleton or a pattern. The text is read with that format and
  # no other, so a date a skeleton writes against the field order of the
  # standard formats reads back: `my`'s Japanese `GyMd` is "GGGGG y/M/d"
  # beside a short date of "GGGGG d/M/y", and "Kanpō 2/6/1" is either (user,
  # 2026-10-04: "Let parse/2 take the format the text was written with"). A
  # calendar's own notation, which every standard format writes for a
  # calendar of weeks, is read before it.
  defp read_in_format(inputs, format, options, reading, as) do
    {_locale, calendar_module, own_calendar, _reference} = reading

    case Enum.find_value(inputs, &notation_date(&1, calendar_module, own_calendar)) do
      {:ok, date} -> {:ok, finalise_date(date, as)}
      {:error, _exception} = error -> error
      nil -> try_format(inputs, format, options, reading, as)
    end
  end

  defp notation_date(input, calendar_module, own_calendar) do
    case Localize.Calendar.from_notation(input, own_calendar) do
      {:ok, date} -> in_calendar(date, calendar_module)
      :none -> nil
      {:error, _exception} = error -> error
    end
  end

  defp try_format(inputs, format, options, reading, as) do
    {locale, calendar_module, own_calendar, reference} = reading

    with {:ok, pattern} <- format_pattern(format, options, reading),
         {:ok, _patterns, ctx} <-
           locale_patterns(locale, calendar_module, own_calendar, reference) do
      # One format reads the text, so an era's narrow name is read whatever
      # width the format states (`narrow_era_branches/2`).
      ctx = %{
        ctx
        | regexes: %{pattern => build_pattern_regex(pattern, ctx)},
          mixed_years: false,
          narrow_eras: true
      }

      transliterated = inputs |> Enum.map(&transliterate_digits(&1, locale)) |> Enum.uniq()

      read_patterns([{:format, pattern}], transliterated, ctx, as) ||
        {:error,
         DateParseError.exception(
           input: hd(inputs),
           locale: locale,
           calendar: calendar_module,
           format: format
         )}
    end
  end

  # The pattern a format resolves to in the calendar the text is read in, as
  # `Localize.Date.to_string/2` resolves it for a whole date, with the
  # numbering the locale writes its fields in. A string is a pattern as it
  # stands, and must be one the formatter writes a date with: a quote left
  # open, a letter that is no field of a date and a field longer than any
  # format writes, which the formatter writes as U+FFFD, are each an error
  # rather than a format nothing matches.
  defp format_pattern(format, _options, {locale, calendar_module, _own_calendar, reference})
       when is_binary(format) do
    whole_date = whole_date(calendar_module, reference)

    with {:ok, locale_id} <- Localize.Locale.cldr_locale_id_from(locale),
         {:ok, written} <-
           Localize.DateTime.Formatter.format(whole_date, format, locale_id, %{locale: locale}) do
      if String.contains?(written, "�"),
        do:
          {:error,
           Localize.DateTimeFormatError.exception(format: format, reason: :invalid_format)},
        else: {:ok, format}
    end
  end

  defp format_pattern(format, options, {locale, calendar_module, _own_calendar, reference}) do
    whole_date = whole_date(calendar_module, reference)

    with {:ok, locale_id} <- Localize.Locale.cldr_locale_id_from(locale),
         {:ok, pattern, numbers} <-
           Localize.Date.resolve_pattern_and_numbers(whole_date, format, locale_id, options) do
      if map_size(numbers) == 0, do: {:ok, pattern}, else: {:ok, {pattern, numbers}}
    end
  end

  # A whole date of the calendar the text is read in, which a format is
  # resolved for: the reference date, or the first day of its year where it
  # holds no more than a year.
  defp whole_date(calendar_module, reference) do
    %{
      calendar: calendar_module,
      year: reference.year,
      month: Map.get(reference, :month, 1),
      day: Map.get(reference, :day, 1)
    }
  end

  # A date written in the notation of the calendar asked for, as the
  # formatter writes a calendar of weeks' date ("2026-W25-2"), read back by
  # that calendar and taken into the calendar the input is read in; else a
  # date in one of the calendar's own formats (`own_format`), which come
  # before ISO 8601; else an ISO 8601 date.
  defp written_date(input, calendar_module, own_calendar, own_format) do
    case Localize.Calendar.from_notation(input, own_calendar) do
      {:ok, date} -> in_calendar(date, calendar_module)
      :none -> own_format.(input) || iso_date(input, calendar_module)
      {:error, _exception} = error -> error
    end
  end

  defp iso_date(input, calendar_module) do
    case try_iso(input, calendar_module) do
      {:ok, _date} = ok -> ok
      :error -> nil
    end
  end

  # Text that ISO 8601 reads as a date can be a date of the calendar asked
  # for, written in one of that calendar's own formats: "2023-11-22" is the
  # Chinese calendar's short date in every locale that takes CLDR's root
  # format, `r-MM-dd`, the twenty-second day of the eleventh month of the
  # year that began in 2023, and not 22 November. A calendar's own formats
  # come first (user, 2026-10-04): any of them, read as leniently as the
  # parser reads them anywhere ("Use the broader rule"), so ISO 8601 reads
  # such text only when none of the calendar's formats makes a date of it,
  # and a date the formatter writes reads back as itself. `Calendar.ISO` is
  # not asked: ISO 8601 is its own notation, as "2026-W25-2" is a calendar
  # of weeks'.
  defp own_format_reading(_input, _locale, Calendar.ISO, _own_calendar, _reference), do: nil

  defp own_format_reading(input, locale, calendar_module, own_calendar, reference) do
    with true <- Regex.match?(~r/\A\d{4}-\d{2}-\d{2}\z/, input),
         {:ok, patterns, ctx} <- locale_patterns(locale, calendar_module, own_calendar, reference) do
      run_locale_pass(patterns, input, ctx, :struct)
    else
      _not_a_date_iso_8601_reads -> nil
    end
  end

  @doc false
  # The date that `input`, which ISO 8601 also reads, is in one of the
  # formats of the calendar asked for, or `nil` when none of them reads it.
  # `Localize.DateTime.Parser` asks before it reads a date and time as ISO
  # 8601.
  @spec own_format_date(String.t(), Keyword.t()) :: {:ok, Date.t()} | nil
  def own_format_date(input, options) do
    with {:ok, calendar_module} <- calendar_option(options),
         {:ok, ^calendar_module} <- Localize.Calendar.parsing_calendar(calendar_module) do
      locale = Keyword.get(options, :locale) || Localize.get_locale()
      reference = reference_date(options, calendar_module)
      own_format_reading(input, locale, calendar_module, calendar_module, reference)
    else
      _read_in_another_calendar -> nil
    end
  end

  # The date partial input is completed against: the reference date in
  # the calendar the input is read in, so a Hebrew date without a year is
  # in this Hebrew year rather than the Hebrew year 2026.
  defp reference_date(options, calendar_module) do
    case Keyword.get(options, :reference_date) || Date.utc_today() do
      %{calendar: ^calendar_module} = date -> date
      %Date{} = date -> date_in_calendar(date, calendar_module)
      %{year: _year} = date -> date
    end
  end

  defp date_in_calendar(date, calendar_module) do
    case Date.convert(date, calendar_module) do
      {:ok, converted} -> converted
      {:error, _incompatible} -> date
    end
  end

  # Retry with ordinal affixes stripped. Only fires if the
  # original input couldn't be parsed, so CLDR-baked
  # ordinal text (e.g. `"2nd quarter"` quarter-wide name)
  # is preserved on the first attempt.
  defp retry_without_ordinal_affixes(attempt, inputs, locale, original_error) do
    stripped = Enum.map(inputs, &strip_ordinal_affixes(&1, locale))

    if stripped == inputs do
      original_error
    else
      case attempt.(Enum.uniq(stripped)) do
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
  def preprocess_safe(input, locale, calendar_module) when is_binary(input) do
    strip_weekday_prefix(input, locale, calendar_module)
  end

  # Strip a recognised weekday name from the start of `input`,
  # along with optional `.`/`,`/`;` punctuation immediately
  # after it. Trailing whitespace (or end-of-input) is required
  # so that single-letter narrow forms — which would otherwise
  # match the first letter of any token — don't strip
  # accidentally; narrow widths are also excluded from the
  # alternation for the same reason.
  defp strip_weekday_prefix(input, locale, calendar_module) do
    case Localize.Calendar.days(locale, cldr_calendar_type(calendar_module)) do
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

  @doc """
  Parses a single-string date range. See
  `Localize.Interval.parse/2` for the public contract.
  """
  @spec parse_range(String.t(), Keyword.t()) ::
          {:ok, Date.Range.t() | {map(), map()}} | {:error, Exception.t()}
  def parse_range(input, options \\ []) when is_binary(input) do
    read_for_calendar(options, &do_parse_range(input, &1, &2), &finalise_range_value/2)
  end

  defp do_parse_range(input, options, calendar_module) do
    locale = Keyword.get(options, :locale) || Localize.get_locale()
    reference = reference_date(options, calendar_module)
    own_calendar = own_calendar(options, calendar_module)
    allow_inverted = Keyword.get(options, :allow_inverted, false)
    as = Keyword.get(options, :as, :struct)

    # Range inputs are pre-split internally by interval-pattern
    # matching, and each endpoint goes through `parse/2` for the
    # split-and-parse fallback — so endpoint-level ordinal and
    # weekday stripping is handled by `parse/2`. Range-level interval
    # patterns don't bake ordinals into their literals (CLDR's
    # interval patterns share the field set with regular date
    # patterns). As in `parse/2`, the interval patterns see the input
    # as given before the input with a leading weekday stripped.
    normalised = normalise_input(input)
    candidates = Enum.uniq([normalised, preprocess_safe(normalised, locale, calendar_module)])

    # Strategy:
    # 1. Try the locale's CLDR interval patterns first — these
    #    are the only way to parse inputs where one endpoint is
    #    partial (e.g. "May 5 – May 10, 2026" where left has no
    #    year and inherits from right).
    # 2. Fall back to a naive split-then-parse-each-side. Catches
    #    inputs the interval patterns don't cover (e.g. mixed
    #    formats, ISO endpoints).
    #
    # A `:format` is the format each end was written with, so each is
    # read with it on its own, about the separator, and the locale's
    # interval patterns, which write the two in the locale's order, are
    # not tried.
    matched =
      if Keyword.get(options, :format),
        do: :error,
        else:
          match_interval_candidates(
            candidates,
            locale,
            calendar_module,
            own_calendar,
            reference,
            as
          )

    case matched do
      {:ok, from, to} ->
        finalise_range(from, to, allow_inverted, as)

      :error ->
        read_joined_range(normalised, locale, [own_calendar, calendar_module], options)
    end
  end

  defp match_interval_candidates(inputs, locale, calendar_module, own_calendar, reference, as) do
    Enum.find_value(inputs, :error, fn input ->
      case match_any_interval_pattern(
             input,
             locale,
             calendar_module,
             own_calendar,
             reference,
             as
           ) do
        {:ok, _from, _to} = ok -> ok
        :error -> nil
      end
    end)
  end

  # In `:map` mode there's no `Date.Range` to build and no
  # inversion to check — the partial maps may not have enough
  # fields to say which is the earlier. We return the pair
  # as-is and let the caller decide.
  defp finalise_range(%Date{} = from, %Date{} = to, allow_inverted, :struct) do
    build_range(from, to, allow_inverted)
  end

  defp finalise_range(%{} = from, %{} = to, _allow_inverted, :map) do
    {:ok, {from, to}}
  end

  # A range read in another calendar and converted, in the shape `:as`
  # asks for.
  defp finalise_range_value(%Date.Range{} = range, :struct), do: range

  defp finalise_range_value(%Date.Range{first: first, last: last}, :map),
    do: {date_to_map(first), date_to_map(last)}

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
  defp match_any_interval_pattern(input, locale, calendar_module, own_calendar, reference, as) do
    cldr_calendar = cldr_calendar_type(calendar_module)

    with {:ok, intervals} <- Format.interval_formats(locale, cldr_calendar),
         {:ok, months_data} <- LCalendar.months(locale, cldr_calendar) do
      transliterated = transliterate_digits(input, locale)
      order = Format.interval_order(intervals)
      ctx = field_context(locale, calendar_module, own_calendar, reference, months_data)
      ctx = %{ctx | interval_order: order}
      years = written_years(locale, calendar_module, own_calendar, reference)

      # An item is a pattern or, in `en-CA`, a default pattern and a variant
      # of it. The formatter writes the default unless it is asked for the
      # variant, so every default is tried before any variant: `en-CA`'s
      # `yMd` is "M/d/y–M/d/y" beside "d/M/y – d/M/y", and the
      # "5/6/2026–7/8/2026" it writes is from 6 May.
      {defaults, variants} = interval_patterns(intervals, years, ctx)
      plain_input = plain_spaces(transliterated)

      (written_first_of(defaults, plain_input) ++ written_first_of(variants, plain_input))
      |> Enum.find_value(:error, &interval_reading(transliterated, &1, ctx, as))
      |> in_range_order(order)
    else
      _ -> :error
    end
  end

  # The patterns a locale's intervals are read with in a calendar, the
  # default of each item and then the variants, each with the regex of every
  # way its year is read (`year_readings/2`). They are a function of the
  # locale and the calendar, as a date's patterns are, and are built once
  # for the two and kept (user, 2026-10-06), as `pattern_regexes/2` keeps a
  # date's: compiled on every call, an interval no early pattern read took
  # about 70 ms, and a single date and time paid it wherever the locale's
  # fallback separator was in its text (`da`'s hyphen). The cost is the
  # memory of some hundreds of compiled patterns for each locale and
  # calendar a range is read in.
  defp interval_patterns(intervals, years, ctx) do
    key = {__MODULE__, :interval_patterns, ctx.locale, ctx.calendar_module}

    case :persistent_term.get(key, nil) do
      nil ->
        patterns = build_interval_patterns(intervals, years, ctx)
        :persistent_term.put(key, patterns)
        patterns

      patterns ->
        patterns
    end
  end

  defp build_interval_patterns(intervals, years, ctx) do
    item_patterns =
      for {skeleton, by_field} <- intervals,
          is_atom(skeleton),
          is_map(by_field),
          {_field, pattern} <- by_field,
          do: pattern

    defaults = for pattern <- item_patterns, text <- default_pattern(pattern), do: text
    variants = for %{variant: text} <- item_patterns, is_binary(text), do: text

    {interval_entries(defaults, years, ctx), interval_entries(variants -- defaults, years, ctx)}
  end

  # The two dates an interval pattern read, the earlier first. TR35 has the
  # locale's fallback pattern give the order of every interval pattern, and
  # where it is "{1} – {0}", as `kek`'s is, the first date of a pattern is
  # the later one: "20/8/2027 – 16/6/2026" is from 16 June 2026, and the
  # same dates the other way round are an inverted range there, as
  # "8/20/2027 – 6/16/2026" is in `en`.
  defp in_range_order({:ok, first, second}, :latest_first), do: {:ok, second, first}
  defp in_range_order(reading, _order), do: reading

  defp default_pattern(pattern) when is_binary(pattern), do: [pattern]
  defp default_pattern(%{default: pattern}) when is_binary(pattern), do: [pattern]
  defp default_pattern(_other), do: []

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
  #
  # Each pattern is one entry: the literal text it must be written with
  # (`pattern_literals/1`) and its tokens and regex for each reading of its
  # year. A pattern with no field written twice reads one date and is no
  # interval's.
  defp interval_entries(patterns, years, ctx) do
    patterns
    |> Enum.flat_map(fn pattern -> [pattern | synthesize_day_first_variants(pattern)] end)
    |> Enum.uniq()
    |> Enum.sort_by(&pattern_specificity/1)
    |> Enum.map(fn pattern ->
      tokens = tokenize_pattern(pattern)

      readings =
        for reading <- year_readings(tokens, years),
            %Regex{} = regex <- [compile_interval_regex(reading, ctx)],
            do: {reading, regex}

      %{literals: pattern_literals(tokens), readings: readings}
    end)
  end

  # A pattern whose own text is in the input is tried before one that reads
  # the input only through a lenient separator: the text a pattern writes
  # holds its separators as they are. An item's patterns need not agree,
  # where a locale gives some and takes the rest from root: `ha`'s `yMd` is
  # "dd/MM/y – dd/MM/y" for a day's or a month's difference and root's
  # "y-MM-dd – y-MM-dd" for a year's, whose "26-06-16 – 27-08-20" the first
  # reads, a hyphen for its slash, as 26 June 2016 to 27 August 2020.
  defp written_first_of(entries, plain_input) do
    {written, lenient} =
      Enum.split_with(entries, fn %{literals: literals} ->
        Enum.all?(literals, &String.contains?(plain_input, &1))
      end)

    written ++ lenient
  end

  # Whether each piece of the pattern's literal text is in the input, the
  # spaces about it apart: a pattern's thin or no-break space is any space
  # in the text read.
  defp literals_in?(pattern, plain_input) do
    pattern
    |> tokenize_pattern()
    |> pattern_literals()
    |> Enum.all?(&String.contains?(plain_input, &1))
  end

  defp pattern_literals(tokens) do
    for {:lit, text} <- tokens,
        literal = text |> plain_spaces() |> String.trim(),
        literal != "",
        do: literal
  end

  defp plain_spaces(text),
    do: String.replace(text, ~r/[\s\x{00A0}\x{2009}\x{202F}\x{3000}]+/u, " ")

  # CLDR keys a calendar's interval patterns by `y`, and the formatter
  # writes them with the year its format asks for: the related Gregorian
  # year where the calendar's formats write `r`, as the Chinese and Dangi
  # calendars' standard formats do ("11/8/2023 – 11/18/2023" for two days of
  # the Chinese year 4660), and the year's two low-order digits where a
  # format writes `yy`, as `lij`'s short Islamic date does ("30/12/47 –
  # 4/1/48 AH"). An interval's year is then read each way its calendar's
  # formats write one, and the reading whose years are nearest the reference
  # year is taken, as a single date's is (`run_locale_pass/4`). A year
  # written as its two low-order digits is no related year.
  defp interval_reading(input, %{readings: readings}, ctx, as) do
    readings
    |> Enum.map(fn {tokens, regex} -> match_interval_tokens(input, tokens, regex, ctx, as) end)
    |> Enum.reject(&(&1 == :error))
    |> Enum.min_by(&interval_distance(&1, ctx.reference_year), fn -> nil end)
  end

  defp year_readings(tokens, %{related: related?, truncated: truncated?}) do
    related = if related?, do: [related_year_tokens(tokens)], else: []
    truncated = if truncated?, do: [with_year(tokens, fn _count -> {:y, 2} end)], else: []

    Enum.uniq([tokens | related ++ truncated])
  end

  defp with_year(tokens, year) do
    Enum.map(tokens, fn
      {:y, count} when count != 2 -> year.(count)
      token -> token
    end)
  end

  # The related year stands wherever the item has its year, as a number or
  # by its name: the formatter writes the year a format asks for in the
  # place of whichever the item has, so `en`'s Chinese "MMM d – d, U" is
  # written "Mo5 2 – 6, 2026" at the medium format, whose date is "MMM d, r".
  defp related_year_tokens(tokens) do
    Enum.map(tokens, fn
      {:y, count} when count != 2 -> {:r, count}
      {:U, count} -> {:r, count}
      token -> token
    end)
  end

  # How far a reading's years are from the reference year, both ends
  # counted: an era written once beside the second date leaves the first
  # year the same in two readings, and the second tells them apart.
  defp interval_distance({:ok, from, to}, reference_year),
    do: year_distance(from, reference_year) + year_distance(to, reference_year)

  defp interval_distance(_reading, _reference_year), do: 0

  defp year_distance(%{year: year}, reference_year) when is_integer(year),
    do: abs(year - reference_year)

  defp year_distance(_value, _reference_year), do: 0

  # How the calendar's dates write their year in the locale, other than as
  # the `y` an interval pattern is keyed by: as the related Gregorian year,
  # where one of its date patterns has an `r`, and as the year's two
  # low-order digits, where one has `yy`. Cached, as the patterns' regexes
  # are.
  defp written_years(locale, calendar_module, own_calendar, reference) do
    key = {__MODULE__, :written_years, locale, calendar_module}

    case :persistent_term.get(key, nil) do
      nil ->
        years =
          case locale_patterns(locale, calendar_module, own_calendar, reference) do
            {:ok, patterns, _ctx} ->
              tokens = Enum.flat_map(patterns, &pattern_tokens/1)

              %{
                related: Enum.any?(tokens, &match?({:r, _count}, &1)),
                truncated: two_digit_year?(tokens)
              }

            _no_patterns ->
              %{related: false, truncated: false}
          end

        :persistent_term.put(key, years)
        years

      years ->
        years
    end
  end

  defp pattern_tokens({_skeleton, pattern}),
    do: pattern |> pattern_text() |> tokenize_pattern()

  defp match_interval_tokens(input, tokens, regex, ctx, as) do
    ctx = %{ctx | two_digit_year: two_digit_year?(tokens)}

    with %{} = caps <- Regex.named_captures(regex, input),
         {left_era, right_era} = interval_eras(caps),
         {:ok, left_partial} <- extract_partial(caps, {"left_", "right_"}, left_era, ctx),
         {:ok, right_partial} <- extract_partial(caps, {"right_", "left_"}, right_era, ctx) do
      interval_endpoints_for(as, left_partial, right_partial, ctx)
    else
      _ -> :error
    end
  end

  # The regex of an interval pattern, its two dates' captures told apart by
  # their names, or `nil` for a pattern with no field written twice, which
  # reads one date and is no interval's.
  defp compile_interval_regex(tokens, ctx) do
    ctx = %{ctx | two_digit_year: two_digit_year?(tokens)}

    with {tokens_l, [_ | _] = tokens_r} <- split_interval_tokens(tokens),
         left_regex = compile_capture_regex(joined(tokens_l), ctx, "left_"),
         right_regex = compile_capture_regex(spaced_dashes(tokens_r), ctx, "right_"),
         {:ok, regex} <- Regex.compile("\\A" <> left_regex <> right_regex <> "\\z", "u") do
      regex
    else
      _no_interval -> nil
    end
  end

  # The text between an interval's two dates is the last of its first part,
  # and is read with its spaces as the writer chose them (`expand_join/2`).
  defp joined(tokens_l) do
    tokens = spaced_dashes(tokens_l)

    case List.last(tokens) do
      {:lit, text} -> List.replace_at(tokens, -1, {:join, text})
      _other -> tokens
    end
  end

  # A pattern is split where a field first comes again, which is not always
  # at its dash: `fil`'s Hebrew "d – MMM d y" is split at its second day, so
  # the dash is in its first part. Any text with a dash set off by a space is
  # read as the text between the dates is.
  defp spaced_dashes(tokens) do
    Enum.map(tokens, fn
      {:lit, text} = literal -> if spaced_dash?(text), do: {:join, text}, else: literal
      token -> token
    end)
  end

  defp spaced_dash?(text) do
    text
    |> String.graphemes()
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.any?(fn [first, second] ->
      (first in @dash_chars and space_char?(second)) or
        (space_char?(first) and second in @dash_chars)
    end)
  end

  defp interval_endpoints_for(:struct, left, right, ctx) do
    latest_first? = ctx.interval_order == :latest_first
    {earlier, later} = if latest_first?, do: {right, left}, else: {left, right}

    with {:ok, earlier_date, later_date} <- endpoints_in_their_years(earlier, later, ctx) do
      if latest_first?, do: {:ok, later_date, earlier_date}, else: {:ok, earlier_date, later_date}
    end
  end

  defp interval_endpoints_for(:map, left_partial, right_partial, ctx) do
    %{calendar_module: calendar_module, reference_year: reference} = ctx
    {left_partial, right_partial} = sharing_a_written_year(left_partial, right_partial, ctx)

    with true <- interval_partial_meaningful?(left_partial),
         true <- interval_partial_meaningful?(right_partial),
         {:ok, left_map} <-
           partial_to_map(left_partial, right_partial, calendar_module, reference),
         {:ok, right_map} <-
           partial_to_map(right_partial, left_partial, calendar_module, reference) do
      {:ok, left_map, right_map}
    else
      _ -> :error
    end
  end

  # An interval's two dates, the earlier first, each in its year. Two dates
  # written without a year are of the reference date's year, as a date alone
  # written without one is: the earlier is, and the later is the date of its
  # month and day beside it (`date_beside/4`), so "Dec 28 – Jan 3" ends in
  # the January that follows (user, 2026-10-06). The formatter writes no such
  # text for two whole dates, giving both their years where they differ, but
  # it writes it for two dates given without their years.
  defp endpoints_in_their_years(%{year: nil} = earlier, %{year: nil} = later, ctx) do
    earlier = %{earlier | year: ctx.reference_year}

    with {:ok, earlier_date} <- materialise(earlier, later, ctx.calendar_module),
         {:ok, later_date} <-
           partial_beside(later, earlier, earlier_date, :after, ctx.calendar_module) do
      {:ok, earlier_date, later_date}
    else
      _ -> :error
    end
  end

  # A date written without its year beside one written with its year takes
  # that year, as CLDR's interval patterns write a year the two share once,
  # or the year next to it where the two would otherwise be in the wrong
  # order: "Dec 28 – Jan 3, 2027" begins in the December before, and `ja`'s
  # "2026年12月28日～1月3日" ends in the January after.
  defp endpoints_in_their_years(%{year: nil} = earlier, later, ctx) do
    with {:ok, later_date} <- materialise(later, earlier, ctx.calendar_module),
         {:ok, earlier_date} <-
           partial_beside(earlier, later, later_date, :before, ctx.calendar_module) do
      {:ok, earlier_date, later_date}
    else
      _ -> :error
    end
  end

  defp endpoints_in_their_years(earlier, %{year: nil} = later, ctx) do
    with {:ok, earlier_date} <- materialise(earlier, later, ctx.calendar_module),
         {:ok, later_date} <-
           partial_beside(later, earlier, earlier_date, :after, ctx.calendar_module) do
      {:ok, earlier_date, later_date}
    else
      _ -> :error
    end
  end

  # Each date written with its year is as it is written, and takes the
  # fields it does not write from the other (`materialise/3`).
  defp endpoints_in_their_years(earlier, later, ctx) do
    with {:ok, earlier_date} <- materialise(earlier, later, ctx.calendar_module),
         {:ok, later_date} <- materialise(later, earlier, ctx.calendar_module) do
      {:ok, earlier_date, later_date}
    else
      _ -> :error
    end
  end

  # As maps, two ends written without a year have none, and one written
  # without its year beside one written with its year has the year its
  # date has there (`endpoints_in_their_years/3`). An end with no day is
  # placed by its first: "Dec – Jan 2027" begins in December 2026.
  defp sharing_a_written_year(left, right, ctx) do
    latest_first? = ctx.interval_order == :latest_first
    {earlier, later} = if latest_first?, do: {right, left}, else: {left, right}

    {earlier, later} =
      case {earlier, later} do
        {%{year: nil}, %{year: nil}} -> {earlier, later}
        {%{year: nil}, _dated} -> {with_year_beside(earlier, later, :before, ctx), later}
        {_dated, %{year: nil}} -> {earlier, with_year_beside(later, earlier, :after, ctx)}
        _both_dated -> {earlier, later}
      end

    if latest_first?, do: {later, earlier}, else: {earlier, later}
  end

  defp with_year_beside(partial, anchor_partial, side, ctx) do
    whole = %{partial | day: partial.day || anchor_partial.day || 1}
    anchor_whole = %{anchor_partial | day: anchor_partial.day || partial.day || 1}

    with {:ok, anchor} <- materialise(anchor_whole, whole, ctx.calendar_module),
         {:ok, %Date{year: year}} <-
           partial_beside(whole, anchor_whole, anchor, side, ctx.calendar_module) do
      %{partial | year: year}
    else
      _no_date -> partial
    end
  end

  # The date of `partial`, written without its year, on `side` of the date
  # `anchor` of the interval's other end, whose fields are `anchor_partial`.
  defp partial_beside(partial, anchor_partial, %Date{} = anchor, side, calendar_module) do
    backwards? = backwards_in_a_month?(partial, anchor_partial, side)

    date_beside(
      fn %Date{year: year} ->
        materialise(%{partial | year: year}, anchor_partial, calendar_module)
      end,
      anchor,
      side,
      fn _in_the_anchors_year -> backwards? end
    )
  end

  # The date an interval's end written without its year is, beside the date
  # of its other end. `read` gives it in the year of the date it is given,
  # and `side` is `:after` where it follows `anchor` and `:before` where it
  # comes before it.
  #
  # It is in the anchor's year. Where it would lie on the other side of the
  # anchor there, or is no date in that year, it is in the year next to the
  # anchor's on its own side, the two then less than a year apart:
  # "Dec 28 – Jan 3" is six days, and "Dec 28 – Feb 29" ends in the leap
  # year after. The years are the calendar's own and so is their order: a
  # year of `Calendrical.Julian.March25` runs from 25 March, so its
  # "Mar 20 – 28" turns the year and its "May 20 – Jan 3" does not.
  #
  # A day and an earlier day of one month are not taken a year apart
  # (`backwards?`): "Jun 20 – 16" is an inverted range, as it is with its
  # year, and not the 361 days to the next 16 June.
  defp date_beside(read, %Date{} = anchor, side, backwards?) do
    in_the_anchors_year = read.(anchor)

    with true <- other_side?(in_the_anchors_year, anchor, side),
         false <- backwards?.(in_the_anchors_year),
         {:ok, a_year_away} <- a_year_away(anchor, side),
         {:ok, %Date{} = date} <- read.(a_year_away),
         true <- within_a_year?(date, anchor, a_year_away, side) do
      {:ok, date}
    else
      _as_it_is -> in_the_anchors_year
    end
  end

  # How a date on the other side of an anchor compares with it.
  defp other_side(:after), do: :lt
  defp other_side(:before), do: :gt

  defp other_side?({:ok, %Date{} = date}, anchor, side),
    do: Localize.Calendar.compare_days(date, anchor) == other_side(side)

  defp other_side?(_no_date, _anchor, _side), do: true

  # On the anchor's day or on its own side of it, and short of the same day
  # a year away.
  defp within_a_year?(date, anchor, a_year_away, side) do
    Localize.Calendar.compare_days(date, anchor) != other_side(side) and
      Localize.Calendar.compare_days(date, a_year_away) == other_side(side)
  end

  # Whether two ends name one month, or one takes its month from the other,
  # with their days in the wrong order. The fields are as they were written:
  # a month's name or its number, and a day.
  defp backwards_in_a_month?(%{day: day} = fields, %{day: anchor_day} = anchor_fields, side)
       when is_integer(day) and is_integer(anchor_day) do
    month = Map.get(fields, :month)
    anchor_month = Map.get(anchor_fields, :month)
    same_month? = is_nil(month) or is_nil(anchor_month) or month == anchor_month

    same_month? and if(side == :after, do: day < anchor_day, else: day > anchor_day)
  end

  defp backwards_in_a_month?(_fields, _anchor_fields, _side), do: false

  # The same day of the year after a date's, or of the year before it, as
  # its calendar counts: a calendar need not number its years one apart.
  defp a_year_away(%Date{year: year, month: month, day: day, calendar: calendar}, side) do
    years = if side == :after, do: 1, else: -1

    with {:ok, {year, month, day}} <-
           Localize.Calendar.shift(calendar, {year, month, day}, years, 0),
         {:ok, date} <- Date.new(year, month, day, calendar) do
      {:ok, date}
    else
      _no_such_day -> :error
    end
  end

  # Build the partial map for one interval endpoint. Missing
  # fields inherit from the other endpoint (CLDR interval
  # convention) just like `materialise/3` does for the struct
  # path; the difference is we stop after inheritance and skip
  # the Date construction, so the endpoint is checked against
  # the calendar instead and an impossible one does not match.
  defp partial_to_map(side, inherit_from, calendar_module, reference_year) do
    year = side.year || inherit_from.year
    month = named_month(side.month || inherit_from.month, year, calendar_module)
    day = side.day || inherit_from.day

    if month != :invalid and
         possible?(date_fields(year, month, day, calendar_module), reference_year) do
      {:ok,
       %{calendar: calendar_module}
       |> maybe_put(:year, year)
       |> maybe_put(:month, month)
       |> maybe_put(:day, day)}
    else
      :error
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  # Reject regex matches where one side captured no date fields
  # at all — that's a malformed interval, not a legitimate
  # partial.
  defp interval_partial_meaningful?(%{year: nil, month: nil, day: nil}), do: false
  defp interval_partial_meaningful?(_), do: true

  # Sort key: day-bearing patterns first, then longer (more
  # specific) patterns within each group, then the pattern itself,
  # so the order never depends on the order the patterns arrived in.
  defp pattern_specificity(pattern) do
    text = pattern_text(pattern)
    {if(pattern_has_day?(text), do: 0, else: 1), -String.length(text), pattern}
  end

  # A pattern is its text, or its text and the numbering it writes its
  # fields in.
  defp pattern_text({text, _numbers}), do: text
  defp pattern_text(text), do: text

  defp pattern_numbers({_text, numbers}), do: numbers
  defp pattern_numbers(_text), do: %{}

  # Quoted literals are stripped so a literal "d" in text does not
  # count as a field.
  defp pattern_has_day?(pattern) do
    pattern |> String.replace(~r/'[^']*'/u, "") |> String.contains?("d")
  end

  # Walk the token stream: a field that's already been seen
  # marks the start of the right endpoint. The tokens between
  # the first and second occurrence of any field (typically
  # just literal separator text) get appended to the left
  # side. We accept day-of-week (`E`/`c`) repeats as well as
  # the date fields.
  defp split_interval_tokens(tokens) do
    {left, right, _seen} = Enum.reduce(tokens, {[], [], MapSet.new()}, &place_interval_token/2)
    {left, right}
  end

  defp place_interval_token(token, {left, right, seen}) do
    case classify_token(token) do
      {:field, letter} ->
        if MapSet.member?(seen, letter) or right != [] do
          {left, right ++ [token], seen}
        else
          {left ++ [token], right, MapSet.put(seen, letter)}
        end

      :literal when right == [] ->
        {left ++ [token], right, seen}

      :literal ->
        {left, right ++ [token], seen}
    end
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
        match?({letter, _} when letter in [:y, :r, :U], token) -> {:cont, {idx - 1, true}}
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
  defp compile_capture_regex(tokens, ctx, prefix) do
    tokens
    |> build_regex_parts(ctx.months, ctx.eras, ctx.lenient, prefix, ctx)
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
  # so `materialise/3` can fill from the other side. A year
  # written with its era is the year of that era.
  # The era of each date of an interval. A pattern writes the era once where
  # the two dates share it ("M/d/y – M/d/y G", "G y-MM-dd – y-MM-dd"), so a
  # date written without one is of the era beside the other, as it takes the
  # other's year where it has none: "H5/06/16～5/06/20" is five days of
  # Heisei 5, whatever era the reference date is in.
  defp interval_eras(caps) do
    left = extract_partial_era_index(caps, "left_")
    right = extract_partial_era_index(caps, "right_")
    {left || right, right || left}
  end

  # One date of an interval, from the captures of its side of the pattern.
  # Its year of an era is asked of the calendar about the date it will be:
  # with the month and the day it takes from the other date where it writes
  # none of its own (`materialise/3`). In a year two eras share the year
  # alone names neither: `en`'s "May 1 – 5, 1 Reiwa" ends on a day written
  # without its month, and 2019 is Heisei 31 until April.
  defp extract_partial(caps, {prefix, other}, era_index, ctx) do
    month = extract_month(caps, prefix)
    day = extract_day(caps, prefix)
    asked = {month || extract_month(caps, other), day || extract_day(caps, other)}

    with {:ok, year} <- extract_calendar_year(caps, prefix, nil, era_index, ctx, asked) do
      reject_invalid(%{year: year, month: month, day: day})
    end
  end

  # The calendar's year the captures give: `y` resolved through its era,
  # else `r` (the related Gregorian year), else `y` as a place in the
  # sixty-year cycle, else `U` (the cyclic year name), else
  # `year_fallback`. A related year, a place or a cyclic name written
  # beside the year it was not taken from must agree with that year.
  defp extract_calendar_year(caps, prefix, year_fallback, era_index, ctx, month_day) do
    with {:ok, year, place} <- written_year(caps, prefix, era_index, ctx, month_day),
         {:ok, year} <- with_related_year(year, capture(caps, prefix <> "related_year"), ctx),
         {:ok, year} <- with_cyclic_year(year, place, ctx),
         {:ok, year} <- with_cyclic_year(year, named_capture_index(caps, prefix <> "__u"), ctx) do
      {:ok, year || year_fallback}
    end
  end

  # The year `y` (or, reading a whole date, `Y`) writes, as the calendar's
  # year: of the era written beside it, or in a calendar that writes its
  # years as years of an era, of the implied era. In a calendar of cyclic
  # years it is no year yet but a place in the cycle, given beside it.
  defp written_year(caps, prefix, era_index, ctx, month_day) do
    case year_capture(caps, prefix) do
      nil ->
        numeral_year(caps, prefix, era_index, ctx, month_day)

      raw ->
        case parse_year(raw) do
          {year, ""} -> numbered_year(year, raw, era_index, ctx, month_day)
          _other -> :error
        end
    end
  end

  # A year written as a numeral of an algorithmic numbering, `ja`'s 元 for
  # the first year of an era (`year_numerals/2`), or no year at all.
  defp numeral_year(caps, prefix, era_index, ctx, month_day) do
    case named_capture_index(caps, prefix <> "__y") do
      nil -> {:ok, nil, nil}
      year -> numbered_year(year, Integer.to_string(year), era_index, ctx, month_day)
    end
  end

  # A calendar of cyclic years writes `y` as the year's place in the
  # sixty-year cycle (`cyclic_year_written?/3`), so a number of 1 to 60 is
  # that place, of the year a related year beside it names or else of the
  # year nearest the reference year, as `U`'s name is: "40" is the Chinese
  # year that began in 2023. A greater number is no place in the cycle, and
  # is the year as the calendar numbers it.
  defp numbered_year(year, _raw, _era_index, %{cyclic_year_written: true}, _month_day) do
    if year in 1..60, do: {:ok, nil, year}, else: {:ok, year, nil}
  end

  defp numbered_year(year, raw, era_index, ctx, month_day) do
    era_index = era_index || ctx.implied_era

    year
    |> maybe_pivot_two_digit_year(raw, era_index, ctx)
    |> resolve_calendar_year(era_index, ctx.calendar_module, month_day)
    |> case do
      {:ok, year} -> {:ok, year, nil}
      {:error, _unknown_era} = error -> error
    end
  end

  defp year_capture(caps, ""), do: capture(caps, "year") || capture(caps, "week_based_year")
  defp year_capture(caps, prefix), do: capture(caps, prefix <> "year")

  defp capture(caps, key) do
    case Map.get(caps, key) do
      value when is_binary(value) and value != "" -> value
      _absent -> nil
    end
  end

  # A year in digits, or in the Hebrew numerals the year field captures
  # only where its pattern writes them.
  defp parse_year(raw) do
    case raw |> String.replace("−", "-") |> Integer.parse() do
      {_year, ""} = year ->
        year

      _not_digits ->
        case Localize.Number.HebrewNumerals.parse(raw) do
          {:ok, year} -> {year, ""}
          :error -> :error
        end
    end
  end

  # A two-digit year is read in the century window around the reference
  # year, in any calendar, when no era qualifies it, or when the pattern
  # writes it as `yy` — a year's two low-order digits, so the Buddhist 2566
  # in "01.04.66 BE" is "66" — in a calendar that shows its years as they
  # are numbered. A calendar of cyclic years writes a place in its cycle
  # and is read before this (`numbered_year/5`). A year `y` writes
  # beside its era ("44 BC", "44 AD") is taken as written, as is a `yy`
  # year of an era in a calendar that shows years of an era: "01.04.05 R"
  # is Reiwa 5.
  defp maybe_pivot_two_digit_year(year, raw, era_index, ctx) do
    truncated? = ctx.two_digit_year and is_nil(ctx.implied_era)

    if two_digits?(raw) and (truncated? or is_nil(era_index)),
      do: pivot_year(year, ctx.reference_year),
      else: year
  end

  # Two unsigned digits: "-4" is two characters, but a signed year is
  # written in full.
  defp two_digits?(raw), do: String.match?(raw, ~r/\A\d{2}\z/)

  # `r`, the related Gregorian year: in a calendar whose year follows the
  # solar year it is a fixed number of years from the calendar's year
  # (TR35).
  defp with_related_year(year, nil, _ctx), do: {:ok, year}

  defp with_related_year(year, raw, ctx) do
    case parse_year(raw) do
      {related, ""} -> year_with_related(year, related, ctx)
      _other -> :error
    end
  end

  defp year_with_related(nil, related, ctx) do
    %{calendar_module: calendar_module, reference_year: reference_year} = ctx

    case related_year_of(reference_year, calendar_module) do
      {:ok, reference_related} ->
        year = related - (reference_related - reference_year)

        Enum.find_value([year, year - 1, year + 1], :error, fn candidate ->
          related_year_of(candidate, calendar_module) == {:ok, related} && {:ok, candidate}
        end)

      {:error, _exception} ->
        :error
    end
  end

  defp year_with_related(year, related, ctx) do
    if related_year_of(year, ctx.calendar_module) == {:ok, related},
      do: {:ok, year},
      else: :error
  end

  # A calendar year's related Gregorian year, as the formatter writes `r`.
  defp related_year_of(year, calendar_module) do
    Localize.Calendar.ask(
      calendar_module,
      :related_gregorian_year,
      [year, 1, 1],
      "a Gregorian year",
      &is_integer/1
    )
  end

  # `U`, the cyclic year name: the year of that name nearest the
  # reference year, as the name recurs every sixty years.
  defp with_cyclic_year(year, nil, _ctx), do: {:ok, year}

  defp with_cyclic_year(nil, position, ctx) do
    %{calendar_module: calendar_module, reference_year: reference_year} = ctx

    case cyclic_position(reference_year, calendar_module) do
      nil -> :error
      reference -> {:ok, reference_year + Integer.mod(position - reference + 30, 60) - 30}
    end
  end

  defp with_cyclic_year(year, position, ctx) do
    if cyclic_position(year, ctx.calendar_module) == position, do: {:ok, year}, else: :error
  end

  # A calendar year's place in the sexagenary cycle, as the formatter
  # finds it for `U`; `nil` when the calendar answers with no year.
  defp cyclic_position(year, calendar_module) do
    case Localize.Calendar.ask(
           calendar_module,
           :cyclic_year,
           [year, 1, 1],
           "a year",
           &is_integer/1
         ) do
      {:ok, number} -> Localize.Utils.Math.amod(number, 60)
      {:error, _exception} -> nil
    end
  end

  # The month the captures give: a number, a lunisolar month's traditional
  # number (`2bis`, `闰2`) or a month name. Each is the CLDR month the
  # formatter writes, `{:named, month}` until the year places it in its
  # calendar (`named_month/3`), so a Hebrew common year's Adar, written 7,
  # is its sixth month.
  defp extract_month(caps, prefix) do
    case {capture(caps, prefix <> "month"), capture(caps, prefix <> "traditional_month")} do
      {nil, nil} -> numeral_month(caps, prefix) || named_month_capture(caps, prefix)
      {nil, raw} -> traditional_month(raw, leap_marked?(caps, prefix))
      {raw, _traditional} -> month_number(raw)
    end
  end

  # The month an algorithmic numeral (`romanlow` "xii") gives.
  defp numeral_month(caps, prefix) do
    case named_capture_index(caps, prefix <> "__n") do
      month when is_integer(month) -> {:named, month}
      nil -> nil
    end
  end

  defp month_number(raw) do
    case Integer.parse(raw) do
      {month, ""} when month in 1..13 -> {:named, month}
      _other -> :invalid
    end
  end

  defp traditional_month(raw, leap?) do
    case Integer.parse(raw) do
      {month, ""} when month in 1..12 and leap? -> {:named, {month, :leap}}
      {month, ""} when month in 1..12 -> {:named, month}
      _other -> :invalid
    end
  end

  defp leap_marked?(caps, prefix) do
    capture(caps, prefix <> "month_leap_before") != nil or
      capture(caps, prefix <> "month_leap_after") != nil
  end

  # The day the captures give, as a number or as the numeral an
  # algorithmic numbering writes (`hanidays`: 初一, 廿一).
  defp extract_day(caps, prefix) do
    case capture(caps, prefix <> "day") do
      nil ->
        named_capture_index(caps, prefix <> "__h")

      raw ->
        case Integer.parse(raw) do
          {day, ""} when day in 1..31 -> day
          _other -> :invalid
        end
    end
  end

  # The era field's capture index, which `resolve_calendar_year/4`
  # turns a year of that era into the calendar's year with.
  defp extract_partial_era_index(caps, prefix) do
    prefixed_indexed_capture(caps, prefix, "__e", ~r/__e(\d+)__$/) ||
      prefixed_indexed_capture(caps, prefix, "__f", ~r/__f(\d+)__$/)
  end

  # The month a `<prefix>__mN__` capture names. A month name gives CLDR's
  # number for the month, `{:named, n}`, or `{:named, {n, :leap}}` for
  # CLDR's leap-year name of month `n` (the `7_yeartype_leap` capture,
  # Hebrew "Adar II") or a name in the leap-month pattern (the `2_leap`
  # capture, "Mo2bis"). It becomes the month of the date only once the
  # year is known (`named_month/3`).
  defp named_month_capture(caps, prefix) do
    marker = prefix <> "__m"

    case Enum.find(caps, fn {key, value} -> String.starts_with?(key, marker) and value != "" end) do
      {key, _value} ->
        key
        |> String.replace_prefix(marker, "")
        |> String.replace_suffix("__", "")
        |> named_month_index()

      nil ->
        nil
    end
  end

  defp named_month_index(index) do
    case Integer.parse(index) do
      {n, ""} when n in 1..13 -> {:named, n}
      {n, "_yeartype_leap"} when n in 1..13 -> {:named, {n, :leap}}
      {n, "_leap"} when n in 1..13 -> {:named, {n, :leap}}
      _other -> nil
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
  defp materialise(%{year: y, month: m, day: d}, inherit_from, calendar_module) do
    year = y || inherit_from.year
    month = m || inherit_from.month
    day = d || inherit_from.day

    if is_nil(year) or is_nil(month) or is_nil(day) do
      :error
    else
      with month when is_integer(month) <- named_month(month, year, calendar_module),
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
    read_for_calendar(
      options,
      fn options, _calendar_module -> read_range_pair(from_string, to_string, options) end,
      &finalise_range_value/2
    )
  end

  # Two dates, each read as a date alone is, in the calendar the options
  # name: the calendar their text is read in, where another was asked for
  # (`read_for_calendar/3`), so that two dates written for a calendar of
  # weeks share a year as the Gregorian dates they are written as.
  defp read_range_pair(from_string, to_string, options) do
    allow_inverted = Keyword.get(options, :allow_inverted, false)
    as = Keyword.get(options, :as, :struct)

    with {:ok, from, to} <- range_pair(from_string, to_string, as, options) do
      finalise_range(from, to, allow_inverted, as)
    end
  end

  # Two dates written without a year are of the reference date's year: the
  # earlier is, and the later is the date of its month and day beside it, as
  # an interval pattern's two dates are (`date_beside/4`), so "December 28
  # to January 3" ends in the January that follows. A date written without
  # its year beside one written with its year is the date of its month and
  # day beside that one, whatever the reference date: "June 16 to August
  # 20, 2031" is in 2031. A date written with its year stays as it is read.
  defp range_pair(from_string, to_string, :struct, options) do
    case {written_fields(from_string, options), written_fields(to_string, options)} do
      {%{year: nil} = from_fields, %{year: nil} = to_fields} ->
        with {:ok, %Date{} = from} <- parse_or_wrap(from_string, options, :from_parse_failed),
             {:ok, to} <-
               string_beside(
                 {to_string, to_fields},
                 {from, from_fields},
                 :after,
                 options,
                 options
               ) do
          {:ok, from, to}
        end

      {%{year: nil} = from_fields, %{} = to_fields} ->
        with {:ok, %Date{} = to} <- dated_end(to_fields, to_string, :to_parse_failed, options),
             {:ok, from} <-
               string_beside(
                 {from_string, from_fields},
                 {to, to_fields},
                 :before,
                 Keyword.put(options, :reference_date, to),
                 options
               ) do
          {:ok, from, to}
        end

      {%{} = from_fields, %{year: nil} = to_fields} ->
        with {:ok, %Date{} = from} <-
               dated_end(from_fields, from_string, :from_parse_failed, options),
             {:ok, to} <-
               string_beside(
                 {to_string, to_fields},
                 {from, from_fields},
                 :after,
                 Keyword.put(options, :reference_date, from),
                 options
               ) do
          {:ok, from, to}
        end

      {%{} = from_fields, %{} = to_fields} ->
        with {:ok, from} <- dated_end(from_fields, from_string, :from_parse_failed, options),
             {:ok, to} <- dated_end(to_fields, to_string, :to_parse_failed, options) do
          {:ok, from, to}
        end

      _no_date ->
        each_alone(from_string, to_string, options)
    end
  end

  # As maps the two are the fields each was written with, and a year one
  # was written without is the year it has beside the other's, as it is
  # where an interval pattern reads the two (`sharing_a_written_year/3`):
  # the year of its date there, or of its month where the two are no dates,
  # "June to August 2031".
  defp range_pair(from_string, to_string, _as, options) do
    with {:ok, %{} = from, %{} = to} <- each_alone(from_string, to_string, options) do
      if year_written?(from) == year_written?(to),
        do: {:ok, from, to},
        else: sharing_a_year(from, to, {from_string, to_string}, options)
    end
  end

  defp year_written?(fields),
    do: Map.has_key?(fields, :year) or Map.has_key?(fields, :week_based_year)

  defp sharing_a_year(from, to, {from_string, to_string}, options) do
    case range_pair(from_string, to_string, :struct, Keyword.put(options, :as, :struct)) do
      {:ok, %Date{} = from_date, %Date{} = to_date} ->
        {:ok, put_year(from, from_date.year), put_year(to, to_date.year)}

      _no_dates ->
        ctx = %{interval_order: :earliest_first, calendar_module: Map.get(from, :calendar)}
        {earlier, later} = sharing_a_written_year(written_partial(from), written_partial(to), ctx)
        {:ok, put_year(from, earlier.year), put_year(to, later.year)}
    end
  end

  defp written_partial(fields),
    do: %{
      year: Map.get(fields, :year),
      month: Map.get(fields, :month),
      day: Map.get(fields, :day)
    }

  defp put_year(fields, year) do
    if is_nil(year) or year_written?(fields), do: fields, else: Map.put(fields, :year, year)
  end

  # An end written with its year, which its text was read for once already
  # (`written_fields/2`): the date its fields make where they are a year, a
  # month and a day, and else the text read as a date.
  defp dated_end(%{date: %Date{} = date}, _string, _reason, _options), do: {:ok, date}
  defp dated_end(_fields, string, reason, options), do: parse_or_wrap(string, options, reason)

  defp each_alone(from_string, to_string, options) do
    with {:ok, from} <- parse_or_wrap(from_string, options, :from_parse_failed),
         {:ok, to} <- parse_or_wrap(to_string, options, :to_parse_failed) do
      {:ok, from, to}
    end
  end

  # The date `string` is, written without its year, beside the date `anchor`
  # of the range's other end. `same_year` is the options it is read with in
  # the anchor's year, and each `fields` the fields a string was written
  # with. Where a day and an earlier day are of one month is told from the
  # two dates, where there are two, as a month's number in a year is not its
  # number in another.
  defp string_beside({string, fields}, {anchor, anchor_fields}, side, same_year, options) do
    reason = if side == :after, do: :to_parse_failed, else: :from_parse_failed

    date_beside(
      fn
        ^anchor -> parse_or_wrap(string, same_year, reason)
        %Date{} = reference -> parse(string, Keyword.put(options, :reference_date, reference))
      end,
      anchor,
      side,
      fn
        {:ok, %Date{} = date} -> backwards_in_a_month?(date, anchor, side)
        _no_date -> backwards_in_a_month?(fields, anchor_fields, side)
      end
    )
  end

  # The year, the month and the day a date was written with, each `nil`
  # where it was not written, with the date they make, or `nil` for text
  # that is no date.
  defp written_fields(string, options) do
    case parse(string, Keyword.put(options, :as, :map)) do
      {:ok, %{} = fields} ->
        %{
          year: Map.get(fields, :year) || Map.get(fields, :week_based_year),
          month: Map.get(fields, :month),
          day: Map.get(fields, :day),
          date: date_of_fields(fields)
        }

      _not_read ->
        nil
    end
  end

  # The date of text read as a year, a month and a day and no other field.
  # Read as a map, text is given those three only where one of the patterns
  # made a date of them, the pattern that reads it as a date too, so the
  # date is theirs and the text need not be read again. Text with another
  # field, a weekday or a week, is read as a date in its own right.
  defp date_of_fields(%{calendar: calendar, year: year, month: month, day: day} = fields)
       when map_size(fields) == 4 and is_integer(year) and is_integer(month) and
              is_integer(day) do
    case Date.new(year, month, day, calendar) do
      {:ok, date} -> date
      {:error, _no_such_date} -> nil
    end
  end

  defp date_of_fields(_fields), do: nil

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

      # Anything other than a parse failure, such as an invalid locale or an
      # unavailable calendar, is reported as it stands.
      {:error, _other} = error ->
        error
    end
  end

  defp build_range(from, to, allow_inverted) do
    case Localize.Calendar.compare_days(from, to) do
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

  # A range no interval pattern reads is two dates joined: by the locale's
  # fallback pattern, as the formatter joins them, or by a separator people
  # write. The text is cut at each place a join's separator is found, and
  # the first cut whose two sides are dates is the range. The separator may
  # be in the dates themselves: `da`'s fallback pattern is "{0}-{1}", and a
  # calendar of weeks' range "2026-W25-2-2026-W27-1". Where no cut gives two
  # dates, the error is the first cut's.
  defp read_joined_range(input, locale, calendars, options) do
    case range_cuts(input, range_joins(locale, calendars)) do
      [] ->
        {:error,
         DateRangeParseError.exception(input: input, reason: :no_separator, locale: locale)}

      [{from_string, to_string} | _rest] = cuts ->
        Enum.find_value(cuts, &range_at_cut(&1, options)) ||
          parse_range_pair(from_string, to_string, options)
    end
  end

  defp range_at_cut({from_string, to_string}, options) do
    case parse_range_pair(from_string, to_string, options) do
      {:ok, _range} = range -> range
      {:error, _reason} -> nil
    end
  end

  # The separators people join two dates with, where the locale's pattern
  # is not used: the dashes, a tilde, "to", and a hyphen or a slash between
  # spaces.
  @written_range_joins for separator <- ["–", "—", "−", "〜", "~", "to", " - ", " / "],
                           do: {"", separator, :earliest_first}

  @doc false
  # The ways two dates are joined into a range, each the text before the
  # first date, the separator and which date is written first: as the
  # fallback pattern of each of the calendars joins them, then as people
  # write them. The text's own calendar comes first: a calendar of weeks'
  # dates are read as Gregorian ones but written with CLDR's generic
  # calendar's patterns, `es-PA`'s "{0} a el {1}" and `fr-CH`'s
  # "du {0} au {1}" where the Gregorian calendar's is "{0} – {1}". `kek`'s
  # Gregorian pattern is "{1} – {0}", the later date first, and a separator
  # a fallback pattern has is read in that pattern's order alone: an en
  # dash is not also the earlier date first there.
  @spec range_joins(atom() | String.t() | Localize.LanguageTag.t(), [module()]) ::
          [{String.t(), String.t(), :earliest_first | :latest_first}]
  def range_joins(locale, calendars) do
    fallback = fallback_range_joins(locale, calendars)

    stated =
      for {before, separator, _order} <- fallback,
          String.trim(before) == "",
          into: MapSet.new(),
          do: String.trim(separator)

    fallback ++
      Enum.reject(@written_range_joins, fn {_before, separator, _order} ->
        String.trim(separator) in stated
      end)
  end

  @doc false
  # The joins of the calendars' fallback patterns alone.
  @spec fallback_range_joins(atom() | String.t() | Localize.LanguageTag.t(), [module()]) ::
          [{String.t(), String.t(), :earliest_first | :latest_first}]
  def fallback_range_joins(locale, calendars) do
    for calendar <- Enum.uniq(calendars),
        {:ok, intervals} <- [Format.interval_formats(locale, cldr_calendar_type(calendar))],
        join <- fallback_join(Map.get(intervals, :interval_format_fallback)),
        uniq: true,
        do: join
  end

  defp fallback_join([0, separator, 1]) when is_binary(separator),
    do: [{"", separator, :earliest_first}]

  defp fallback_join([1, separator, 0]) when is_binary(separator),
    do: [{"", separator, :latest_first}]

  defp fallback_join([before, 0, separator, 1]) when is_binary(before) and is_binary(separator),
    do: [{before, separator, :earliest_first}]

  defp fallback_join([before, 1, separator, 0]) when is_binary(before) and is_binary(separator),
    do: [{before, separator, :latest_first}]

  defp fallback_join(_other_shape), do: []

  # Every way the joins cut the text in two, the earlier date's text first.
  # A separator is looked for as the pattern has it, between its spaces,
  # before it is looked for without them, so `el`'s " - " cuts
  # "2026-W25-2 - 2026-W27-1" between its dates.
  defp range_cuts(input, joins) do
    cuts =
      for {before, separator, order} <- joins,
          {:ok, text} <- [after_join_start(input, String.trim(before))],
          separator <- Enum.uniq([separator, String.trim(separator)]),
          separator != "",
          {left, right} <- cuts_at(text, separator),
          left = String.trim(left),
          right = String.trim(right),
          left != "" and right != "" do
        if order == :earliest_first, do: {left, right}, else: {right, left}
      end

    Enum.uniq(cuts)
  end

  defp after_join_start(input, ""), do: {:ok, input}

  defp after_join_start(input, before) do
    if String.starts_with?(input, before),
      do: {:ok, String.replace_prefix(input, before, "")},
      else: :error
  end

  # The text on each side of each place the separator is found.
  defp cuts_at(text, separator) do
    parts = String.split(text, separator)

    for index <- 1..(Enum.count(parts) - 1)//1 do
      {left, right} = Enum.split(parts, index)
      {Enum.join(left, separator), Enum.join(right, separator)}
    end
  end

  # ── ISO 8601 ─────────────────────────────────────────────────

  @doc false
  # The date ISO 8601 writes as `input`, in `Calendar.ISO`: a calendar date,
  # a day of the year or a week date, with its hyphens or without them.
  # `Localize.DateTime.Parser` reads the date before a `T` with it, and
  # MessageFormat 2 its date literals.
  @spec from_iso8601(String.t()) :: {:ok, Date.t()} | :error
  def from_iso8601(input) when is_binary(input) do
    if String.valid?(input), do: iso_forms(input), else: :error
  end

  # An ISO 8601 date is read in `Calendar.ISO` and returned in the
  # `:calendar` module.
  defp try_iso(input, calendar_module) do
    case iso_forms(input) do
      {:ok, date} -> in_calendar(date, calendar_module) || :error
      :error -> :error
    end
  end

  # The first of ISO 8601's forms that reads the input, in `Calendar.ISO`.
  defp iso_forms(input) do
    with :error <- try_iso_extended(input),
         :error <- try_iso_basic(input),
         :error <- try_iso_ordinal(input) do
      try_iso_week_date(input)
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

  # `YYYY-DDD` and `YYYYDDD` (ordinal date — year + day-of-year, 1..366):
  # that day of the year's days, as `Localize.Calendar.ISO` gives them.
  defp try_iso_ordinal(input) do
    with [_, y, d] <- Regex.run(~r/\A(\d{4})-?(\d{3})\z/u, input),
         {year, ""} <- Integer.parse(y),
         {day_of_year, ""} <- Integer.parse(d),
         %Date.Range{} = days <- Localize.Calendar.ISO.year(year),
         true <- day_of_year in 1..Enum.count(days)//1 do
      {:ok, Date.add(days.first, day_of_year - 1)}
    else
      _ -> :error
    end
  end

  # `YYYY-Www-D` and `YYYYWwwD` (ISO week date — week-based year + week
  # number + day of the week, 1 for Monday to 7): that day of ISO 8601's
  # week, which `Localize.Calendar.ISO` answers where a question carries no
  # locale. A week the year does not have, `2026-W54-1` or `2025-W53-1`, is
  # no date.
  defp try_iso_week_date(input) do
    with [_, y, _separator, w, d] <- Regex.run(~r/\A(\d{4})(-?)W(\d{2})\2(\d)\z/u, input),
         {year, ""} <- Integer.parse(y),
         {week, ""} <- Integer.parse(w),
         {day, ""} <- Integer.parse(d),
         true <- day in 1..7,
         %Date.Range{first: monday} <- Localize.Calendar.ISO.week(year, week) do
      {:ok, Date.add(monday, day - 1)}
    else
      _ -> :error
    end
  end

  # ── Locale patterns ──────────────────────────────────────────

  # `inputs` are the spellings of one input to try, in order: as given,
  # then with a leading weekday stripped. A pass tries every spelling
  # before the next pass starts, so a strict match on either is
  # preferred to a lax one.
  defp try_locale_patterns(inputs, locale, calendar_module, own_calendar, reference, as) do
    with {:ok, patterns, ctx} <- locale_patterns(locale, calendar_module, own_calendar, reference) do
      transliterated = inputs |> Enum.map(&transliterate_digits(&1, locale)) |> Enum.uniq()

      read_patterns(patterns, transliterated, ctx, as) ||
        read_by_narrow_era(patterns, transliterated, ctx, as) ||
        {:error, no_match_error(hd(inputs), locale, calendar_module)}
    end
  end

  # The reading of the inputs that takes the era by a narrow name the
  # pattern does not state (`narrow_era_branches/2`), tried once no pattern
  # reads them otherwise, so a pattern that states the narrow name, or reads
  # no era at all, is never passed over for one that only allows it.
  defp read_by_narrow_era(patterns, inputs, ctx, as) do
    patterns
    |> Enum.filter(fn {_kind, pattern} -> era_field?(pattern) end)
    |> read_patterns(inputs, %{ctx | narrow_eras: true}, as)
  end

  defp era_field?(pattern) do
    pattern
    |> pattern_text()
    |> tokenize_pattern()
    |> Enum.any?(&match?({:G, _count}, &1))
  end

  # The first reading of the inputs any of the patterns gives, or `nil`.
  defp read_patterns(patterns, inputs, ctx, :struct),
    do: run_candidate_pass(patterns, inputs, ctx, :struct)

  # Pass 1 — strict: only accept a pattern whose fields construct a valid
  # date. This filters out misleading regex matches like `MMM y` against
  # "May 5" (which would yield month=5, year=5). The winning pattern's
  # fields are then surfaced as a map, with the synthesised year stripped
  # if the user didn't supply one.
  #
  # Pass 2 — lax: needed for legitimately partial inputs that can't
  # construct a date even with the reference year (e.g. `"2026"` alone, or
  # `"May"` alone).
  defp read_patterns(patterns, inputs, ctx, :map) do
    run_candidate_pass(patterns, inputs, ctx, {:map, :strict}) ||
      run_candidate_pass(lax_order(patterns), inputs, ctx, {:map, :lax})
  end

  # The patterns a calendar's dates are read with in a locale, in the order
  # they are tried, and the names and rules their fields are read with.
  defp locale_patterns(locale, calendar_module, own_calendar, reference) do
    cldr_calendar = cldr_calendar_type(calendar_module)

    with {:ok, available} <- Format.available_formats(locale, cldr_calendar),
         {:ok, months_data} <- LCalendar.months(locale, cldr_calendar) do
      # The first pattern to read the input wins, so they are taken in a
      # fixed order: the locale's standard formats, which the formatter
      # writes, then the available formats, which come from a map whose
      # order varies between VM runs, the most specific first. So `de`'s
      # "01.04.66 BE" is its short "dd.MM.yy G", not "d.M.y G" with the year
      # 66, and `pl`'s Chinese "1 12 jia-chen" its medium "d MMM U".
      available_patterns =
        available
        |> collect_patterns()
        |> Enum.sort_by(fn {_skeleton, pattern} -> pattern_specificity(pattern) end)

      standard = Format.standard_format_entries(locale, cldr_calendar)

      patterns =
        standard
        |> collect_patterns()
        |> Enum.concat(available_patterns)
        |> Enum.uniq_by(fn {_skeleton, pattern} -> pattern end)

      ctx = field_context(locale, calendar_module, own_calendar, reference, months_data)

      # The compiled regex for each pattern is a pure function of
      # (locale, calendar) — the CLDR name data and lenient rules are
      # both derived from them — so the whole set is built once and
      # cached. Without this every parse (especially a *failing* one,
      # which exhausts all ~60 patterns) rebuilds and recompiles them.
      ctx = Map.put(ctx, :regexes, pattern_regexes(patterns, ctx))
      ctx = Map.put(ctx, :mixed_years, mixed_year_fields?(patterns, ctx))

      ctx =
        Map.put(
          ctx,
          :variants,
          variant_patterns(standard) |> MapSet.union(variant_patterns(available))
        )

      {:ok, patterns, ctx}
    end
  end

  # The patterns a format has as its variant, which the formatter writes
  # only when it is asked for one (`en-CA`'s day-first numeric dates).
  defp variant_patterns(entries) do
    for {_skeleton, %{variant: variant}} <- entries,
        is_binary(variant),
        into: MapSet.new(),
        do: variant
  end

  # The lax pass takes the patterns in a fixed order, day-bearing first,
  # as the first possible reading wins (see `run_locale_pass/4`).
  defp lax_order(patterns) do
    Enum.sort_by(patterns, fn {_skeleton, pattern} -> pattern_specificity(pattern) end)
  end

  defp run_candidate_pass(patterns, inputs, ctx, pass_as) do
    Enum.find_value(inputs, &run_locale_pass(written_first(patterns, &1, ctx), &1, ctx, pass_as))
  end

  # The patterns whose own text is in the input, in the order they are
  # tried, before those that read it only through a lenient separator, as
  # an interval's patterns are taken (`written_first_of/2`): the text
  # a pattern writes holds its separators as they are. `af`'s `GyMd` in the
  # generic calendar is "M-d-y G" beside a `yyyyMd` of "d/M/y GGGGG", and
  # each reads the "1-7-8 Reiwa" the first writes, the second, a hyphen for
  # its slash, as the first of July. A variant is not moved up: the
  # formatter writes it only when it is asked to, so `en-CA`'s "5/3" stays
  # its default "MM-dd"'s third of May, read through a lenient separator,
  # before its variant "d/M"'s fifth of March.
  defp written_first(patterns, input, ctx) do
    plain_input = plain_spaces(input)

    {written, lenient} =
      Enum.split_with(patterns, fn {_kind, pattern} ->
        text = pattern_text(pattern)
        not MapSet.member?(ctx.variants, text) and literals_in?(text, plain_input)
      end)

    written ++ lenient
  end

  # A day the input gave is never read as something else: once a pattern
  # with a day has matched, even with a day no date has, the lax pass
  # tries no pattern without one, so "June 31" is not June 2031.
  defp run_locale_pass(patterns, input, ctx, {:map, :lax}) do
    {day_patterns, other_patterns} =
      Enum.split_with(patterns, fn {_skeleton, pattern} ->
        pattern_has_day?(pattern_text(pattern))
      end)

    case first_lax_match(day_patterns, input, ctx) do
      {:ok, map} ->
        {:ok, map}

      :error ->
        nil

      :no_match ->
        case first_lax_match(other_patterns, input, ctx) do
          {:ok, map} -> {:ok, map}
          _no_match_or_error -> nil
        end
    end
  end

  # Where the patterns write a year both as the calendar's year and as
  # its related Gregorian year, the same digits read as years far apart
  # (`ko`'s Chinese "2020. 5. 1." is "y. M. d.", a year numbered 2020, and
  # "r. M. d.", the year that began in 2020), so the reading nearest the
  # reference year is taken.
  defp run_locale_pass(patterns, input, %{mixed_years: true} = ctx, pass_as) do
    patterns
    |> Enum.flat_map(fn {_kind, pattern} ->
      case match_pattern(input, pattern, ctx, pass_as) do
        {:ok, %Date{} = date} -> date |> in_calendar(ctx.calendar_module) |> List.wrap()
        {:ok, %{} = map} -> [{:ok, map}]
        _no_match_or_error -> []
      end
    end)
    |> Enum.min_by(&reading_distance(&1, ctx.reference_year), fn -> nil end)
  end

  defp run_locale_pass(patterns, input, ctx, pass_as) do
    Enum.find_value(patterns, fn {_kind, pattern} ->
      case match_pattern(input, pattern, ctx, pass_as) do
        {:ok, %Date{} = date} -> in_calendar(date, ctx.calendar_module)
        {:ok, %{} = map} -> {:ok, map}
        _no_match_or_error -> nil
      end
    end)
  end

  defp reading_distance({:ok, %{year: year}}, reference_year) when is_integer(year),
    do: abs(year - reference_year)

  defp reading_distance(_reading, _reference_year), do: 0

  # Whether the patterns write the year both as the calendar's year (`y`)
  # and as its related Gregorian year (`r`). Cached with the regexes.
  defp mixed_year_fields?(patterns, ctx) do
    key = {__MODULE__, :mixed_year_fields, ctx.locale, ctx.calendar_module}

    case :persistent_term.get(key, nil) do
      nil ->
        letters =
          for {_skeleton, pattern} <- patterns,
              {letter, _count} when letter in [:y, :r] <- tokenize_pattern(pattern_text(pattern)),
              into: MapSet.new(),
              do: letter

        mixed = MapSet.size(letters) == 2
        :persistent_term.put(key, mixed)
        mixed

      mixed ->
        mixed
    end
  end

  # The first possible reading among `patterns` as `{:ok, map}`, else
  # `:error` when a pattern matched with fields no date has, else
  # `:no_match`.
  defp first_lax_match(patterns, input, ctx) do
    Enum.reduce_while(patterns, :no_match, fn {_skeleton, pattern}, outcome ->
      case match_pattern(input, pattern, ctx, {:map, :lax}) do
        {:ok, map} -> {:halt, {:ok, map}}
        :error -> {:cont, :error}
        :no_match -> {:cont, outcome}
      end
    end)
  end

  @doc false
  # The `:calendar` option is a calendar module, `Calendar.ISO` by default,
  # and the date is built and returned in it. Anything else, a CLDR calendar
  # type or a string included, is an unknown calendar. Every parse entry
  # point runs this first, so the ISO 8601 path and the locale patterns
  # report a calendar the same way.
  @spec calendar_option(Keyword.t()) :: {:ok, module()} | {:error, Exception.t()}
  def calendar_option(options) do
    calendar_module = Keyword.get(options, :calendar, Calendar.ISO)

    with :ok <- Localize.Calendar.validate_calendar(%{calendar: calendar_module}) do
      {:ok, calendar_module}
    end
  end

  # The calendar whose own weeks and quarters the input's week and quarter
  # fields count: the calendar asked for, which reading its dates in another
  # (`parsing_calendar/0`) does not change. An unusable one leaves the
  # calendar the input is read in.
  defp own_calendar(options, calendar_module) do
    own_calendar = Keyword.get(options, :own_calendar, calendar_module)

    case Localize.Calendar.validate_calendar(%{calendar: own_calendar}) do
      :ok -> own_calendar
      {:error, _unusable} -> calendar_module
    end
  end

  @doc false
  # A date written for a calendar is read in the calendar it names for
  # parsing (its `parsing_calendar/0`) and converted into it: itself, or
  # `Calendar.ISO` for a calendar of weeks, whose written month and day
  # name no single week, so "Feb 1, 2024" is read as 1 February 2024. A
  # date read in another calendar is read whole and comes back whole, as a
  # partial date of one calendar has no fields in the other. `parse` reads
  # the input in a calendar with the options given, and `finalise` gives a
  # converted value the shape `:as` asks for.
  @spec read_for_calendar(Keyword.t(), (Keyword.t(), module() -> term()), (term(), atom() ->
                                                                             term())) ::
          term()
  def read_for_calendar(options, parse, finalise) do
    with {:ok, calendar_module} <- calendar_option(options),
         {:ok, parsing} <- Localize.Calendar.parsing_calendar(calendar_module) do
      read_in(parsing, calendar_module, options, parse, finalise)
    end
  end

  defp read_in(calendar_module, calendar_module, options, parse, _finalise),
    do: parse.(options, calendar_module)

  defp read_in(parsing, calendar_module, options, parse, finalise) do
    as = Keyword.get(options, :as, :struct)
    options = Keyword.merge(options, calendar: parsing, own_calendar: calendar_module)

    with {:ok, value} <- parse.(Keyword.put(options, :as, :struct), parsing),
         {:ok, converted} <- convert_value(value, calendar_module) do
      weeks = weeks_without_days(as, converted, options, parsing, parse)
      {:ok, converted |> finalise.(as) |> without_days(weeks)}
    end
  end

  # A week written for the calendar names no day, so read as a map it is
  # not the whole date of its first day but the fields its days share, as
  # the formatter writes a date without its day: the year and the week a
  # calendar of weeks holds in its month field, `%{year: 2026, month: 25}`
  # for "week 25 of 2026". The input is read again for the fields it
  # carries, and a year and a week alone are that week of the calendar's
  # own, whose days it names itself (`Localize.Calendar.week/4`), where the
  # whole reading is that week's first day: an ISO 8601 week ("2026-W25")
  # that is not one of the calendar's own weeks stays the day it was read
  # as. Each end of an interval is taken on its own.
  defp weeks_without_days(:map, converted, options, parsing, parse) do
    locale = Keyword.get(options, :locale) || Localize.get_locale()
    week_data = Localize.DateTime.Week.config(locale)

    case {parse.(Keyword.put(options, :as, :map), parsing), converted} do
      {{:ok, {%{} = from, %{} = to}}, %Date.Range{first: first, last: last}} ->
        {week_without_day(from, first, week_data), week_without_day(to, last, week_data)}

      {{:ok, %{} = fields}, %Date{} = first_day} ->
        week_without_day(fields, first_day, week_data)

      _unread ->
        nil
    end
  end

  defp weeks_without_days(_as, _converted, _options, _parsing, _parse), do: nil

  defp week_without_day(%{week_of_year: week} = fields, %Date{} = first_day, week_data) do
    week_year = Map.get(fields, :week_based_year) || Map.get(fields, :year)
    others = Map.keys(fields) -- [:calendar, :year, :week_based_year, :week_of_year]

    with [] <- others,
         true <- is_integer(week_year),
         {:ok, days} <- Localize.Calendar.week(first_day.calendar, week_year, week, week_data),
         %Date{calendar: calendar, year: year, month: month} <- days.first,
         %Date{year: ^year, month: ^month} <- days.last,
         :eq <- Localize.Calendar.compare_days(days.first, first_day) do
      %{calendar: calendar, year: year, month: month}
    else
      _not_one_week -> nil
    end
  end

  defp week_without_day(_fields, _first_day, _week_data), do: nil

  defp without_days(value, nil), do: value
  defp without_days(%{} = _whole, %{} = week), do: week

  defp without_days({from, to}, {from_week, to_week}),
    do: {from_week || from, to_week || to}

  @doc false
  # A value read in one calendar, in another: a date, a range of dates or
  # a date and time, as `Date.convert/2` and its kin convert them. A value
  # the calendar cannot take is an error, never left in the calendar it
  # was read in.
  @spec convert_value(term(), module()) :: {:ok, term()} | {:error, Exception.t()}
  def convert_value(%Date{} = date, calendar_module),
    do: converted(Date.convert(date, calendar_module), date, calendar_module)

  def convert_value(%Date.Range{first: first, last: last, step: step}, calendar_module) do
    with {:ok, first} <- convert_value(first, calendar_module),
         {:ok, last} <- convert_value(last, calendar_module) do
      {:ok, Date.range(first, last, step)}
    end
  end

  def convert_value(%NaiveDateTime{} = naive, calendar_module),
    do: converted(NaiveDateTime.convert(naive, calendar_module), naive, calendar_module)

  def convert_value(%DateTime{} = datetime, calendar_module),
    do: converted(DateTime.convert(datetime, calendar_module), datetime, calendar_module)

  defp converted({:ok, _converted} = ok, _value, _calendar_module), do: ok

  defp converted({:error, _incompatible}, value, calendar_module) do
    {:error,
     Localize.InvalidValueError.exception(
       value: value,
       expected: "a value convertible to #{inspect(calendar_module)}"
     )}
  end

  @doc false
  # The CLDR calendar type of a calendar module, which selects the CLDR
  # patterns and names the input is read with.
  @spec cldr_calendar_type(module()) :: atom()
  defdelegate cldr_calendar_type(calendar_module), to: Localize.Calendar

  # A date read in another calendar, in `calendar_module`, or `nil` where
  # the calendar cannot take it, which is then no reading of the input:
  # a date is never returned in a calendar other than the one asked for.
  defp in_calendar(%Date{} = date, calendar_module) do
    case convert_value(date, calendar_module) do
      {:ok, _date} = ok -> ok
      {:error, _not_convertible} -> nil
    end
  end

  # ── Digit transliteration ────────────────────────────────────

  # Translate non-Latin digit runs to Latin before integer
  # parsing. Walk the locale's default number system; for
  # numeric systems with custom digit sets, build the
  # translation table on the fly. `Localize.Time.Parser` reads
  # a time's digits the same way.
  @doc false
  def transliterate_digits(input, locale) do
    case locale_digits(locale) do
      nil -> input
      digits -> digit_translate(input, digits)
    end
  end

  # The digits of the locale's default number system, or `nil` where they
  # are Latin or the system has none.
  defp locale_digits(locale) do
    with {:ok, system} <- Localize.Number.System.number_system_from_locale(locale),
         {:ok, digits} when is_binary(digits) and digits not in ["", "0123456789"] <-
           Localize.Number.System.number_system_digits(system) do
      digits
    else
      _ -> nil
    end
  end

  # The input is read with its digits in Latin, so names the locale writes
  # with its own digits are read in Latin digits too: `dz`'s abbreviated
  # months and its quarters are Tibetan numbers, and `fa`'s short weekdays
  # and the year ranges of `ar-EG`'s Japanese era names carry its digits.
  defp latin_names(data, nil), do: data
  defp latin_names(name, digits) when is_binary(name), do: digit_translate(name, digits)

  defp latin_names(%{} = data, digits),
    do: Map.new(data, fn {key, value} -> {key, latin_names(value, digits)} end)

  defp latin_names(other, _digits), do: other

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

  # The locale's names and rules the fields of the calendar's patterns
  # are read with, shared by date and interval patterns. `:numbers` is
  # the numbering a pattern writes its fields in, set as each pattern is
  # compiled.
  defp field_context(locale, calendar_module, own_calendar, reference, months_data) do
    cldr_calendar = cldr_calendar_type(calendar_module)
    month_patterns = maybe_load_month_patterns(locale, cldr_calendar)
    digits = locale_digits(locale)

    %{
      quarters: latin_names(maybe_load_quarters(locale, cldr_calendar), digits),
      days: latin_names(maybe_load_days(locale, cldr_calendar), digits),
      locale: locale,
      months: latin_names(months_data, digits),
      eras: latin_names(maybe_load_eras(locale, era_calendar_type(calendar_module)), digits),
      cyclic_years: maybe_load_cyclic_years(locale, cldr_calendar),
      month_patterns: month_patterns,
      traditional_months: traditional_months?(calendar_module, month_patterns),
      numbers: %{},
      two_digit_year: false,
      lenient: load_lenient_date(locale),
      reference_year: reference.year,
      implied_era: implied_era(reference, calendar_module),
      cyclic_year_written: cyclic_year_written?(reference, calendar_module, locale),
      narrow_eras: false,
      interval_order: :earliest_first,
      variants: MapSet.new(),
      mixed_years: false,
      calendar_module: calendar_module,
      own_calendar: own_calendar,
      week_config: Localize.DateTime.Week.config(locale)
    }
  end

  # The era a year written without one is of, in a calendar that writes
  # its years as years of an era (the Japanese calendars): the reference
  # date's, as ICU takes the current era. `nil` where the calendar's years
  # are written as they are numbered.
  defp implied_era(%{calendar: calendar_module} = reference, calendar_module) do
    with {:ok, shown} when shown != reference.year <- LCalendar.displayed_year(reference),
         {:ok, {_year_of_era, era}} <- LCalendar.year_of_era(reference) do
      era
    else
      _year_as_numbered -> nil
    end
  end

  defp implied_era(_reference, _calendar_module), do: nil

  # Whether the formatter writes a year of the calendar as its place in the
  # sixty-year cycle rather than as its number, as TR35's `y` is in a
  # calendar of cyclic years (`Localize.Calendar.cycle_place/2`): ICU4C
  # writes the Chinese year that began in 2023 as 40. It does where the
  # locale's data names the calendar's years by a cycle, and where the
  # calendar itself displays the place, its `calendar_year/3` answering the
  # reference year's place in the cycle and not its number.
  defp cyclic_year_written?(
         %{calendar: calendar_module, year: year} = reference,
         calendar_module,
         locale
       )
       when is_integer(year) do
    match?({:ok, _place}, LCalendar.cycle_place(reference, locale)) or
      case LCalendar.displayed_year(reference) do
        {:ok, shown} when shown != year -> cyclic_position(year, calendar_module) == shown
        _year_as_numbered -> false
      end
  end

  defp cyclic_year_written?(_reference, _calendar_module, _locale), do: false

  # The CLDR calendar a calendar names its eras from: its
  # `era_calendar_type/0` where it has one (Calendrical's lunisolar
  # Japanese calendar names its months from the Chinese calendar and its
  # eras from the Japanese one), else its CLDR calendar type.
  defp era_calendar_type(calendar_module),
    do: Localize.Calendar.era_calendar_type(calendar_module)

  # A lunisolar calendar writes a month as a number in its traditional
  # numbering when the locale gives the calendar a numeric leap-month
  # pattern, as the formatter does ("2bis", "闰2").
  defp traditional_months?(_calendar_module, month_patterns) do
    match?([_ | _], get_in(month_patterns, [:numeric, :all, :leap]))
  end

  defp maybe_load_month_patterns(locale, calendar) do
    case LCalendar.month_patterns(locale, calendar) do
      {:ok, data} -> data
      _ -> %{}
    end
  end

  defp maybe_load_cyclic_years(locale, calendar) do
    case LCalendar.cyclic_years(locale, calendar) do
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
  defp swap_month_day_variants({pattern, numbers}) do
    for swapped <- swap_month_day_variants(pattern), do: {swapped, numbers}
  end

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

  # A comma is dropped from a literal that keeps another separator ("d MMM,
  # y" is "d MMM y"), and a literal that is only a comma becomes a space,
  # so its fields stay apart: `en-ZW`'s "dd MMM,y" swaps to "MMM dd y",
  # where "MMM ddy" would read "May 2019" as 20 May 2019.
  defp strip_commas_in_literals(pattern) do
    pattern
    |> tokenize_pattern()
    |> Enum.map(fn
      {:lit, text} -> {:lit, strip_commas(text)}
      other -> other
    end)
    |> detokenize_pattern()
  end

  defp strip_commas(text) do
    case String.replace(text, ",", "") do
      "" when text != "" -> " "
      stripped -> stripped
    end
  end

  defp detokenize_pattern(tokens) do
    Enum.map_join(tokens, "", &detokenize_token/1)
  end

  defp detokenize_token({:lit, ""}), do: ""

  defp detokenize_token({:lit, text}) when is_binary(text) do
    if Regex.match?(~r/[A-Za-z]/u, text) do
      # ASCII letters, reserved as pattern letters (TR35), need
      # quoting so the re-tokenizer treats them as text.
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

  # The standard pattern is the one the formatter writes unless it is asked
  # for the variant, so it is read first: `en-CA`'s Chinese short date is
  # "M/d/r" beside the variant "d/M/r", and the "5/2/2026" it writes is the
  # second day of the fifth month.
  defp resolve_pattern_variants(%{variant: variant, standard: standard})
       when is_binary(variant) and is_binary(standard),
       do: [standard, variant]

  # A pattern that writes its fields in another numbering (`d=hanidays`
  # in `zh`'s Chinese calendar) keeps it, so the fields are read in it.
  defp resolve_pattern_variants(%{format: pattern, number_system: numbers})
       when is_binary(pattern) and is_map(numbers),
       do: [{pattern, numbers}]

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

  # A pattern is read by code points: a quote or a pattern letter is one,
  # and a combining mark beside it is literal text. Read by graphemes,
  # `nnh`'s "'lyɛ'̌ʼ d 'na' MMMM, y" closes no quote, its caron joining
  # the closing quote, and none of its long dates parse.
  defp tokenize_pattern(pattern) do
    pattern
    |> String.codepoints()
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

  defp cldr_letter?(char) when char in ~w(y Y M d E G L c Q q w W D e F r U), do: true
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
  defp classify_plain({:join, _}), do: :literal
  defp classify_plain(_), do: :field

  defp maybe_prefix_capture(regex, ""), do: regex
  defp maybe_prefix_capture(regex, prefix), do: rename_capture(regex, prefix)

  defp field_regex({:lit, text}, _months, _eras, lenient, _ctx) do
    {:plain, expand_literal(text, lenient)}
  end

  defp field_regex({:join, text}, _months, _eras, lenient, _ctx) do
    {:plain, expand_join(text, lenient)}
  end

  # A calendar without a before era writes a year below 1 with its
  # sign (`-456 BE`), as ASCII hyphen-minus or U+2212 MINUS SIGN; the
  # two low-order digits of `yy` carry none.
  defp field_regex({:y, count}, _months, _eras, _lenient, ctx) do
    digit = digit_class(ctx, "y")

    regex =
      cond do
        # `he` writes a Hebrew date's year in Hebrew numerals, "ה׳תשפ״ד".
        field_numbering(ctx, "y") == :hebr ->
          "(?P<year>#{Localize.Number.HebrewNumerals.regex_source()})"

        count == 2 ->
          "(?P<year>#{digit}{2})"

        true ->
          year_numerals(ctx, "(?P<year>[-−]?#{digit}{1,4})")
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

  # `r`, the related Gregorian year, is written in Latin digits (TR35).
  defp field_regex({:r, _count}, _months, _eras, _lenient, _ctx) do
    {:capture, :related_year, "(?P<related_year>[-−]?\\d{1,4})"}
  end

  # `U`, the cyclic year name (甲子, "jia-zi"), or the year as `y`
  # writes it where the locale has no cyclic names (TR35).
  defp field_regex({:U, count}, months, eras, lenient, ctx) do
    case cyclic_year_regex(Map.get(ctx, :cyclic_years), cyclic_width(count)) do
      {:branches, regex} -> {:capture, :cyclic_year, regex}
      :none -> field_regex({:y, count}, months, eras, lenient, ctx)
    end
  end

  # A lunisolar calendar's month written as a number is its traditional
  # number, a leap month in the locale's numeric leap pattern ("2bis",
  # "闰2"). A month written in an algorithmic numbering (`haw`'s
  # `romanlow`, "31/xii/24") is read as the formatter writes it.
  defp field_regex({:M, count}, _months, _eras, lenient, ctx) when count <= 2 do
    digit = digit_class(ctx, "M")

    case {numeral_names(ctx, "M", 1..13), numeric_leap_affixes(ctx)} do
      {[_ | _] = numerals, _leap} ->
        {:capture, :month, numeral_regex(numerals, "__n")}

      {[], nil} ->
        {:capture, :month, "(?P<month>#{digit}{1,2})"}

      {[], {prefix, suffix}} ->
        {:capture, :traditional_month,
         optional_capture("month_leap_before", prefix, lenient) <>
           "(?P<traditional_month>#{digit}{1,2})" <>
           optional_capture("month_leap_after", suffix, lenient)}
    end
  end

  defp field_regex({:M, count}, months, _eras, _lenient, ctx) when count in 3..5 do
    month_patterns = Map.get(ctx, :month_patterns, %{})
    {:capture, :month, month_name_regex(months, @month_name_widths[count], month_patterns)}
  end

  defp field_regex({:L, count}, months, eras, lenient, ctx),
    do: field_regex({:M, count}, months, eras, lenient, ctx)

  # A day written in an algorithmic numbering (`hanidays` in `zh`'s
  # Chinese calendar: 初一, 十一, 廿一) is read as the formatter writes
  # it.
  defp field_regex({:d, _count}, _months, _eras, _lenient, ctx) do
    case numeral_names(ctx, "d", 1..31) do
      [] -> {:capture, :day, "(?P<day>#{digit_class(ctx, "d")}{1,2})"}
      numerals -> {:capture, :day, numeral_regex(numerals, "__h")}
    end
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

  # A field at a length no format writes, such as `QQQQQQ`, which only a
  # pattern a caller gives can hold: it reads nothing, so its pattern
  # matches no text.
  defp field_regex(_field, _months, _eras, _lenient, _ctx), do: {:plain, "(?!)"}

  # The digits a numeric field is written with: Latin (or the locale's
  # own, read as Latin before matching) and those of the numbering the
  # pattern writes the field in (`hanidec` 〇一二… in `ja`'s Chinese
  # calendar).
  defp digit_class(ctx, field) do
    case numbering_digits(field_numbering(ctx, field)) do
      [digits] -> "[\\d" <> Regex.escape(digits) <> "]"
      [] -> "\\d"
    end
  end

  defp field_numbering(ctx, field) do
    numbers = Map.get(ctx, :numbers, %{})
    Map.get(numbers, field) || Map.get(numbers, "all")
  end

  defp numbering_digits(system) do
    case Map.get(Localize.Number.System.number_systems(), system) do
      %{type: :numeric, digits: digits} when is_binary(digits) -> [digits]
      _algorithmic_or_none -> []
    end
  end

  # The numerals an algorithmic numbering (`hanidays`) writes for each
  # of `values` of `field`, as the formatter writes them.
  defp numeral_names(ctx, field, values) do
    with system when not is_nil(system) <- field_numbering(ctx, field),
         %{type: :algorithmic} <- Map.get(Localize.Number.System.number_systems(), system) do
      for value <- values,
          {:ok, numeral} <-
            [Localize.DateTime.Formatter.number_in_system(value, system, ctx.locale)],
          do: {value, numeral}
    else
      _numeric_or_none -> []
    end
  end

  defp numeral_regex(numerals, marker) do
    branches =
      numerals
      |> Enum.sort_by(fn {_value, numeral} -> -byte_size(numeral) end)
      |> Enum.map_join("|", fn {value, numeral} ->
        "(?P<#{marker}#{value}__>#{Regex.escape(numeral)})"
      end)

    "(?:" <> branches <> ")"
  end

  # The years an algorithmic numbering writes otherwise than in digits, each
  # read before the digits of `digits`: `ja`'s Japanese dates are written
  # with `y=jpanyear`, whose first year of an era is 元, "令和元年5月1日". The
  # years asked about are those of an era, none of which has reached a
  # hundred.
  @numeral_years 1..100

  defp year_numerals(ctx, digits) do
    numerals =
      for {year, numeral} <- numeral_names(ctx, "y", @numeral_years),
          numeral != Integer.to_string(year),
          do: {year, numeral}

    case numerals do
      [] -> digits
      numerals -> "(?:" <> numeral_regex(numerals, "__y") <> "|" <> digits <> ")"
    end
  end

  # The text before and after a month's number in the locale's numeric
  # leap-month pattern, in a calendar that writes its months in their
  # traditional numbering: `{"", "bis"}` in `en`, `{"闰", ""}` in `zh`.
  defp numeric_leap_affixes(%{traditional_months: true, month_patterns: month_patterns}) do
    case Enum.split_while(get_in(month_patterns, [:numeric, :all, :leap]), &(&1 != 0)) do
      {prefix, [0 | suffix]} -> {Enum.join(prefix), Enum.join(suffix)}
      _no_placeholder -> nil
    end
  end

  defp numeric_leap_affixes(_ctx), do: nil

  defp optional_capture(_name, "", _lenient), do: ""

  defp optional_capture(name, text, lenient),
    do: "(?P<#{name}>" <> expand_literal(text, lenient) <> ")?"

  # The locale's cyclic year names, by place in the cycle. CLDR gives
  # abbreviated names; a name of any width is read.
  defp cyclic_year_regex(cyclic_years, width) when is_map(cyclic_years) do
    names_by_width = get_in(cyclic_years, [:years, :format]) || %{}

    declared =
      indexed_names(Map.get(names_by_width, width) || Map.get(names_by_width, :abbreviated))

    lenient =
      Enum.flat_map([:wide, :abbreviated, :narrow], &indexed_names(Map.get(names_by_width, &1)))

    grouped_name_regex(declared, lenient, "__u")
  end

  defp cyclic_year_regex(_cyclic_years, _width), do: :none

  defp cyclic_width(count) when count in 1..3, do: :abbreviated
  defp cyclic_width(4), do: :wide
  defp cyclic_width(_count), do: :narrow

  defp indexed_names(names) when is_map(names) do
    for {index, name} when is_integer(index) and is_binary(name) <- names, do: {index, name}
  end

  defp indexed_names(_names), do: []

  # A comma is optional only in a literal that also has a space, which the
  # input must still give ("May 5 2026" for "MMM d, y"). A comma that is
  # its literal's only separator is kept: `en-ZW`'s "dd MMM,y" would
  # otherwise read "May 2019" as 20 May 2019, its day and year run
  # together.
  defp expand_literal(text, lenient) do
    graphemes = String.graphemes(text)
    optional_comma? = Enum.any?(graphemes, &space_char?/1)

    Enum.map_join(graphemes, &expand_char(&1, lenient, optional_comma?))
  end

  # The text that joins an interval's two dates. Where it has a dash, the
  # spaces about the dash are the writer's to leave out or put in: TR35's
  # parsing has spaces "ignored (except to delimit the tokens of the input
  # string)", and a dash delimits without them. `en`'s "MMM d – d, y" reads
  # "Jun 16–20, 2026" and `de`'s "dd.–dd.MM.y" reads "16. – 20.06.2026".
  # Only the spaces beside a dash are so: `hy`'s "dd MMM, y թ․ – dd MMM, y
  # թ." keeps the space before its "թ․", and a join of words keeps its
  # spaces, which are what sets the words apart.
  defp expand_join(text, lenient) do
    graphemes = String.graphemes(text)
    optional_comma? = Enum.any?(graphemes, &space_char?/1)

    runs = Enum.chunk_by(graphemes, &space_char?/1)

    [nil | runs]
    |> Enum.concat([nil])
    |> Enum.chunk_every(3, 1, :discard)
    |> Enum.map_join(fn [before, run, later] ->
      if beside_a_dash?(before, run, later),
        do: "",
        else: Enum.map_join(run, &expand_join_char(&1, lenient, optional_comma?))
    end)
  end

  # Whether a run of a join's text is the spaces before or after a dash.
  defp beside_a_dash?(before, [char | _spaces], later) do
    space_char?(char) and
      ((is_list(before) and List.last(before) in @dash_chars) or
         (is_list(later) and hd(later) in @dash_chars))
  end

  defp expand_join_char(char, lenient, optional_comma?) do
    if char in @dash_chars,
      do: @space_class <> expand_char(char, lenient, optional_comma?) <> @space_class,
      else: expand_char(char, lenient, optional_comma?)
  end

  defp expand_char(char, lenient, optional_comma?) do
    cond do
      space_char?(char) ->
        # A literal space in the CLDR pattern requires at least
        # one whitespace character in the input. Inter-field
        # gaps (with no pattern literal between them) use the
        # `*` form via `@space_class` elsewhere.
        @literal_space_class

      char == "," and optional_comma? ->
        # CLDR patterns embed `,` as a structural punctuation
        # marker (e.g., `MMM d, y` between day and year), but
        # informal input routinely drops it (`"May 5 2026"`).
        # The comma is optional where the literal's space-class
        # still requires at least one whitespace char, so `"May
        # d,y"` (comma but no space) still won't false-match.
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

  defp month_name_regex(months_data, declared_width, month_patterns) do
    # CLDR TR35 §6.5 (lenient parsing): the pattern declares a
    # width (`MMM` = abbreviated, `MMMM` = wide), but real-world
    # input may use any of them. We accept both wide and
    # abbreviated names regardless of the pattern's declared
    # width. A narrow name is read only where the pattern writes
    # one and the names tell the months apart
    # (`month_name_widths/2`).
    #
    # Format (`M`) and stand-alone (`L`) names are both accepted
    # for either symbol: ru's format July is "июля" and its
    # stand-alone July "июль", and ru's `yMMMM` is "LLLL y 'г'.".
    #
    # Each index gets exactly ONE named capture group, with
    # internal alternation across the widths' name forms.
    # Duplicate names across widths (en's "May" is the same in
    # both) are deduplicated. Longest-form-first inside the group
    # so the regex prefers `"June"` over `"Jun"` when both could
    # match a prefix of input.
    by_index =
      for context <- [:format, :stand_alone],
          width <- month_name_widths(months_data, declared_width),
          {index, name} <- get_in(months_data, [context, width]) || %{} do
        {index, name, width}
      end
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
    "(?i:" <> Enum.join(leap_month_branches(months_data, month_patterns) ++ branches, "|") <> ")"
  end

  # The widths of name a month field is read in. A narrow name is one
  # letter in most locales, `en`'s "J" being January, June and July, so it
  # is read only where the pattern writes a narrow month and the calendar's
  # narrow names are each one month's and no other month's wide or
  # abbreviated name: `mn`'s `yM` is "y MMMMM" and its narrow months are
  # Roman numerals in the Gregorian calendar, "2026 VI", and digits in the
  # others.
  defp month_name_widths(months_data, :narrow) do
    if distinct_narrow_months?(months_data),
      do: [:wide, :abbreviated, :narrow],
      else: [:wide, :abbreviated]
  end

  defp month_name_widths(_months_data, _declared_width), do: [:wide, :abbreviated]

  defp distinct_narrow_months?(months_data) do
    narrow = month_names(months_data, [:narrow])
    names = narrow ++ month_names(months_data, [:wide, :abbreviated])

    narrow != [] and
      Enum.all?(narrow, fn {name, index} ->
        Enum.all?(names, fn {its_name, its_index} -> its_name != name or its_index == index end)
      end)
  end

  # Each name of the widths with CLDR's number for its month, in lower case,
  # as a name is read whatever its case. A leap-year name of a month (the
  # Hebrew `7_yeartype_leap`, "Adar II") is that month's: its narrow name is
  # the month's own, "7", which the year then places (`named_month/3`).
  defp month_names(months_data, widths) do
    for context <- [:format, :stand_alone],
        width <- widths,
        {index, name} when is_binary(name) <- get_in(months_data, [context, width]) || %{},
        {month, _leap_or_nothing} <- [index |> to_string() |> Integer.parse()],
        uniq: true,
        do: {String.downcase(name), month}
  end

  # A lunisolar calendar's leap months: each month's name in the
  # locale's leap-month pattern for its context and width ("Mo2bis",
  # "闰二月"), tried before the plain names they contain.
  defp leap_month_branches(months_data, month_patterns) do
    for context <- [:format, :stand_alone],
        width <- [:wide, :abbreviated],
        [_ | _] = pattern <- [get_in(month_patterns, [context, width, :leap])],
        {index, name} when is_integer(index) and is_binary(name) <-
          get_in(months_data, [context, width]) || %{} do
      {index, leap_month_name(name, pattern), width}
    end
    |> Enum.group_by(&elem(&1, 0), fn {_index, name, width} -> {name, width} end)
    |> Enum.map(fn {index, name_widths} ->
      forms =
        name_widths
        |> Enum.uniq_by(fn {name, _width} -> name end)
        |> Enum.sort_by(fn {name, _width} -> -byte_size(name) end)
        |> Enum.map_join("|", &name_form/1)

      "(?P<__m#{index}_leap__>#{forms})"
    end)
  end

  defp leap_month_name(name, pattern) do
    [name] |> Localize.Substitution.substitute(pattern) |> IO.iodata_to_binary()
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

  # `Localize.Calendar.eras/2` returns `%{width => %{index => name}}`
  # and keeps CLDR's alternative era names at negative indices: `-1`
  # for era 0 ("BCE") and `-2` for era 1 ("CE"). They fold onto their
  # era here, because a regex group name cannot carry a minus sign and
  # a pattern whose regex does not compile never matches. A name of
  # another width than the pattern's is accepted where it names one era.
  defp era_name_regex(eras_data, width) when is_map(eras_data) do
    declared = era_names(Map.get(eras_data, width) || Map.get(eras_data, :abbreviated))

    lenient =
      Enum.flat_map([:wide, :abbreviated], fn era_width ->
        era_names(Map.get(eras_data, era_width))
      end)

    case name_branches(declared, lenient, "__e") ++
           narrow_era_branches(eras_data, declared ++ lenient) do
      [] -> :none
      branches -> {:branches, "(?i:" <> Enum.join(branches, "|") <> ")"}
    end
  end

  # The narrow name is among an era's other forms: an interval item states
  # its era as `G` and the formatter writes it at the width the format asks
  # for, the narrow "R" of a short date in "R 8/06/16 – 8/06/20". It is one
  # letter in most locales, so a narrow name the pattern does not state is
  # captured under a marker of its own, `__f`, after every name the pattern
  # does read, and a date is read by it only where no pattern reads the text
  # otherwise (`read_by_narrow_era/4`): `sv-AX` writes a Japanese date at
  # `GyMd` as "8-01-07 R", from "y-MM-dd GGGGG", and its short date is
  # "d.M.y G", which would read that text as the 8th of January of Reiwa 7.
  defp narrow_era_branches(eras_data, read) do
    read_names = MapSet.new(read, fn {_index, name} -> String.downcase(name) end)

    unread =
      eras_data
      |> Map.get(:narrow)
      |> era_names()
      |> Enum.reject(fn {_index, name} -> String.downcase(name) in read_names end)

    name_branches([], unread, "__f")
  end

  defp era_names(names) when is_map(names) do
    Enum.flat_map(names, fn
      {index, name} when is_integer(index) and index < 0 and is_binary(name) ->
        [{-1 - index, name}]

      {index, name} when is_integer(index) and is_binary(name) ->
        [{index, name}]

      _other ->
        []
    end)
  end

  defp era_names(_names), do: []

  # A named capture group per index, alternating over that index's
  # names longest first, with the groups ordered by their longest
  # name. The names of the pattern's own width are always included.
  # TR35 §Parsing Dates and Times also accepts a field's other forms
  # "if they are unique", so a lenient name is added only when it
  # belongs to a single index.
  defp grouped_name_regex(declared, lenient, marker) do
    case name_branches(declared, lenient, marker) do
      [] -> :none
      branches -> {:branches, "(?i:" <> Enum.join(branches, "|") <> ")"}
    end
  end

  defp name_branches(declared, lenient, marker) do
    indices_by_name =
      Enum.group_by(declared ++ lenient, &String.downcase(elem(&1, 1)), &elem(&1, 0))

    unique =
      Enum.filter(lenient, fn {_index, name} ->
        match?([_index], Enum.uniq(Map.fetch!(indices_by_name, String.downcase(name))))
      end)

    (declared ++ unique)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.map(fn {index, names} ->
      {index, names |> Enum.uniq() |> Enum.sort_by(&(-byte_size(&1)))}
    end)
    |> Enum.sort_by(fn {_index, [longest | _shorter]} -> -byte_size(longest) end)
    |> Enum.map(fn {index, names} ->
      "(?P<#{marker}#{index}__>#{Enum.map_join(names, "|", &Regex.escape/1)})"
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
  # builder can validate or derive a date from it. The wide,
  # abbreviated and short names of both contexts are accepted
  # alongside the pattern's own width, as TR35 §Parsing Dates
  # and Times asks: input rarely knows which width a pattern
  # declares.
  defp day_name_field(days_data, width, context) when is_map(days_data) do
    declared =
      day_names(get_in(days_data, [context, width]) || get_in(days_data, [:format, width]))

    lenient =
      for name_context <- [:format, :stand_alone],
          name_width <- [:wide, :abbreviated, :short],
          name <- day_names(get_in(days_data, [name_context, name_width])),
          do: name

    case grouped_name_regex(declared, lenient, "__d") do
      :none -> {:plain, "[\\p{L}\\.]+"}
      {:branches, regex} -> {:capture, :day_of_week, regex}
    end
  end

  defp day_name_field(_data, _width, _context),
    do: {:plain, "[\\p{L}\\.]+"}

  defp day_names(names) when is_map(names) do
    for {index, name} when is_integer(index) and is_binary(name) <- names, do: {index, name}
  end

  defp day_names(_names), do: []

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
  # once in `try_locale_patterns/5`: `:months`, `:eras`,
  # `:lenient`, `:reference_year`, `:calendar_module`, plus the
  # `:days`/`:quarters`/`:locale` keys read by `field_regex/5`.
  # Returns %{pattern => compiled_regex_or_nil} for every pattern, cached
  # in :persistent_term keyed by {locale, calendar module}: calendars that
  # share a CLDR type can name their eras or number their months
  # differently. One write per cold (locale, calendar); every later parse
  # reads precompiled regexes.
  defp pattern_regexes(patterns, ctx) do
    key = {__MODULE__, :pattern_regexes, ctx.locale, ctx.calendar_module}

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
    ctx = %{ctx | numbers: pattern_numbers(pattern)}
    tokens = tokenize_pattern(pattern_text(pattern))
    regex_string = compile_regex(tokens, ctx.months, ctx.eras, ctx.lenient, ctx)

    case Regex.compile(regex_string, "u") do
      {:ok, regex} -> regex
      {:error, _} -> nil
    end
  end

  # `{:ok, result}`, `:error` when the pattern matched but its fields
  # make no date, or `:no_match` when it did not match. A pattern that
  # reads the era by a narrow name it does not state matches only once
  # `ctx.narrow_eras` allows it (`read_by_narrow_era/4`).
  defp match_pattern(input, pattern, ctx, as) do
    with %Regex{} = regex <- Map.get(ctx.regexes, pattern),
         %{} = caps <- Regex.named_captures(regex, input),
         true <- ctx.narrow_eras or is_nil(named_capture_index(caps, "__f")) do
      tokens = pattern |> pattern_text() |> tokenize_pattern()

      caps
      |> latin_digits(pattern_numbers(pattern))
      |> match_captures(%{ctx | two_digit_year: two_digit_year?(tokens)}, as)
    else
      _ -> :no_match
    end
  end

  # Whether a pattern writes its year as `yy`, its two low-order digits.
  defp two_digit_year?(tokens), do: Enum.member?(tokens, {:y, 2})

  # Fields the pattern writes in a numbering with digits of its own
  # (`hanidec` 〇一二…) are read as Latin digits.
  defp latin_digits(caps, numbers) when map_size(numbers) == 0, do: caps

  defp latin_digits(caps, numbers) do
    numbers
    |> Map.values()
    |> Enum.uniq()
    |> Enum.flat_map(&numbering_digits/1)
    |> Enum.reduce(caps, fn digits, caps ->
      Map.new(caps, fn {key, value} -> {key, digit_translate(value, digits)} end)
    end)
  end

  defp match_captures(caps, ctx, as) do
    year_fallback = year_fallback_for(as, ctx.reference_year)

    with {:ok, era_index} <- extract_era(caps),
         {:ok, fields} <- extract_fields(caps, year_fallback, era_index, ctx) do
      match_result_for(as, fields, caps, ctx)
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

  defp match_result_for(:struct, fields, _caps, ctx) do
    build_date_smart(fields, ctx.calendar_module)
  end

  defp match_result_for({:map, :strict}, fields, caps, ctx) do
    case build_date_smart(fields, ctx.calendar_module) do
      {:ok, _date} -> {:ok, strict_map(fields, caps, ctx.calendar_module)}
      :error -> :error
    end
  end

  # A lax match builds no date, so its fields are checked against the
  # calendar instead: an impossible partial date does not match.
  defp match_result_for({:map, :lax}, fields, _caps, ctx) do
    if possible?(fields, ctx.reference_year),
      do: {:ok, fields_to_map(fields, ctx.calendar_module)},
      else: :error
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
    non_empty?(caps, "year") or non_empty?(caps, "week_based_year") or
      non_empty?(caps, "related_year") or not is_nil(named_capture_index(caps, "__u")) or
      not is_nil(named_capture_index(caps, "__y"))
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
  defp extract_fields(caps, year_fallback, era_index, ctx) do
    %{calendar_module: calendar_module, own_calendar: own_calendar, week_config: week_config} =
      ctx

    month = extract_month(caps, "")
    day = extract_day(caps, "")

    with {:ok, calendar_year} <-
           extract_calendar_year(caps, "", year_fallback, era_index, ctx, {month, day}) do
      reject_invalid(%{
        year: calendar_year,
        month: named_month(month, calendar_year, calendar_module),
        day: day,
        quarter: extract_optional_quarter(caps),
        week_of_year: extract_optional_int(caps, "week_of_year"),
        week_of_month: extract_optional_int(caps, "week_of_month"),
        week_based_year: extract_optional_int(caps, "week_based_year"),
        day_of_year: extract_optional_int(caps, "day_of_year"),
        day_of_week: extract_optional_day_of_week(caps, week_config),
        day_of_week_in_month: extract_optional_int(caps, "day_of_week_in_month"),
        weekday_name_index: extract_optional_weekday_name(caps),
        calendar_module: calendar_module,
        own_calendar: own_calendar,
        week_config: week_config
      })
    end
  end

  # A field whose captured value no date can have (month 15, day 32) is
  # `:invalid`, not absent: the pattern does not match, rather than read
  # the input as if the field were missing.
  defp reject_invalid(fields) do
    if Enum.any?(fields, fn {_field, value} -> value == :invalid end),
      do: :error,
      else: {:ok, fields}
  end

  defp pivot_year(two_digit, reference_year) do
    century_base = div(reference_year - 80, 100) * 100
    candidate = century_base + two_digit
    if candidate < reference_year - 80, do: candidate + 100, else: candidate
  end

  # A month name gives CLDR's number for the month. It is the month of the
  # date only in a calendar that numbers its months that way; the month is
  # the one of `year` whose `month_of_year/3` (the key the calendar's month
  # names are found by) is that number. So a Hebrew month after Adar I sits
  # one place earlier in an ordinary year, and a Chinese month one place
  # later after a leap month. A plain name of a month that `year` has only
  # as a leap variant (Adar, in a Hebrew leap year) names that variant. A
  # name the year has no month for is `:invalid`. Without a year, the month
  # is CLDR's number.
  defp named_month({:named, month}, year, calendar_module) when is_integer(year) do
    month_named(month, year, calendar_module) || :invalid
  end

  defp named_month({:named, month}, _year, _calendar_module), do: cldr_month_number(month)
  defp named_month(month, _year, _calendar_module), do: month

  defp cldr_month_number({month, :leap}), do: month
  defp cldr_month_number(month), do: month

  # The month of the year whose CLDR month, as its calendar answers, is
  # the one written.
  defp month_named({_month, :leap} = leap_month, year, calendar_module) do
    Enum.find(
      months_of(year, calendar_module),
      &(cldr_month_of(year, &1, calendar_module) == leap_month)
    )
  end

  defp month_named(month, year, calendar_module) do
    if cldr_month_of(year, month, calendar_module) == month do
      month
    else
      months = months_of(year, calendar_module)

      Enum.find(months, &(cldr_month_of(year, &1, calendar_module) == month)) ||
        Enum.find(months, &(cldr_month_of(year, &1, calendar_module) == {month, :leap}))
    end
  end

  defp months_of(year, calendar_module),
    do: 1..Localize.Calendar.answering(calendar_module).months_in_year(year)//1

  defp cldr_month_of(year, month, calendar_module) do
    Localize.Calendar.cldr_month(%{year: year, month: month, day: 1, calendar: calendar_module})
  end

  # Quarter capture comes in two flavors: numeric capture
  # under `quarter`, or one of the named branches
  # `__q1__` / `__q2__` / `__q3__` / `__q4__`. Return
  # 1..4, `nil` when there is none, or `:invalid`.
  defp extract_optional_quarter(caps) do
    case Map.get(caps, "quarter") do
      raw when is_binary(raw) and raw != "" ->
        case Integer.parse(raw) do
          {n, ""} when n in 1..4 -> n
          _ -> :invalid
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
          _ -> :invalid
        end

      _ ->
        nil
    end
  end

  # Day of week from the numeric or name capture, as an ISO day (1 is
  # Monday), `nil` when there is none, or `:invalid`. Numeric `e` and `c` count from the locale's first day
  # of the week, so they are converted; a name already carries its ISO day.
  defp extract_optional_day_of_week(caps, {first_day, _min_days}) do
    if raw = Map.get(caps, "day_of_week_numeric") do
      with local_day when is_integer(local_day) <- parse_numeric_day_of_week(raw) do
        Localize.DateTime.Week.iso_day_of_week(local_day, first_day)
      end
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
          _ -> :invalid
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
    {:ok, named_capture_index(caps, "__e") || named_capture_index(caps, "__f")}
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

  # The calendar's year for a year written as `year` of era
  # `era_index`. A year without an era is the calendar's own,
  # and without a year (only possible in `:map` mode, or an
  # interval endpoint) there's nothing to resolve.
  defp resolve_calendar_year(year, era_index, _calendar_module, _month_day)
       when not is_integer(year) or is_nil(era_index),
       do: {:ok, year}

  # The calendar says which of its years it writes as `year` of the era,
  # a Japanese calendar's years of an imperial era included.
  defp resolve_calendar_year(year, era_index, calendar_module, month_day),
    do: year_in_era(year, era_index, calendar_module, month_day)

  # The calendar's year that the formatter writes as `year` of era
  # `era_index`. A forward era counts years as they are and a before era
  # counts back, from year 0 in a calendar that has one (1 BC) and from
  # year -1 in one that does not; an era that begins before the calendar's
  # first year counts from the calendar year it begins in, so Amete Alem
  # 5495 is the Ethiopic year -5. Those are the candidates, each asked of
  # the calendar through the functions the formatter uses. The month and
  # day, where the input has them, settle an era that begins mid-year.
  defp year_in_era(year, era_index, calendar_module, {month, day}) do
    ([year, -year, 1 - year] ++ counted_from_era_start(year, era_index, calendar_module))
    |> Enum.uniq()
    |> Enum.find(&written_as?(era_probe(calendar_module, &1, month, day), year, era_index))
    |> case do
      nil -> {:error, :unknown_era}
      calendar_year -> {:ok, calendar_year}
    end
  end

  # The year of era `era_index` counted from the calendar year the era
  # begins in, where the calendar's eras have more than one beginning, and
  # then from the year CLDR gives for that beginning. A calendar may number
  # its years one way when an era begins and another before it ends:
  # Calendrical's Japanese reform calendar counts its lunisolar years from
  # 645 and its years from the reform of 1873 as the Gregorian calendar
  # does, so Meiji begins in its year 1224 and Meiji 6 is its year 1873.
  defp counted_from_era_start(year, era_index, calendar_module) do
    starts = era_starts(calendar_module)

    with true <- map_size(starts) > 1,
         {:ok, [start_year, start_month, start_day]} <- Map.fetch(starts, era_index),
         {:ok, start} <- Date.new(start_year, start_month, start_day),
         {:ok, %{year: first_year}} <- Date.convert(start, calendar_module) do
      [first_year + year - 1, start_year + year - 1]
    else
      _no_era_start -> []
    end
  end

  defp era_starts(calendar_module) do
    Localize.SupplementalData.calendars()
    |> get_in([era_calendar_type(calendar_module), :eras])
    |> List.wrap()
    |> Enum.flat_map(fn
      [era, %{start: start}] -> [{era, start}]
      _before_era -> []
    end)
    |> Map.new()
  end

  # A candidate year the calendar does not hold is not asked about: a
  # calendar may raise for a year outside the range it computes, as
  # Calendrical's Persian calendar does outside Gregorian 1001 to 3000.
  defp written_as?(date, year, era_index) do
    calendar_holds?(date) and
      Localize.Calendar.displayed_year(date) == {:ok, year} and
      match?({:ok, {_year_of_era, ^era_index}}, Localize.Calendar.year_of_era(date))
  end

  # Asked of the year's first day, which every year the calendar holds has,
  # before a month is placed in the year.
  defp calendar_holds?(%{calendar: calendar, year: year}) do
    Localize.Calendar.answering(calendar).valid_date?(year, 1, 1)
  end

  # The date a candidate year is asked about. The month the input gave is
  # CLDR's number for it, and the calendar is asked about the month of the
  # candidate year it names so (`named_month/3`): a Hebrew common year has
  # twelve months and its Elul is written 13, a month the calendar would say
  # the year has not. Where the year has no such month, or the input gave
  # none, the year alone is asked about.
  defp era_probe(calendar_module, year, month, day) do
    probe = %{calendar: calendar_module, year: year}

    with true <- calendar_holds?(probe),
         placed when is_integer(placed) <- named_month(era_month(month), year, calendar_module) do
      probe |> Map.put(:month, placed) |> maybe_put(:day, era_day(day))
    else
      _no_month_to_ask_about -> probe
    end
  end

  defp era_month({:named, _month} = month), do: month
  defp era_month(_month), do: nil

  defp era_day(day) when is_integer(day), do: day
  defp era_day(_day), do: nil

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
        build_from_week_date(fields, calendar_module)

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
        date_from_week(fields.year, fields.week_of_year, nil, fields, calendar_module)

      has_week_based_year_week?(fields) ->
        date_from_week(fields.week_based_year, fields.week_of_year, nil, fields, calendar_module)

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

  defp build_from_day_of_year(fields, calendar_module),
    do: day_of_year(fields.year, fields.day_of_year, calendar_module)

  defp build_from_week_date(fields, calendar_module) do
    date_from_week(
      fields.week_based_year,
      fields.week_of_year,
      fields.day_of_week,
      fields,
      calendar_module
    )
  end

  defp build_from_year_as_week_year(fields, calendar_module) do
    date_from_week(
      fields.year,
      fields.week_of_year,
      fields.day_of_week,
      fields,
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

  # The first day of a quarter in the calendar's own quarters, as the
  # formatter writes `Q`: the days its `quarter/2` gives, taken into the
  # calendar the input is read in.
  defp build_from_quarter(fields, calendar_module) do
    with {:ok, days} <-
           Localize.Calendar.ask(
             fields.own_calendar,
             :quarter,
             [fields.year, fields.quarter],
             "the days of a quarter",
             &match?(%Date.Range{}, &1)
           ),
         {:ok, date} <- convert_value(days.first, calendar_module) do
      {:ok, date}
    else
      _no_such_quarter -> :error
    end
  end

  # Verify the `E`/`c` weekday name (if any was captured)
  # matches the date's actual weekday. Mismatch → :error so
  # the parser backtracks to try a different pattern.
  defp validate_weekday(date, %{day_of_week: nil, weekday_name_index: nil}), do: {:ok, date}

  defp validate_weekday(date, %{day_of_week: nil, weekday_name_index: idx})
       when is_integer(idx) do
    if Date.day_of_week(date, :monday) == idx, do: {:ok, date}, else: :error
  end

  defp validate_weekday(date, %{day_of_week: dow}) when is_integer(dow) do
    if Date.day_of_week(date, :monday) == dow, do: {:ok, date}, else: :error
  end

  # Build a date from a week-based year, a week and a day of the week in
  # the weeks the formatter writes `Y` and `w` in: the calendar's own, the
  # days its `week/2` gives, or the locale's for `Calendar.ISO`, which has
  # none of its own (`Localize.Calendar.week/4`). Of those days it is the one
  # on the ISO day of the week, or the first. They are the weeks of the
  # calendar asked for even where it reads its dates as Gregorian ones
  # (`fields.own_calendar`), and the date is taken into the calendar the
  # input is read in.
  defp date_from_week(week_year, week, day_of_week, fields, calendar_module) do
    with {:ok, days} <-
           Localize.Calendar.week(fields.own_calendar, week_year, week, fields.week_config),
         %Date{} = date <- day_in_week(days, day_of_week),
         {:ok, date} <- convert_value(date, calendar_module) do
      {:ok, date}
    else
      _no_such_day -> :error
    end
  end

  defp day_in_week(days, nil), do: days.first

  defp day_in_week(days, day_of_week),
    do: Enum.find(days, &(Date.day_of_week(&1, :monday) == day_of_week))

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

  # ── Partial dates ────────────────────────────────────────────

  # A year the input left out ranges over this many years either side of
  # the reference year: enough to hold every leap-day, weekday and
  # week-count combination of the Gregorian calendar, which repeat every
  # 28 years, and the leap years of the lunisolar calendars.
  @partial_year_span 28

  # A partial date is possible when some date of the calendar has every
  # field it carries. A year the input left out ranges over the years
  # around the reference year, so "February 29" is possible and
  # "June 31" is not.
  defp possible?(fields, reference_year) do
    fields
    |> candidate_years(reference_year)
    |> Enum.any?(&possible_in_year?(fields, &1))
  end

  defp candidate_years(%{year: year}, _reference_year) when is_integer(year), do: [year]

  defp candidate_years(_fields, reference_year) do
    Enum.flat_map(0..@partial_year_span, fn
      0 -> [reference_year]
      span -> [reference_year + span, reference_year - span]
    end)
  end

  defp possible_in_year?(fields, year) do
    months_in_year = fields.calendar_module.months_in_year(year)
    months = if fields.month, do: [fields.month], else: Enum.to_list(1..months_in_year)

    (is_nil(fields.month) or fields.month in 1..months_in_year) and
      possible_day?(fields, year, months) and
      possible_day_of_year?(fields, year) and
      possible_week?(fields, year) and
      possible_week_of_month?(fields, year, months) and
      possible_weekday_in_month?(fields, year, months)
  end

  # The day falls in one of the months and, when a weekday was captured
  # too, on that weekday.
  defp possible_day?(%{day: nil}, _year, _months), do: true

  defp possible_day?(fields, year, months) do
    Enum.any?(months, fn month ->
      case build_date(year, month, fields.day, fields.calendar_module) do
        {:ok, date} -> match?({:ok, _date}, validate_weekday(date, fields))
        :error -> false
      end
    end)
  end

  defp possible_day_of_year?(%{day_of_year: nil}, _year), do: true

  defp possible_day_of_year?(fields, year),
    do: match?({:ok, _date}, day_of_year(year, fields.day_of_year, fields.calendar_module))

  defp possible_week?(%{week_of_year: nil}, _year), do: true

  defp possible_week?(fields, year) do
    week_year = fields.week_based_year || year
    week = fields.week_of_year

    match?(
      {:ok, _date},
      date_from_week(week_year, week, fields.day_of_week, fields, fields.calendar_module)
    )
  end

  defp possible_week_of_month?(%{week_of_month: nil}, _year, _months), do: true

  defp possible_week_of_month?(fields, year, months) do
    Enum.any?(months, &(fields.week_of_month in weeks_of_month(year, &1, fields)))
  end

  # The weeks of a month, numbered as the formatter numbers `W`: the
  # calendar's own weeks of the month (its `week_of_month/3`), or the
  # locale's for `Calendar.ISO`, that its days fall in and that belong to it.
  defp weeks_of_month(year, month, %{calendar_module: calendar_module} = fields) do
    days_in_month =
      Localize.Calendar.ask(
        calendar_module,
        :days_in_month,
        [year, month],
        "a number of days",
        &(is_integer(&1) and &1 > 0)
      )

    case days_in_month do
      {:ok, days} ->
        for day <- 1..days,
            date = %{year: year, month: month, day: day, calendar: calendar_module},
            {:ok, {^month, week}} <-
              [Localize.Calendar.week_of_month(date, fields.week_config)],
            uniq: true,
            do: week

      {:error, _no_days} ->
        []
    end
  end

  defp possible_weekday_in_month?(%{day_of_week_in_month: nil}, _year, _months), do: true

  defp possible_weekday_in_month?(fields, year, months) do
    weekdays = if fields.day_of_week, do: [fields.day_of_week], else: Enum.to_list(1..7)
    n = fields.day_of_week_in_month

    Enum.any?(for(month <- months, weekday <- weekdays, do: {month, weekday}), fn {month, weekday} ->
      match?({:ok, _date}, date_from_nth_weekday(year, month, weekday, n, fields.calendar_module))
    end)
  end

  # A day of a year by its number, as the formatter writes `D`: that day of
  # the year's days, which the calendar gives (its `year/1`), counted from
  # the first. A number the year has no day for is no date.
  defp day_of_year(year, day_of_year, calendar_module) when is_integer(day_of_year) do
    with {:ok, days} <-
           Localize.Calendar.ask(
             calendar_module,
             :year,
             [year],
             "the days of a year",
             &match?(%Date.Range{}, &1)
           ),
         true <- day_of_year in 1..Enum.count(days)//1 do
      {:ok, Date.add(days.first, day_of_year - 1)}
    else
      _no_such_day -> :error
    end
  end

  defp day_of_year(_year, _day_of_year, _calendar_module), do: :error

  # The fields of a date given only as year, month and day, in the shape
  # `extract_fields/5` gives them. It has no week fields, so nothing reads
  # the week data.
  defp date_fields(year, month, day, calendar_module) do
    %{
      year: year,
      month: month,
      day: day,
      quarter: nil,
      week_of_year: nil,
      week_of_month: nil,
      week_based_year: nil,
      day_of_year: nil,
      day_of_week: nil,
      day_of_week_in_month: nil,
      weekday_name_index: nil,
      calendar_module: calendar_module,
      own_calendar: calendar_module,
      week_config: nil
    }
  end

  # ── Errors ───────────────────────────────────────────────────

  defp no_match_error(input, locale, calendar_module) do
    DateParseError.exception(input: input, locale: locale, calendar: calendar_module)
  end
end
