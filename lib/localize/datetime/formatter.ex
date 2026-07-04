defmodule Localize.DateTime.Formatter do
  @moduledoc false

  # Implements format symbol handlers for CLDR date/time format patterns.
  #
  # Each public function corresponds to a token produced by the
  # date_time_format_lexer. The `format/4` entry point tokenizes
  # a format pattern string and calls each handler in sequence.
  #
  # Symbol handlers accept `(date_or_time, count, locale_id, options)`
  # where `count` is the number of repeated format characters (e.g.,
  # `MMM` has count 3) and `options` is a map.
  #
  # Calendar.ISO is supported natively — values like calendar_year,
  # week_of_year, and day_of_year are derived directly.

  import Kernel, except: [to_string: 1]

  alias Localize.DateTime.Format.Compiler

  # Handler names that emit a timezone field. Used to elide
  # empty-zone artefacts (and their bounding whitespace) when a
  # zoneless input — a `Time` or a `NaiveDateTime` — is formatted
  # against a pattern that ends in `" z"` / `" zzzz"` / etc.
  @zone_handlers ~w(
    zone_short zone_basic zone_gmt
    generic_non_location specific_non_location
    zone_iso zone_iso_z
  )a

  defguardp is_date(date)
            when is_map_key(date, :year) and is_map_key(date, :month) and is_map_key(date, :day)

  defguardp is_time(time)
            when is_map_key(time, :hour) and is_map_key(time, :minute)

  defguardp has_month(date) when is_map_key(date, :month)

  # ── Entry point ────────────────────────────────────────────

  # # format/4
  #
  # Formats a date/time/datetime using a format pattern string.
  #
  # ### Arguments
  #
  # * `datetime` is a Date, Time, DateTime, NaiveDateTime, or map.
  #
  # * `format_string` is a CLDR format pattern string.
  #
  # * `locale_id` is a locale identifier atom.
  #
  # * `options` is a map of formatting options.
  #
  # ### Returns
  #
  # * `{:ok, formatted_string}` or `{:error, exception}`.
  #
  @spec format(map(), String.t(), atom(), map()) ::
          {:ok, String.t()} | {:error, Exception.t()}
  def format(datetime, format_string, locale_id, options \\ %{}) do
    with {:ok, tokens, _} <- tokenize_cached(format_string) do
      results =
        Enum.map(tokens, fn
          {:literal, _line, string} ->
            string

          {handler, _line, count} ->
            apply(__MODULE__, handler, [datetime, count, locale_id, options])
        end)

      case Enum.find(results, &match?({:error, _}, &1)) do
        {:error, _} = error ->
          error

        nil ->
          stripped = strip_empty_zone_padding(tokens, results, [])
          {:ok, stripped |> Enum.map(&ensure_string/1) |> IO.iodata_to_binary()}
      end
    end
  end

  # Drops empty zone-handler results from the parallel `tokens` and
  # `results` lists, also stripping any trailing whitespace from the
  # preceding literal and any leading whitespace from the following
  # one. A zone handler returns `""` when the input lacks zone info
  # (e.g., a `Time` or `NaiveDateTime` formatted against a `:long` /
  # `:full` pattern that ends in `" z"` / `" zzzz"`). Without this
  # pass the literal space remains and the output ends with a stray
  # trailing space (e.g. `"21:00:00 "`, `"21時00分00秒 "`).
  defp strip_empty_zone_padding([], [], acc), do: Enum.reverse(acc)

  defp strip_empty_zone_padding(
         [{handler, _line, _count} | rest_t],
         ["" | rest_r],
         acc
       )
       when handler in @zone_handlers do
    acc = trim_trailing_whitespace_in_acc(acc)
    {rest_t, rest_r} = trim_leading_whitespace_in_next(rest_t, rest_r)
    strip_empty_zone_padding(rest_t, rest_r, acc)
  end

  defp strip_empty_zone_padding([_token | rest_t], [value | rest_r], acc) do
    strip_empty_zone_padding(rest_t, rest_r, [value | acc])
  end

  defp trim_trailing_whitespace_in_acc([last | rest]) when is_binary(last) do
    case String.trim_trailing(last) do
      ^last -> [last | rest]
      "" -> rest
      trimmed -> [trimmed | rest]
    end
  end

  defp trim_trailing_whitespace_in_acc(acc), do: acc

  defp trim_leading_whitespace_in_next(
         [{:literal, line, _} | rest_t],
         [next | rest_r]
       )
       when is_binary(next) do
    case String.trim_leading(next) do
      ^next -> {[{:literal, line, next} | rest_t], [next | rest_r]}
      "" -> {rest_t, rest_r}
      trimmed -> {[{:literal, line, trimmed} | rest_t], [trimmed | rest_r]}
    end
  end

  defp trim_leading_whitespace_in_next(rest_t, rest_r), do: {rest_t, rest_r}

  defp tokenize_cached(format_string) do
    key = {:localize, :datetime_format_tokens, format_string}

    case Localize.FormatCache.lookup(key) do
      {:ok, {tokens, end_line}} ->
        {:ok, tokens, end_line}

      :miss ->
        case Compiler.tokenize(format_string) do
          {:ok, tokens, end_line} ->
            Localize.FormatCache.store(key, {tokens, end_line})
            {:ok, tokens, end_line}

          error ->
            error
        end
    end
  end

  defp ensure_string(value) when is_binary(value), do: value
  defp ensure_string(value) when is_integer(value), do: Integer.to_string(value)
  defp ensure_string(value) when is_float(value), do: Float.to_string(value)
  defp ensure_string(nil), do: ""
  defp ensure_string(value), do: Kernel.to_string(value)

  # ── Literal ────────────────────────────────────────────────

  @doc false
  def literal(_datetime, _count, string, _options) when is_binary(string), do: string
  def literal(_datetime, _count, _locale_id, _options), do: ""

  # ── Era (G) ────────────────────────────────────────────────

  @doc false
  def era(date, count, locale_id, options) when is_date(date) do
    format = format_for_count(count)
    Localize.Calendar.localize(date, :era, locale: locale_id, format: format, era: options[:era])
  end

  def era(_date, _count, _locale_id, _options), do: ""

  # ── Year (y) ───────────────────────────────────────────────
  #
  # CLDR `y` is the era-relative year. For Calendar.ISO this
  # is the same as the proleptic year for AD dates (and the
  # absolute value for BC). For era-aware calendars like
  # `Calendrical.Japanese`, the era-year (Heisei 12, Reiwa 6,
  # …) differs from the proleptic year and we must consult
  # the calendar's `year_of_era/3` callback to derive it.

  @doc false
  def year(%{year: _} = date, 1, locale_id, options) do
    era_year(date) |> calendar_year() |> apply_ns(locale_id, options, "y")
  end

  def year(%{year: _} = date, 2, locale_id, options) do
    era_year(date)
    |> calendar_year()
    |> rem(100)
    |> abs()
    |> pad(2)
    |> apply_ns(locale_id, options, "y")
  end

  def year(%{year: _} = date, count, locale_id, options) do
    era_year(date) |> calendar_year() |> pad(count) |> apply_ns(locale_id, options, "y")
  end

  def year(_date, _count, _locale_id, _options), do: ""

  # Apply a CLDR `number_system` override for one field. The
  # overrides map (from `Localize.DateTime.Format.number_system_overrides/4`)
  # is keyed by field symbol — `"y"`, `"M"`, `"d"`, … — plus
  # `"all"` meaning every numeric field. Resolution order:
  # field-specific override → `"all"` override → no override.
  #
  # The value is a number-system atom. Numeric systems
  # (`:arab`, `:beng`, `:deva`, etc.) have a fixed 10-digit set
  # so we transliterate per ASCII digit. Algorithmic systems
  # (`:hebr`, `:jpanyear`, `:roman`, etc.) need the RBNF rule
  # set for the locale — we delegate to
  # `Localize.Number.to_string/2` which loads RBNF on demand.
  # If neither path produces output (no RBNF rule for the
  # locale, malformed digit set) we fall back to ASCII.
  defp apply_ns(value, locale_id, options, field) do
    string = ensure_string(value)

    case fetch_override(options, field) do
      nil ->
        string

      system ->
        transliterate_to_number_system(string, system, locale_id) || string
    end
  end

  defp fetch_override(options, field) do
    overrides = options[:number_system_overrides] || options["number_system_overrides"] || %{}
    Map.get(overrides, field) || Map.get(overrides, "all")
  end

  # Resolve a CLDR number-system atom (`:hebr`, `:jpanyear`,
  # `:arab`, …) to a renderer. Numeric systems get a digit
  # table; algorithmic systems get a CLDR RBNF rule name that
  # `Localize.Number.to_string/2` knows how to invoke via its
  # `:format` option.
  defp transliterate_to_number_system(string, system, locale_id) do
    case Map.get(Localize.Number.System.number_systems(), system) do
      %{type: :numeric, digits: digits} ->
        transliterate_via_digits(string, digits)

      %{type: :algorithmic, rules: rule_path} when is_binary(rule_path) ->
        case Integer.parse(string) do
          {n, ""} -> apply_rbnf_rule(n, rule_path, locale_id)
          _ -> nil
        end

      _ ->
        nil
    end
  end

  # Algorithmic rules are referenced either as a bare rule
  # name (`"hebrew"` — resolved against the locale's RBNF set,
  # falling back to root) or as a fully-qualified path
  # (`"ja/SpelloutRules/spellout-numbering-year-latn"`). The
  # path form names a specific locale and rule set; we pass
  # the trailing rule name as the `:format` option and use
  # the locale embedded in the path.
  defp apply_rbnf_rule(n, rule_path, locale_id) do
    {target_locale, rule_name} =
      case String.split(rule_path, "/", parts: 3) do
        [locale, _group, rule] -> {String.to_atom(locale), rule}
        [rule] -> {locale_id, rule}
        _ -> {locale_id, rule_path}
      end

    rule_atom = String.to_atom(rule_name)

    case Localize.Number.to_string(n, locale: target_locale, format: rule_atom) do
      {:ok, formatted} -> formatted
      _ -> nil
    end
  end

  defp transliterate_via_digits(string, digits) when byte_size(digits) > 0 do
    digit_list = String.graphemes(digits)

    if length(digit_list) == 10 do
      string
      |> String.graphemes()
      |> Enum.map(fn
        c when c in ~w(0 1 2 3 4 5 6 7 8 9) ->
          Enum.at(digit_list, String.to_integer(c))

        c ->
          c
      end)
      |> Enum.join()
    else
      nil
    end
  end

  defp transliterate_via_digits(_, _), do: nil

  # For era-aware calendars implementing the Calendrical
  # behaviour, `calendar_year/3` returns the displayed
  # calendar year (Heisei 12, BE 2543, AH 1420) — which is
  # what CLDR's `y` token wants. We prefer it over
  # `year_of_era/3` because the latter returns a Julian-day-
  # derived counter that varies by calendar convention.
  #
  # `Calendar.ISO` takes the `year_of_era/3` branch (it exports
  # no `calendar_year/3`), so BCE dates render era-relative per
  # TR35: year -1 is "2" (with era "BC"), year 0 is "1" — never
  # a signed proleptic year like "-1 BC".
  defp era_year(%{year: year, month: month, day: day, calendar: calendar})
       when is_atom(calendar) do
    cond do
      function_exported?(calendar, :calendar_year, 3) ->
        calendar.calendar_year(year, month, day)

      function_exported?(calendar, :year_of_era, 3) ->
        case calendar.year_of_era(year, month, day) do
          {era_year, _era} -> era_year
          _ -> year
        end

      true ->
        year
    end
  end

  defp era_year(%{year: year}), do: year

  # ── Week-aligned year (Y) ──────────────────────────────────

  @doc false
  def week_aligned_year(date, 1, locale_id, _options) when is_date(date) do
    {year, _week} = locale_week_of_year(date, locale_id)
    Kernel.to_string(year)
  end

  def week_aligned_year(date, 2, locale_id, _options) when is_date(date) do
    {year, _week} = locale_week_of_year(date, locale_id)
    year |> rem(100) |> pad(2)
  end

  def week_aligned_year(date, count, locale_id, _options) when is_date(date) and count in 3..5 do
    {year, _week} = locale_week_of_year(date, locale_id)
    pad(year, count)
  end

  def week_aligned_year(_date, _count, _locale_id, _options), do: ""

  # ── Extended year (u) ──────────────────────────────────────

  @doc false
  def extended_year(%{year: year}, count, _locale_id, _options) do
    pad(year, count)
  end

  def extended_year(_date, _count, _locale_id, _options), do: ""

  # ── Cyclic year (U) ────────────────────────────────────────

  @doc false
  def cyclic_year(%{year: year}, _count, _locale_id, _options), do: year
  def cyclic_year(_date, _count, _locale_id, _options), do: ""

  # ── Related year (r) ───────────────────────────────────────

  @doc false
  def related_year(%{year: year}, _count, _locale_id, _options), do: year
  def related_year(_date, _count, _locale_id, _options), do: ""

  # ── Quarter (Q) ────────────────────────────────────────────

  @doc false
  def quarter(date, 1, _locale_id, _options) when has_month(date) do
    quarter_of_year(date)
  end

  def quarter(date, 2, _locale_id, _options) when has_month(date) do
    quarter_of_year(date) |> pad(2)
  end

  def quarter(date, 3, locale_id, _options) when has_month(date) do
    Localize.Calendar.localize(date, :quarter, locale: locale_id, format: :abbreviated)
  end

  def quarter(date, 4, locale_id, _options) when has_month(date) do
    Localize.Calendar.localize(date, :quarter, locale: locale_id, format: :wide)
  end

  def quarter(date, 5, locale_id, _options) when has_month(date) do
    Localize.Calendar.localize(date, :quarter, locale: locale_id, format: :narrow)
  end

  def quarter(_date, _count, _locale_id, _options), do: ""

  # ── Standalone Quarter (q) ─────────────────────────────────

  @doc false
  def standalone_quarter(date, 1, _locale_id, _options) when has_month(date) do
    quarter_of_year(date)
  end

  def standalone_quarter(date, 2, _locale_id, _options) when has_month(date) do
    quarter_of_year(date) |> pad(2)
  end

  def standalone_quarter(date, count, locale_id, _options)
      when has_month(date) and count in 3..5 do
    format = format_for_count(count)

    Localize.Calendar.localize(date, :quarter,
      locale: locale_id,
      context: :stand_alone,
      format: format
    )
  end

  def standalone_quarter(_date, _count, _locale_id, _options), do: ""

  # ── Month (M) ──────────────────────────────────────────────

  @doc false
  def month(%{month: month}, 1, locale_id, options),
    do: month |> apply_ns(locale_id, options, "M")

  def month(%{month: month}, 2, locale_id, options),
    do: pad(month, 2) |> apply_ns(locale_id, options, "M")

  def month(date, count, locale_id, _options) when has_month(date) and count in 3..5 do
    format = format_for_count(count)
    Localize.Calendar.localize(date, :month, locale: locale_id, format: format)
  end

  def month(_date, _count, _locale_id, _options), do: ""

  # ── Standalone Month (L) ───────────────────────────────────

  @doc false
  def standalone_month(%{month: month}, 1, _locale_id, _options), do: month

  def standalone_month(%{month: month}, 2, _locale_id, _options), do: pad(month, 2)

  def standalone_month(date, count, locale_id, _options) when has_month(date) and count in 3..5 do
    format = format_for_count(count)

    Localize.Calendar.localize(date, :month,
      locale: locale_id,
      context: :stand_alone,
      format: format
    )
  end

  def standalone_month(_date, _count, _locale_id, _options), do: ""

  # ── Week of Year (w) ───────────────────────────────────────

  @doc false
  def week_of_year(date, 1, locale_id, _options) when is_date(date) do
    {_year, week} = locale_week_of_year(date, locale_id)
    week
  end

  def week_of_year(date, 2, locale_id, _options) when is_date(date) do
    {_year, week} = locale_week_of_year(date, locale_id)
    pad(week, 2)
  end

  def week_of_year(_date, _count, _locale_id, _options), do: ""

  # ── Week of Month (W) ──────────────────────────────────────

  @doc false
  def week_of_month(
        %{year: year, month: month, day: day, calendar: Calendar.ISO},
        _count,
        locale_id,
        _options
      ) do
    {first_day, min_days} = week_config(locale_id)
    first_of_month_dow = :calendar.day_of_the_week({year, month, 1})
    offset = rem(first_of_month_dow - first_day + 7, 7)
    raw_week = div(day - 1 + offset, 7) + 1

    # Week 1 exists only when the first (possibly partial) week of the
    # month holds at least min_days days; otherwise that partial week
    # counts as week 0 per ICU.
    if 7 - offset >= min_days, do: raw_week, else: raw_week - 1
  end

  def week_of_month(%{day: day}, _count, _locale_id, _options) when is_integer(day) do
    div(day - 1, 7) + 1
  end

  def week_of_month(_date, _count, _locale_id, _options), do: ""

  # ── Day of Month (d) ───────────────────────────────────────

  @doc false
  def day_of_month(%{day: day}, 1, locale_id, options),
    do: day |> apply_ns(locale_id, options, "d")

  def day_of_month(%{day: day}, 2, locale_id, options),
    do: pad(day, 2) |> apply_ns(locale_id, options, "d")

  def day_of_month(_date, _count, _locale_id, _options), do: ""

  # ── Day of Year (D) ────────────────────────────────────────

  @doc false
  def day_of_year(date, count, _locale_id, _options) when is_date(date) do
    doy = compute_day_of_year(date)
    if count == 1, do: doy, else: pad(doy, count)
  end

  def day_of_year(_date, _count, _locale_id, _options), do: ""

  # ── Day of Week in Month (F) ───────────────────────────────

  @doc false
  def day_of_week_in_month(%{day: day}, _count, _locale_id, _options) do
    div(day - 1, 7) + 1
  end

  def day_of_week_in_month(_date, _count, _locale_id, _options), do: ""

  # ── Day Name (E) ───────────────────────────────────────────

  @doc false
  def day_name(date, count, locale_id, _options) when is_date(date) do
    format =
      case count do
        n when n in 1..3 -> :abbreviated
        4 -> :wide
        5 -> :narrow
        6 -> :short
        _ -> :abbreviated
      end

    Localize.Calendar.localize(date, :day_of_week, locale: locale_id, format: format)
  end

  def day_name(_date, _count, _locale_id, _options), do: ""

  # ── Day of Week number (e) ─────────────────────────────────

  @doc false
  def day_of_week(date, 1, _locale_id, _options) when is_date(date) do
    iso_day(date)
  end

  def day_of_week(date, 2, _locale_id, _options) when is_date(date) do
    pad(iso_day(date), 2)
  end

  def day_of_week(date, count, locale_id, options) when is_date(date) and count >= 3 do
    day_name(date, count, locale_id, options)
  end

  def day_of_week(_date, _count, _locale_id, _options), do: ""

  # ── Standalone Day of Week (c) ─────────────────────────────

  @doc false
  def standalone_day_of_week(date, 1, _locale_id, _options) when is_date(date) do
    iso_day(date)
  end

  def standalone_day_of_week(date, 2, _locale_id, _options) when is_date(date) do
    pad(iso_day(date), 2)
  end

  def standalone_day_of_week(date, count, locale_id, _options)
      when is_date(date) and count >= 3 do
    format = format_for_count(count)

    Localize.Calendar.localize(date, :day_of_week,
      locale: locale_id,
      context: :stand_alone,
      format: format
    )
  end

  def standalone_day_of_week(_date, _count, _locale_id, _options), do: ""

  # ── Period AM/PM (a) ───────────────────────────────────────

  @doc false
  # AM/PM depends only on `:hour`, so accept any map that has an hour
  # (partial times like `%{hour: 14}` still produce a correct marker).
  def period_am_pm(%{hour: _} = time, count, locale_id, options) do
    format = format_for_count(count)

    Localize.Calendar.localize(time, :am_pm,
      locale: locale_id,
      format: format,
      am_pm: options[:am_pm]
    )
  end

  def period_am_pm(_time, _count, _locale_id, _options), do: ""

  # ── Period noon/midnight (b) ───────────────────────────────

  @doc false
  # TR35 `b`: am, pm, noon, midnight. The exact-point (`at`) rules
  # from the locale's day-period rule set select noon/midnight; any
  # other time renders as AM/PM.
  def period_noon_midnight(time, count, locale_id, options) when is_time(time) do
    minutes = minutes_of_day(time)

    with rules when is_map(rules) <- day_period_rules(locale_id),
         period when period != nil <- at_period(rules, minutes),
         name when is_binary(name) <- day_period_name(period, count, locale_id) do
      name
    else
      _ -> period_am_pm(time, count, locale_id, options)
    end
  end

  def period_noon_midnight(_time, _count, _locale_id, _options), do: ""

  # ── Flexible period (B) ────────────────────────────────────

  @doc false
  # TR35 `B`: flexible day periods ("in the morning", "noon"). Exact
  # (`at`) rules take precedence, then the from/before range the time
  # falls in. Locales without day-period rules, and periods without a
  # localized name, fall back to AM/PM.
  def period_flex(time, count, locale_id, options) when is_time(time) do
    minutes = minutes_of_day(time)

    with rules when is_map(rules) <- day_period_rules(locale_id),
         period when period != nil <- at_period(rules, minutes) || flex_period(rules, minutes),
         name when is_binary(name) <- day_period_name(period, count, locale_id) do
      name
    else
      _ -> period_am_pm(time, count, locale_id, options)
    end
  end

  def period_flex(_time, _count, _locale_id, _options), do: ""

  defp minutes_of_day(%{hour: hour} = time) do
    hour * 60 + Map.get(time, :minute, 0)
  end

  # The locale's day-period rules are keyed by language code.
  defp day_period_rules(locale_id) do
    language =
      locale_id
      |> Kernel.to_string()
      |> String.split("-")
      |> hd()

    Map.get(Localize.SupplementalData.day_periods().format, language)
  end

  defp at_period(rules, minutes) do
    Enum.find_value(rules, fn
      {period, %{at: at}} when at == minutes -> period
      _ -> nil
    end)
  end

  defp flex_period(rules, minutes) do
    Enum.find_value(rules, fn
      {period, %{from: from, before: before}} when from <= before ->
        if minutes >= from and minutes < before, do: period

      # Ranges that wrap midnight (e.g. night from 23:00 before 04:00).
      {period, %{from: from, before: before}} ->
        if minutes >= from or minutes < before, do: period

      _ ->
        nil
    end)
  end

  # The localized name for a day period at the requested width,
  # falling back through abbreviated and wide before giving up (the
  # caller then renders AM/PM instead).
  defp day_period_name(period, count, locale_id) do
    width = format_for_count(count)

    with {:ok, day_periods} <- Localize.Calendar.day_periods(locale_id) do
      names = Map.get(day_periods, :format, %{})

      Enum.find_value([width, :abbreviated, :wide], fn w ->
        names |> Map.get(w, %{}) |> Map.get(period)
      end)
    else
      _ -> nil
    end
  end

  # ── Hour 1-12 (h) ─────────────────────────────────────────

  @doc false
  def h12(%{hour: hour}, 1, _locale_id, _options) do
    h = rem(hour, 12)
    if h == 0, do: 12, else: h
  end

  def h12(%{hour: hour}, count, _locale_id, _options) do
    h = rem(hour, 12)
    h = if h == 0, do: 12, else: h
    pad(h, count)
  end

  def h12(_time, _count, _locale_id, _options), do: ""

  # ── Hour 0-11 (K) ─────────────────────────────────────────

  @doc false
  def h11(%{hour: hour}, 1, _locale_id, _options), do: rem(hour, 12)

  def h11(%{hour: hour}, count, _locale_id, _options) do
    rem(hour, 12) |> pad(count)
  end

  def h11(_time, _count, _locale_id, _options), do: ""

  # ── Hour 0-23 (H) ─────────────────────────────────────────

  @doc false
  def h23(%{hour: hour}, 1, _locale_id, _options), do: hour

  def h23(%{hour: hour}, count, _locale_id, _options), do: pad(hour, count)

  def h23(_time, _count, _locale_id, _options), do: ""

  # ── Hour 1-24 (k) ─────────────────────────────────────────

  @doc false
  def h24(%{hour: hour}, 1, _locale_id, _options) do
    if hour == 0, do: 24, else: hour
  end

  def h24(%{hour: hour}, count, _locale_id, _options) do
    h = if hour == 0, do: 24, else: hour
    pad(h, count)
  end

  def h24(_time, _count, _locale_id, _options), do: ""

  # ── Minute (m) ─────────────────────────────────────────────

  @doc false
  def minute(%{minute: minute}, 1, _locale_id, _options), do: minute

  def minute(%{minute: minute}, count, _locale_id, _options), do: pad(minute, count)

  def minute(_time, _count, _locale_id, _options), do: ""

  # ── Second (s) ─────────────────────────────────────────────

  @doc false
  def second(%{second: second}, 1, _locale_id, _options), do: second

  def second(%{second: second}, count, _locale_id, _options), do: pad(second, count)

  def second(_time, _count, _locale_id, _options), do: ""

  # ── Fractional Second (S) ──────────────────────────────────

  @doc false
  def fractional_second(%{microsecond: {microsecond, precision}}, count, _locale_id, _options) do
    # Display `count` digits of the fractional second
    digits = min(count, max(precision, 1))
    fraction = div(microsecond, trunc(:math.pow(10, 6 - digits)))
    pad(fraction, digits)
  end

  def fractional_second(_time, _count, _locale_id, _options), do: ""

  # ── Decimal separator between seconds and fractional ───────

  @doc false
  def decimal_separator(_datetime, _count, _locale_id, _options), do: "."

  # ── Millisecond (A) ────────────────────────────────────────

  @doc false
  def millisecond(%{hour: h, minute: m, second: s} = time, count, _locale_id, _options) do
    ms = (h * 3600 + m * 60 + s) * 1000

    ms =
      case Map.get(time, :microsecond) do
        {us, _} -> ms + div(us, 1000)
        _ -> ms
      end

    pad(ms, count)
  end

  def millisecond(_time, _count, _locale_id, _options), do: ""

  # ── Date placeholder {1} ───────────────────────────────────

  @doc false
  def date(datetime, _count, locale_id, options) when is_date(datetime) do
    date_format = options[:date_format] || :medium

    with {:ok, pattern} <-
           Localize.DateTime.Format.resolve_format(
             :date,
             date_format,
             locale_id,
             cldr_calendar_for_datetime(datetime),
             variant_options(options)
           ),
         {:ok, formatted} <- format(datetime, pattern, locale_id, options) do
      formatted
    else
      {:error, _} = error -> error
    end
  end

  def date(_datetime, _count, _locale_id, _options), do: ""

  # ── Time placeholder {0} ───────────────────────────────────

  @doc false
  def time(datetime, _count, locale_id, options) when is_time(datetime) do
    time_format = options[:time_format] || :medium

    with {:ok, pattern} <-
           Localize.DateTime.Format.resolve_format(
             :time,
             time_format,
             locale_id,
             cldr_calendar_for_datetime(datetime),
             variant_options(options)
           ),
         {:ok, formatted} <- format(datetime, pattern, locale_id, options) do
      formatted
    else
      {:error, _} = error -> error
    end
  end

  def time(_datetime, _count, _locale_id, _options), do: ""

  # Resolve the CLDR calendar key from a datetime's `:calendar`
  # module — same probe as `Localize.Date.cldr_calendar_for/1`.
  defp cldr_calendar_for_datetime(%{calendar: Calendar.ISO}), do: :gregorian

  defp cldr_calendar_for_datetime(%{calendar: module}) when is_atom(module) do
    Code.ensure_loaded?(module)

    if function_exported?(module, :cldr_calendar_type, 0) do
      module.cldr_calendar_type()
    else
      :gregorian
    end
  end

  defp cldr_calendar_for_datetime(_), do: :gregorian

  # Pulls the `:prefer` option (consumed by
  # `Localize.DateTime.Format.resolve_variant/2`) out of the
  # formatter's option bag, which may be a keyword list or a map.
  defp variant_options(options) do
    case fetch_option(options, :prefer) do
      {:ok, value} -> [prefer: value]
      :error -> []
    end
  end

  defp fetch_option(options, key) when is_list(options), do: Keyword.fetch(options, key)
  defp fetch_option(options, key) when is_map(options), do: Map.fetch(options, key)

  # ── Timezone symbols ─────────────────────────────────────

  alias Localize.DateTime.Timezone

  # z (1-3): Short specific non-location (e.g., "EST")
  # z (4):   Long specific non-location (e.g., "Eastern Standard Time")
  @doc false
  def zone_short(%{time_zone: _} = datetime, count, locale_id, _options) when count in 1..3 do
    case Timezone.non_location_format(datetime, locale_id, format: :short, type: :specific) do
      {:ok, result} -> result
      _ -> ""
    end
  end

  def zone_short(%{time_zone: _} = datetime, 4, locale_id, _options) do
    case Timezone.non_location_format(datetime, locale_id, format: :long, type: :specific) do
      {:ok, result} -> result
      _ -> ""
    end
  end

  def zone_short(%{utc_offset: _} = datetime, count, locale_id, _options) do
    format = if count in 1..3, do: :short, else: :long

    case Timezone.gmt_format(datetime, locale_id, format: format) do
      {:ok, result} -> result
      _ -> ""
    end
  end

  def zone_short(_datetime, _count, _locale_id, _options), do: ""

  # Z (1-3): ISO 8601 basic format (+0500)
  # Z (4):   Localized GMT format (GMT+05:00)
  # Z (5):   ISO 8601 extended with Z for zero (+05:00 or Z)
  @doc false
  def zone_basic(datetime, count, _locale_id, _options) when count in 1..3 do
    {:ok, result} = Timezone.iso_format(datetime, format: :long, type: :basic, z_for_zero: false)
    result
  end

  def zone_basic(datetime, 4, locale_id, _options) do
    case Timezone.gmt_format(datetime, locale_id, format: :long) do
      {:ok, result} -> result
      _ -> ""
    end
  end

  def zone_basic(datetime, 5, _locale_id, _options) do
    {:ok, result} =
      Timezone.iso_format(datetime, format: :full, type: :extended, z_for_zero: true)

    result
  end

  def zone_basic(_datetime, _count, _locale_id, _options), do: ""

  # O (1): Short localized GMT (GMT+1)
  # O (4): Long localized GMT (GMT+01:00)
  @doc false
  def zone_gmt(datetime, 1, locale_id, _options) do
    case Timezone.gmt_format(datetime, locale_id, format: :short, zero_format: :offset) do
      {:ok, result} -> result
      _ -> ""
    end
  end

  def zone_gmt(datetime, 4, locale_id, _options) do
    case Timezone.gmt_format(datetime, locale_id, format: :long, zero_format: :offset) do
      {:ok, result} -> result
      _ -> ""
    end
  end

  def zone_gmt(datetime, _count, locale_id, _options) do
    case Timezone.gmt_format(datetime, locale_id, format: :long) do
      {:ok, result} -> result
      _ -> ""
    end
  end

  # v (1): Short generic non-location (e.g., "ET")
  # v (4): Long generic non-location (e.g., "Eastern Time")
  @doc false
  def generic_non_location(%{time_zone: _} = datetime, count, locale_id, _options) do
    format = if count in 1..3, do: :short, else: :long

    case Timezone.non_location_format(datetime, locale_id, format: format, type: :generic) do
      {:ok, result} -> result
      _ -> ""
    end
  end

  def generic_non_location(datetime, _count, locale_id, _options) do
    case Timezone.gmt_format(datetime, locale_id) do
      {:ok, result} -> result
      _ -> ""
    end
  end

  # V (1-4): Zone ID and location formats
  @doc false
  def specific_non_location(%{time_zone: tz} = _datetime, 1, _locale_id, _options)
      when is_binary(tz) do
    tz
  end

  def specific_non_location(%{time_zone: tz} = _datetime, 2, _locale_id, _options)
      when is_binary(tz) do
    tz
  end

  def specific_non_location(datetime, count, locale_id, _options) do
    format = if count in 1..3, do: :short, else: :long

    case Timezone.gmt_format(datetime, locale_id, format: format) do
      {:ok, result} -> result
      _ -> ""
    end
  end

  # X (1-5): ISO 8601 with Z for zero offset
  @doc false
  def zone_iso_z(datetime, count, _locale_id, _options) do
    {format, type} = iso_format_for_count(count)

    {:ok, result} = Timezone.iso_format(datetime, format: format, type: type, z_for_zero: true)
    result
  end

  # x (1-5): ISO 8601 without Z for zero offset
  @doc false
  def zone_iso(datetime, count, _locale_id, _options) do
    {format, type} = iso_format_for_count(count)

    {:ok, result} = Timezone.iso_format(datetime, format: format, type: type, z_for_zero: false)
    result
  end

  defp iso_format_for_count(1), do: {:short, :basic}
  defp iso_format_for_count(2), do: {:long, :basic}
  defp iso_format_for_count(3), do: {:long, :extended}
  defp iso_format_for_count(4), do: {:full, :basic}
  defp iso_format_for_count(5), do: {:full, :extended}
  defp iso_format_for_count(_), do: {:long, :basic}

  # ── Calendar derivation helpers ────────────────────────────

  defp calendar_year(year) when is_integer(year), do: year

  # Prefer the date's own calendar callback. Calendrical calendars
  # that implement ISO weeks (Gregorian, Julian, composites)
  # return `{year, week}`. Calendars without ISO-week semantics
  # (Hebrew, Islamic, Persian, Japanese imperial, …) return
  # `{:error, :not_defined}` from the Calendrical Behaviour
  # default — in that case we convert to Calendar.ISO and use
  # the Erlang stdlib helper. For plain `Calendar.ISO` dates,
  # which don't carry the callback at all, the stdlib helper
  # is the direct path.
  # CLDR week-of-year per TR35: weeks begin on the locale's first day
  # of the week, and week 1 is the first week containing at least the
  # locale's minimum number of days of the new year. Days before week 1
  # belong to the last week of the previous week-aligned year. Applied
  # to `Calendar.ISO` dates; calendars with their own week schemes keep
  # their `iso_week_of_year/3` callback path.
  defp locale_week_of_year(
         %{year: year, month: month, day: day, calendar: Calendar.ISO},
         locale_id
       ) do
    {first_day, min_days} = week_config(locale_id)
    gregorian_day = :calendar.date_to_gregorian_days({year, month, day})
    this_year_start = week_one_start(year, first_day, min_days)

    cond do
      gregorian_day < this_year_start ->
        previous_start = week_one_start(year - 1, first_day, min_days)
        {year - 1, div(gregorian_day - previous_start, 7) + 1}

      gregorian_day >= week_one_start(year + 1, first_day, min_days) ->
        {year + 1, 1}

      true ->
        {year, div(gregorian_day - this_year_start, 7) + 1}
    end
  end

  defp locale_week_of_year(date, _locale_id) do
    iso_week_of_year(date)
  end

  # The gregorian day number on which week 1 of the given year starts.
  defp week_one_start(year, first_day, min_days) do
    jan1 = :calendar.date_to_gregorian_days({year, 1, 1})
    offset = rem(:calendar.day_of_the_week({year, 1, 1}) - first_day + 7, 7)

    if 7 - offset >= min_days do
      jan1 - offset
    else
      jan1 - offset + 7
    end
  end

  # The locale's week configuration. The CLDR world default (firstDay
  # monday, minDays 1) applies when the locale's territory cannot be
  # resolved.
  defp week_config(locale_id) do
    first_day =
      case Localize.Calendar.first_day_for_locale(locale_id) do
        day when is_integer(day) -> day
        _ -> 1
      end

    min_days =
      case Localize.Calendar.min_days_for_locale(locale_id) do
        days when is_integer(days) -> days
        _ -> 1
      end

    {first_day, min_days}
  end

  defp iso_week_of_year(%{year: year, month: month, day: day, calendar: calendar} = date) do
    if function_exported?(calendar, :iso_week_of_year, 3) do
      case calendar.iso_week_of_year(year, month, day) do
        {y, w} when is_integer(y) and is_integer(w) -> {y, w}
        _ -> iso_week_via_stdlib(date)
      end
    else
      iso_week_via_stdlib(date)
    end
  end

  defp iso_week_of_year(%{year: year, month: month, day: day}) do
    :calendar.iso_week_number({year, month, day})
  end

  defp iso_week_via_stdlib(%{calendar: Calendar.ISO, year: year, month: month, day: day}) do
    :calendar.iso_week_number({year, month, day})
  end

  defp iso_week_via_stdlib(%{} = date) do
    %Date{year: y, month: m, day: d} = Date.convert!(date, Calendar.ISO)
    :calendar.iso_week_number({y, m, d})
  end

  defp compute_day_of_year(%{year: year, month: month, day: day, calendar: calendar})
       when is_integer(year) and is_integer(month) and is_integer(day) do
    if function_exported?(calendar, :day_of_year, 3) do
      calendar.day_of_year(year, month, day)
    else
      compute_day_of_year_gregorian(year, month, day)
    end
  end

  defp compute_day_of_year(%{year: year, month: month, day: day})
       when is_integer(year) and is_integer(month) and is_integer(day) do
    compute_day_of_year_gregorian(year, month, day)
  end

  defp compute_day_of_year_gregorian(year, month, day) do
    days_before =
      for m <- 1..(month - 1), reduce: 0 do
        acc -> acc + Calendar.ISO.days_in_month(year, m)
      end

    days_before + day
  end

  # Calendar protocol requires every implementation to export
  # `day_of_week/4` — dispatch through the date's own calendar.
  # The bare-map clause is for non-`Date` shapes (raw
  # `%{year:, month:, day:}` maps with no `:calendar`); we
  # assume Gregorian for those since there's no other signal.
  defp iso_day(%{year: year, month: month, day: day, calendar: calendar}) do
    {dow, _, _} = calendar.day_of_week(year, month, day, :monday)
    dow
  end

  defp iso_day(%{year: year, month: month, day: day}) do
    {dow, _, _} = Calendar.ISO.day_of_week(year, month, day, :monday)
    dow
  end

  defp quarter_of_year(%{month: month}) when is_integer(month) do
    div(month - 1, 3) + 1
  end

  # ── General helpers ────────────────────────────────────────

  defp format_for_count(count) do
    case count do
      n when n in 1..3 -> :abbreviated
      4 -> :wide
      5 -> :narrow
      6 -> :short
      _ -> :abbreviated
    end
  end

  defp pad(integer, n) when is_integer(integer) and integer >= 0 do
    str = Integer.to_string(integer)
    padding = n - String.length(str)

    if padding <= 0 do
      str
    else
      String.duplicate("0", padding) <> str
    end
  end

  defp pad(integer, n) when is_integer(integer) and integer < 0 do
    "-" <> pad(abs(integer), n)
  end

  defp pad(string, n) when is_binary(string) do
    len = String.length(string)

    if len >= n do
      string
    else
      String.duplicate("0", n - len) <> string
    end
  end
end
