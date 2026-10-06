defmodule Localize.Interval do
  @moduledoc """
  Formats date and time intervals as localized strings.

  Interval formats produce strings like "Jan 10 – 12, 2008" from
  two dates, rather than repeating "Jan 10, 2008 – Jan 12, 2008".
  The format is selected based on the greatest calendar field
  difference between the start and end values.

  An interval is formatted with the formats of its endpoints' calendar: its interval patterns, its date and time formats, and the date-time pattern joining a date to a time range. Both endpoints must therefore be in the same calendar. An era is a calendar field like any other, so endpoints in different eras show their eras where the locale has a pattern for them, as ICU does: "Dec 31, 1 BC – Jan 1, 1 AD".

  The two values are written in the order the locale's interval fallback pattern states, which TR35 makes the order of every interval pattern: the earlier first in every locale but one of CLDR 49. `kek`'s Gregorian pattern is "{1} – {0}", so it writes the later value first.

  """

  import Kernel, except: [to_string: 1]
  import Localize.Utils.Helpers, only: [is_keyword_list: 1]

  # Locale-independent skeletons for the non-default `:fields`
  # options. The default `:date` selection is resolved per-locale from
  # `Localize.DateTime.Format.date_formats/1` (see `resolve_fields/3`)
  # so date intervals follow the same conventions single
  # `Localize.Date.to_string/2` does for the same `:format`.
  @field_skeletons %{
    month: %{full: :MMM, long: :MMM, medium: :MMM, short: :M},
    month_and_day: %{full: :MMMEd, long: :MMMEd, medium: :MMMd, short: :Md},
    year_and_month: %{full: :yMMMM, long: :yMMMM, medium: :yMMM, short: :yM}
  }

  @default_fields :date
  @default_format :medium

  # The fields of a date, largest first. A date holds any of them, and a
  # whole date all three.
  @date_fields [:year, :month, :day]

  # TR35 joins an interval's date and time with the standard date-time
  # pattern ("March 15, 3:00 – 5:00 PM"), where a single date and time takes
  # the "at" pattern by default.
  @interval_style :default

  @doc """
  Formats an interval between two dates, times or datetimes as a localized string.

  ### Arguments

  * `from` is the start of the interval: a `t:Date.t/0`, `t:Time.t/0`, `t:NaiveDateTime.t/0` or `t:DateTime.t/0`, or a map with their fields, or `nil` for an interval open at its start. A date's map may hold only some of its `:year`, `:month` and `:day`.

  * `to` is the end of the interval, of the same kind as `from`, or `nil` for an interval open at its end.

  * `options` is a keyword list of options.

  ### Options

  * `:locale` is a locale identifier. The default is `:en`.

  * `:format` is a standard format, `:short`, `:medium`, `:long` or `:full`, a skeleton such as `:yMMMEd` or `:yMMMdHm`, or a pattern such as `"d MMM y"`. The default is `:medium`. A skeleton selects CLDR's interval format for its fields, as CLDR keys them, so it can name a format no standard format reaches. A pattern names no interval format, so both endpoints are formatted with it around the locale's interval fallback pattern. A datetime interval's skeleton is split into its date and time fields, as TR35's interval algorithm separates them: on one day the date is written once and the times as a range, a skeleton of time fields alone writes only the times, and a skeleton of date fields alone formats the dates as a date interval does. A date in a calendar of weeks, such as `Calendrical.ISOWeek`, is written at a standard format in the calendar's own notation, so an interval of its dates is both dates around the fallback pattern: "2026-W25-2 – 2026-W27-1". A skeleton's month is such a date's week and its day the weekday, which no interval format is keyed by, so its interval is both dates in full too: "Tue, week 25 of 2026 – Mon, week 26 of 2026".

  * `:date_format` and `:time_format` choose the date and the time half of a datetime interval separately, each a standard format, a skeleton or a pattern. `:date_format` is a date interval's format too, and `:time_format` a time interval's.

  * `:fields` selects *which* date fields a date interval shows with a standard `:format`: `:date` (the whole date, the default), `:month`, `:month_and_day`, or `:year_and_month`. See `known_fields/0`.

  * `:style` is the pattern joining a datetime interval's date and time: `:default`, the locale's standard date-time pattern, which TR35 says an interval takes ("June 15, 2026, 10:00 – 14:30"), or `:at`, the "at time" pattern a single date and time takes by default in `Localize.DateTime.to_string/2`. The default is `:default`.

  * `:numeric_date_separator` and `:numeric_time_separator` are
    strings replacing the locale's own separators in the rendered
    pattern, as they do on `Localize.Date.to_string/2`. A separator
    the pattern merges with neighbouring literal text is left alone
    — fi's day-differing interval pattern is `"d.–d.M.y"`, whose
    first separator carries the range dash — so an interval may
    substitute one endpoint and not the other.

  With a standard format the two are independent axes: `:fields` chooses which fields appear, `:format` chooses how wide they are rendered. So `fields: :year_and_month` renders the two months against a single year either way — numerically for `format: :short` ("1/2022" … "3/2022") and spelled out for `format: :long` ("January" … "March 2022").

  At a standard format an interval's dates and times have the fields of the pattern the single value is written with, at the pattern's widths, so they read as `Localize.Date.to_string/2` and `Localize.Time.to_string/2` write one alone: `vi`'s short date is "1/4/23" and its interval "1/4/23 – 10/4/23", and a locale whose short time is 24-hour writes a 24-hour range. The order and the text between the fields are those of CLDR's interval format for those fields.

  Endpoints that differ in no field the interval shows are formatted once: whole dates in the requested standard format, exactly as `Localize.Date.to_string/2` renders them. A date interval's fields are compared as its format writes them, so a week (`:yw`) or a quarter (`:yQQQ`) is one field whatever months and days it spans: 15 June to 20 July 2026 is "week 25 of 2026 – week 30 of 2026", and 15 to 17 June "week 25 of 2026". Two dates that differ in a month or a year the skeleton does not write take the interval of the skeleton widened with it: `format: :d` from 15 June to 20 July is "6/15 – 7/20", and to a day of the next year "6/15/2026 – 7/20/2027".

  Dates that hold only some of their fields, two months or a month and a day each, take at a standard format CLDR's interval format for the fields they hold, as `Localize.Date.to_string/2` writes each alone: `%{month: 6}` to `%{month: 8}` is "Jun – Aug". One format writes both endpoints, so they must hold the same fields. A skeleton, a `:fields` selection or a pattern is used as it is given.

  ### Returns

  * `{:ok, formatted_string}` on success.

  * `{:error, exception}` on failure, including endpoints in different calendars and dates that hold different fields.

  ### Examples

      iex> Localize.Interval.to_string(~D[2022-04-22], ~D[2022-04-25], locale: :en)
      {:ok, "Apr 22 – 25, 2022"}

      iex> Localize.Interval.to_string(~D[2026-06-15], ~D[2026-06-18], format: :yMMMEd, locale: :en)
      {:ok, "Mon, Jun 15 – Thu, Jun 18, 2026"}

      iex> Localize.Interval.to_string(%{month: 6, day: 15}, %{month: 6, day: 20}, locale: :en)
      {:ok, "Jun 15 – 20"}

      iex> Localize.Interval.to_string(~N[2026-06-15 10:00:00], ~N[2026-06-15 14:30:00],
      ...>   format: :yMMMdHm,
      ...>   locale: :en
      ...> )
      {:ok, "Jun 15, 2026, 10:00 – 14:30"}

      iex> Localize.Interval.to_string(~N[2026-06-15 10:00:00], ~N[2026-06-15 14:30:00],
      ...>   format: :Hm,
      ...>   locale: :en
      ...> )
      {:ok, "10:00 – 14:30"}

  """
  @spec to_string(map() | nil, map() | nil, Keyword.t()) ::
          {:ok, String.t()} | {:error, Exception.t()}
  def to_string(from, to, options \\ [])

  def to_string(nil, nil, options) when is_keyword_list(options) do
    {:error, Localize.DateTimeInvalidInputError.exception(type: :datetime)}
  end

  def to_string(nil, to, options) when not is_nil(to) and is_keyword_list(options) do
    format_open_interval(to, :open_start, options)
  end

  def to_string(from, nil, options) when not is_nil(from) and is_keyword_list(options) do
    format_open_interval(from, :open_end, options)
  end

  def to_string(from, to, options) when is_keyword_list(options) do
    format_closed_interval(from, to, options, :string)
  end

  def to_string(_from, _to, options),
    do: {:error, Localize.Utils.Helpers.invalid_options(options)}

  @doc """
  Formats a date, time, or datetime interval into typed parts, mirroring ECMA-402's `formatRangeToParts`.

  The parts concatenate to exactly the string `to_string/3` produces with the same options. Every part carries a `:source` key: `:start_range` for parts of the interval start, `:end_range` for parts of the interval end, and `:shared` for the separators between them. When the endpoints have no practical difference the single formatted value carries source `:shared` throughout.

  Unlike `to_string/3`, open intervals (a `nil` endpoint) are not supported — both endpoints are required, matching the JS API.

  ### Arguments

  * `from` is a `Date`, `Time`, `DateTime`, `NaiveDateTime`, or compatible map for the interval start.

  * `to` is a value of the same kind for the interval end.

  * `options` is a keyword list of options. See `to_string/3`.

  ### Returns

  * `{:ok, parts}` where `parts` is a list of `%{type: atom(), value: String.t(), source: atom()}` maps.

  * `{:error, exception}` on failure or when an endpoint is `nil`.

  ### Examples

      iex> Localize.Interval.to_parts(~D[2022-04-22], ~D[2022-04-25], locale: :en)
      {:ok,
       [
         %{type: :month, value: "Apr", source: :start_range},
         %{type: :literal, value: " ", source: :start_range},
         %{type: :day, value: "22", source: :start_range},
         %{type: :literal, value: " – ", source: :shared},
         %{type: :day, value: "25", source: :end_range},
         %{type: :literal, value: ", ", source: :end_range},
         %{type: :year, value: "2022", source: :end_range}
       ]}

  """
  @spec to_parts(map(), map(), Keyword.t()) ::
          {:ok, [%{type: atom(), value: String.t(), source: atom()}]} | {:error, Exception.t()}
  def to_parts(from, to, options \\ [])

  def to_parts(from, to, options)
      when (is_nil(from) or is_nil(to)) and is_keyword_list(options) do
    {:error, Localize.DateTimeInvalidInputError.exception(type: :datetime)}
  end

  def to_parts(from, to, options) when is_keyword_list(options) do
    format_closed_interval(from, to, options, :parts)
  end

  def to_parts(_from, _to, options),
    do: {:error, Localize.Utils.Helpers.invalid_options(options)}

  @doc """
  Same as `to_parts/3` but raises on error.

  ### Arguments

  * `from` is the interval start.

  * `to` is the interval end.

  * `options` is a keyword list of options. See `to_parts/3`.

  ### Returns

  * A list of `%{type: atom(), value: String.t(), source: atom()}` maps.

  ### Raises

  * Raises an exception if the interval cannot be decomposed into parts.

  ### Examples

      iex> Localize.Interval.to_parts!(~D[2022-04-22], ~D[2022-04-25], locale: :en) |> length()
      7

  """
  @spec to_parts!(map(), map(), Keyword.t()) ::
          [%{type: atom(), value: String.t(), source: atom()}]
  def to_parts!(from, to, options \\ []) do
    case to_parts(from, to, options) do
      {:ok, parts} -> parts
      {:error, exception} -> raise exception
    end
  end

  # An interval is formatted with the formats of its endpoints' calendar, so
  # endpoints in two calendars have none to share, as for ICU.
  defp format_closed_interval(from, to, options, output) do
    if calendar_of(from) != calendar_of(to) do
      {:error,
       Localize.DateTimeIntervalFormatError.exception(
         reason: :mixed_calendars,
         detail: "#{inspect(calendar_of(from))} and #{inspect(calendar_of(to))}"
       )}
    else
      with :ok <- Localize.Calendar.validate_value(from),
           :ok <- Localize.Calendar.validate_value(to) do
        format_endpoints(from, to, options, output)
      end
    end
  end

  defp format_endpoints(from, to, options, output) do
    cond do
      datetime_value?(from) and datetime_value?(to) ->
        format_datetime_interval(from, to, options, output)

      time_value?(from) and time_value?(to) ->
        format_time_interval(from, to, options, output)

      date_value?(from) and date_value?(to) ->
        format_date_interval(from, to, options, output)

      true ->
        {:error, mixed_endpoints(from, to)}
    end
  end

  defp mixed_endpoints(from, to) do
    Localize.DateTimeIntervalFormatError.exception(
      reason: :mixed_endpoints,
      detail: "#{inspect(from)} and #{inspect(to)}"
    )
  end

  # ── Type detection ───────────────────────────────────────────
  #
  # A value is known by the fields it holds: a date by a year, a month or a
  # day, a time by an hour, and a date and time by both. A date need not
  # hold a year: a month, or a month and a day, is a date ("Jun", "Jun 15"),
  # as `Localize.Date.to_string/2` writes it. Struct types
  # Date/Time/NaiveDateTime/DateTime are handled explicitly; generic maps
  # fall back to key-presence.

  defp datetime_value?(%DateTime{}), do: true
  defp datetime_value?(%NaiveDateTime{}), do: true
  defp datetime_value?(%Date{}), do: false
  defp datetime_value?(%Time{}), do: false
  defp datetime_value?(%{hour: _} = map), do: date_fields(map) != []
  defp datetime_value?(_), do: false

  defp date_value?(%Date{}), do: true
  defp date_value?(%{} = map), do: date_fields(map) != [] and not Map.has_key?(map, :hour)
  defp date_value?(_), do: false

  defp time_value?(%Time{}), do: true
  defp time_value?(%DateTime{}), do: false
  defp time_value?(%NaiveDateTime{}), do: false
  defp time_value?(%Date{}), do: false
  defp time_value?(%{hour: _} = map), do: date_fields(map) == []
  defp time_value?(_), do: false

  # The date fields a value holds, largest first.
  defp date_fields(value), do: Enum.filter(@date_fields, &Map.has_key?(value, &1))

  # A value's calendar module; a map without one is taken as `Calendar.ISO`,
  # as the formatters take it.
  defp calendar_of(value) when is_map(value), do: Map.get(value, :calendar, Calendar.ISO)
  defp calendar_of(_value), do: Calendar.ISO

  # The CLDR calendar whose data formats a value: its calendar's answer for
  # the value's date.
  defp cldr_calendar_for(value) when is_map(value),
    do: Localize.Calendar.date_calendar_type(value)

  defp cldr_calendar_for(_value), do: :gregorian

  defp interval_formats(locale_id, value),
    do: Localize.DateTime.Format.interval_formats(locale_id, cldr_calendar_for(value))

  # ── Date-only interval (the original path) ──────────────────

  defp format_date_interval(from, to, options, output) do
    locale = Keyword.get(options, :locale, Localize.get_locale())

    # `:date_format` is the explicit date-axis selector and matches
    # the option used on datetime intervals (where `date_sub_options/1`
    # honours it). For date-only intervals it must take precedence
    # over `:format`, mirroring the precedence used on the time-only
    # path with `:time_format`.
    format =
      Keyword.get(options, :date_format) ||
        Keyword.get(options, :format, @default_format)

    fields = Keyword.get(options, :fields, @default_fields)

    with {:ok, locale_id} <- resolve_locale_id(locale) do
      case resolve_date_fields(fields, format, locale_id, {from, to}, options) do
        {:ok, {:fallback_style, fallback_format}} ->
          # CLDR ships no skeleton-keyed interval-format data for the
          # per-locale skeleton (e.g. ja's `:yMMdd` for `:short`,
          # en's `:yMMMMd` for `:long`, every locale's `:yMMMMEEEEd`
          # for `:full`). Format each endpoint via
          # `Localize.Date.to_string/2` with the requested style and
          # join via the locale's `interval_format_fallback`.
          format_date_interval_fallback(from, to, fallback_format, locale, options, output)

        {:ok, {format_key, requested_skeleton}} ->
          skeletons = {format_key, requested_skeleton}
          whole_format = whole_date_format(fields, format, requested_skeleton)
          format_date_interval_styled(from, to, skeletons, whole_format, locale, options, output)

        {:ok, format_key} ->
          whole_format = whole_date_format(fields, format, format_key)

          format_date_interval_styled(
            from,
            to,
            {format_key, nil},
            whole_format,
            locale,
            options,
            output
          )

        {:error, _} = error ->
          error
      end
    end
  end

  # A date whose calendar writes its dates in a notation of its own is
  # written in it at a standard format, "2026-W25-2" for a calendar of weeks
  # (`Localize.Date.to_string/2`), and no interval format shares a notation's
  # fields, so whole dates are written in full around the fallback pattern,
  # or once when they are the same day.
  defp resolve_date_fields(:date, format, locale_id, {from, to}, options)
       when format in [:short, :medium, :long, :full] do
    case Localize.Calendar.own_notation?(calendar_of(from)) do
      {:ok, true} -> {:ok, {:fallback_style, format}}
      {:ok, false} -> resolve_standard_format(format, locale_id, {from, to}, options)
      {:error, _exception} = error -> error
    end
  end

  # A skeleton's month is such a calendar's week and its day the weekday
  # (`Localize.Date.own_fields/2`), which no interval format is keyed by, so
  # its dates are written in full with the skeleton too: "Tue, week 25 of
  # 2026 – Mon, week 26 of 2026" for `yMMMd`, where CLDR's generic `yMMMd`
  # interval wrote the calendar's period and day number as a month and a
  # day of the month.
  defp resolve_date_fields(:date, skeleton, locale_id, {from, _to}, _options)
       when is_atom(skeleton) and not is_nil(skeleton) do
    case Localize.Calendar.own_notation?(calendar_of(from)) do
      {:ok, true} -> {:ok, {:fallback_style, skeleton}}
      {:ok, false} -> resolve_fields(:date, skeleton, locale_id, cldr_calendar_for(from))
      {:error, _exception} = error -> error
    end
  end

  defp resolve_date_fields(fields, format, locale_id, {from, _to}, _options),
    do: resolve_fields(fields, format, locale_id, cldr_calendar_for(from))

  # A whole date takes the locale's standard date format. A date without one
  # of its fields takes the format of the fields it holds, as
  # `Localize.Date.to_string/2` writes it alone: two months are "Jun – Aug",
  # CLDR's `MMM` interval, and two days of one month "Jun 15 – 20", its
  # `MMMd`. One format writes both ends, so they must hold the same fields.
  defp resolve_standard_format(format, locale_id, {from, to}, options) do
    calendar = cldr_calendar_for(from)

    cond do
      date_fields(from) == @date_fields ->
        standard_date_fields(format, {locale_id, calendar}, options)

      date_fields(from) == date_fields(to) ->
        resolve_fields(:date, Localize.Date.derive_format_id(from, format), locale_id, calendar)

      true ->
        {:error, mixed_endpoints(from, to)}
    end
  end

  # A standard format's interval is the one for the fields of its pattern, at
  # the widths the pattern writes them, so the dates of an interval are
  # written as `Localize.Date.to_string/2` writes one alone (user,
  # 2026-10-04: "the pattern").
  #
  # The locale's item for the skeleton may be missing from CLDR's interval
  # table (`ja`'s `yMMdd`, `en`'s `yMMMMd`, every locale's `yMMMMEEEEd`); the
  # closest item then takes its widths, and failing that each date is
  # written in full around the fallback pattern.
  defp standard_date_fields(format, {locale_id, calendar} = lookup, options) do
    with {:ok, skeleton} <- standard_date_skeleton(format, lookup, options),
         {:ok, interval_formats} <-
           Localize.DateTime.Format.interval_formats(locale_id, calendar) do
      skeleton_or_fallback_style(skeleton, interval_formats, format, lookup)
    end
  end

  # The skeleton of a standard date format: the fields of its pattern, at the
  # widths the pattern writes them. CLDR gives each standard format a
  # skeleton too, which TR35 calls "derived from the pattern" and which in
  # many locales is not: `vi`'s short date is "d/M/yy" beside a skeleton of
  # `yMMdd`, inherited from root, and an interval that asked for that was
  # "01/04/2023 – 10/04/2023" where the date alone is "1/4/23".
  #
  # A pattern does not say whether a month it writes as a number is the
  # month's name, as it is in "y年M月d日", where CLDR's skeleton has `MMM`
  # and the interval formats of that key write "M月". So a month the pattern
  # numbers beside a word takes the skeleton's month where the skeleton
  # names it. ICU and ECMA-402 take the pattern's fields with no such care,
  # and write the dates of a `ja` long interval as "2023/04/01".
  defp standard_date_skeleton(format, {locale_id, calendar}, options) do
    alias Localize.DateTime.Format

    with {:ok, pattern} <- Format.resolve_format(:date, format, locale_id, calendar, options),
         {:ok, skeletons} <- Format.date_formats(locale_id, calendar) do
      fields = Format.Match.pattern_skeleton(pattern)
      {:ok, fields |> with_named_month(pattern, Map.get(skeletons, format)) |> skeleton_atom()}
    end
  end

  defp with_named_month(fields, pattern, skeleton)
       when is_atom(skeleton) and not is_nil(skeleton) do
    with [named] <- Regex.run(~r/[ML]{3,}/, Atom.to_string(skeleton)),
         [numbered] when byte_size(numbered) <= 2 <- Regex.run(~r/[ML]+/, fields),
         true <- literal_words?(pattern) do
      String.replace(fields, numbered, named, global: false)
    else
      _not_a_named_month -> fields
    end
  end

  defp with_named_month(fields, _pattern, _no_skeleton), do: fields

  # Whether a pattern's literal text holds a word: a letter in quotes, or a
  # letter outside them that is no field, as "年" and "月" are.
  defp literal_words?(pattern) do
    quoted = ~r/'(?:[^']|'')*'/u

    Enum.any?(Regex.scan(quoted, pattern), fn [text] -> text =~ ~r/\p{L}/u end) or
      pattern
      |> then(&Regex.replace(quoted, &1, ""))
      |> then(&Regex.replace(~r/[a-zA-Z]/, &1, ""))
      |> String.match?(~r/\p{L}/u)
  end

  # The fields of a pattern the locale data holds, as the atom a skeleton
  # is: it adds at most one atom per pattern.
  defp skeleton_atom(fields), do: String.to_atom(fields)

  # The format of a date formatted whole — alone, when the values differ in
  # no unit the interval shows, or in full around the fallback pattern. For
  # whole dates it is the requested standard format, so a date reads exactly
  # as `Localize.Date.to_string/2` renders it, as ECMA-402's `formatRange`
  # renders it; for other fields it is their skeleton.
  defp whole_date_format(:date, format, _skeleton) when format in [:short, :medium, :long, :full],
    do: format

  defp whole_date_format(_fields, _format, skeleton), do: skeleton

  defp format_date_interval_styled(from, to, skeletons, whole_format, locale, options, output) do
    {format_key, requested_skeleton} = skeletons
    skeleton = requested_skeleton || format_key

    with {:ok, locale_id} <- resolve_locale_id(locale),
         {:ok, formats} <- interval_formats(locale_id, from) do
      options_map = options |> Map.new() |> Map.put_new(:locale, locale)
      lookup = {locale_id, cldr_calendar_for(from)}

      plan_options = Keyword.put_new(options, :locale, locale)

      case date_interval_plan(formats, skeletons, {from, to}, lookup, plan_options) do
        :single ->
          format_single(output, Localize.Date, from, Keyword.put(options, :format, whole_format))

        {:split, left, right} ->
          numbered = with_format_numbering(options_map, whole_format, {from, to}, lookup)
          format_split(output, from, to, left, right, locale_id, numbered)

        {:fallback, ^skeleton} ->
          format_in_full(output, Localize.Date, {from, to}, whole_format, formats, options)

        {:fallback, fallback_skeleton} ->
          format_in_full(output, Localize.Date, {from, to}, fallback_skeleton, formats, options)

        {:error, _} = error ->
          error
      end
    end
  end

  # An interval of two whole dates at a standard format writes its numbers
  # in the numbering the format states for them, as the date alone is
  # written (user, 2026-10-06). CLDR gives a standard date format's pattern,
  # and the skeleton it gives beside it, a `numbers` attribute, which TR35
  # has "specify a number system to be used for all of the numeric fields in
  # the date format" or for one of them; an interval item has none of its
  # own, and it is the format's skeleton the interval is made from. So
  # `he`'s Hebrew medium interval is "א׳–ה׳ בתמוז ה׳תשפ״ו" beside the date
  # "א׳ בתמוז ה׳תשפ״ו", and `zh`'s Chinese "2026年五月初二至初六" beside
  # "2026年五月初二", where both were digits, "1–5 בתמוז 5786", as ICU's
  # `DateIntervalFormat` writes them. A numbering the caller gives stands
  # over the format's, as it does for a date alone. A date without one of
  # its fields is written with no standard format, and neither is its
  # interval.
  defp with_format_numbering(options_map, format, {from, to}, {locale_id, calendar})
       when format in [:short, :medium, :long, :full] do
    if date_fields(from) == @date_fields and date_fields(to) == @date_fields do
      numbers =
        Localize.DateTime.Format.number_system_overrides(:date, format, locale_id, calendar)

      Map.update(options_map, :number_system_overrides, numbers, &over_format(&1, numbers))
    else
      options_map
    end
  end

  defp with_format_numbering(options_map, _format, _dates, _lookup), do: options_map

  defp over_format(given, numbers) when is_map(given), do: Map.merge(numbers, given)
  defp over_format(given, _numbers), do: given

  # TR35 §Interval Formats steps 4 to 7, as ICU implements them. Values that
  # differ in no field the skeleton writes format as one. A year or a month
  # difference for a skeleton without one takes the pattern of the skeleton
  # widened with it, so an interval across a year or a month boundary keeps
  # both, and an era difference for a skeleton without an era takes the
  # closest item's pattern for the skeleton widened with one, so each value
  # shows its era: "Apr 30, 31 Heisei – May 1, 1 Reiwa". Any other
  # difference takes the item's pattern for it, or failing that the fallback
  # pattern around both values in full.
  defp date_interval_plan(formats, {format_key, requested_skeleton}, {from, to}, lookup, options) do
    skeleton = requested_skeleton || format_key
    difference = calendar_difference(from, to)
    {locale_id, _calendar} = lookup

    cond do
      not date_difference_visible?(skeleton, difference, {from, to}, locale_id, options) ->
        :single

      across_cycles?(from, to, locale_id) ->
        in_full_with_year(skeleton, from, locale_id, options)

      difference == :era and is_nil(item_pattern(Map.get(formats, format_key), :G)) and
          not String.contains?(Kernel.to_string(skeleton), "G") ->
        era_widened_split(formats, {format_key, requested_skeleton}, lookup, options)

      true ->
        with nil <- widened_split(formats, skeleton, difference, {from, to}, lookup, options) do
          key = difference_key(difference, skeleton, Map.get(formats, format_key))
          interval_split(formats, format_key, requested_skeleton, key, options, skeleton)
        end
    end
  end

  # Two dates of different sixty-year cycles, in a calendar of cyclic years
  # (`Localize.Calendar.cycle/2`). An interval item writes a year once or
  # twice as the item's own year, which in those calendars is the year's
  # place in its cycle or its name, the same in every cycle: `en`'s `yMd`
  # item wrote 16 June 2026 to 12 June 2086 as "5/2/43 – 5/2/43". So the
  # two are written in full, each as the format writes a date alone (user,
  # 2026-10-06), as ICU, which holds the cycle as an era, writes them:
  # "5/2/2026 – 5/2/2086". A format that writes no year is widened with one
  # first, as it is for any two years.
  defp across_cycles?(from, to, locale_id) do
    with {:ok, from_cycle} <- Localize.Calendar.cycle(from, locale_id),
         {:ok, to_cycle} <- Localize.Calendar.cycle(to, locale_id) do
      from_cycle != to_cycle
    else
      _no_cycle -> false
    end
  end

  # The widened skeleton is one a date is written with, whether or not the
  # locale's data holds a format under its name: no atom is made of it.
  defp in_full_with_year(skeleton, date, locale_id, options) do
    with true <- is_atom(skeleton) and skeleton not in [:short, :medium, :long, :full],
         widened when is_binary(widened) <- widened_skeleton(skeleton, :year),
         format when is_atom(format) and not is_nil(format) <-
           Localize.Utils.Helpers.existing_atom(widened),
         {:ok, _pattern} <- Localize.Date.resolve_pattern(date, format, locale_id, options) do
      {:fallback, format}
    else
      _as_it_is -> {:fallback, skeleton}
    end
  end

  # The pattern of the skeleton widened with the month, or the year, the two
  # dates differ in and it does not write, as ICU widens one: a day alone
  # takes its month across months, "6/15 – 7/15" where two bare days would
  # read as days of one month, and its month and year across years; a month
  # and a day take their year. The widened skeleton takes the closest item's
  # pattern at its own widths, or is written in full for both dates where the
  # locale has it as a format but no interval of it ("Q2 2026 – Q2 2027").
  # Two dates the widened skeleton writes alike are one, as two days of one
  # week either side of the new year are to a week and its year. `nil` where
  # the skeleton writes the field, or cannot be widened.
  defp widened_split(
         formats,
         skeleton,
         difference,
         dates,
         {locale_id, _calendar} = lookup,
         options
       ) do
    with widened when is_binary(widened) <- widened_skeleton(skeleton, difference),
         {:ok, plan, format} <- widened_plan(formats, widened, difference, lookup, options) do
      if date_difference_visible?(format, difference, dates, locale_id, options),
        do: plan,
        else: :single
    else
      _not_widened -> nil
    end
  end

  defp widened_plan(formats, widened, difference, {locale_id, calendar}, options) do
    case Localize.DateTime.Format.Match.best_interval_match(widened, locale_id, calendar) do
      {:ok, matched} ->
        requested = if Atom.to_string(matched) == widened, do: nil, else: widened
        key = difference_key(difference, matched, nil)
        {:ok, interval_split(formats, matched, requested, key, options, matched), matched}

      :error ->
        with {:fallback, format} = plan <- widened_in_full(widened, locale_id, calendar) do
          {:ok, plan, format}
        end
    end
  end

  defp widened_skeleton(skeleton, :month) do
    if day_without_month?(format_letters(skeleton)), do: "M" <> Kernel.to_string(skeleton)
  end

  defp widened_skeleton(skeleton, :year) do
    letters = format_letters(skeleton)

    cond do
      Enum.any?(letters, &(&1 in ~w(G y Y u U r))) -> nil
      day_without_month?(letters) -> "yM" <> Kernel.to_string(skeleton)
      true -> "y" <> Kernel.to_string(skeleton)
    end
  end

  defp widened_skeleton(_skeleton, _difference), do: nil

  defp day_without_month?(letters),
    do: "d" in letters and not Enum.any?(letters, &(&1 in ~w(M L)))

  # A widened skeleton with no interval of its own is written for both dates
  # where it is one of the locale's formats, by the name the locale data
  # holds it under: no atom is made of it.
  defp widened_in_full(widened, locale_id, calendar) do
    with {:ok, available} <- Localize.DateTime.Format.available_formats(locale_id, calendar),
         format when is_atom(format) and not is_nil(format) <-
           Localize.Utils.Helpers.existing_atom(widened),
         true <- Map.has_key?(available, format) do
      {:fallback, format}
    else
      _not_a_format -> nil
    end
  end

  # The era pattern of the matched item widened with `G`, found as ICU finds
  # it: the item keyed by `G` and the matched skeleton, or, when the skeleton
  # matched its item exactly, the item closest to that. The pattern takes the
  # requested widths, so `yMMMM` takes `GyMMM`'s with the month spelled out.
  # Without one, both values are formatted in full.
  defp era_widened_split(formats, {format_key, requested_skeleton}, lookup, options) do
    {locale_id, calendar} = lookup
    skeleton = requested_skeleton || format_key
    widened = "G" <> Kernel.to_string(format_key)

    with {:ok, widened_key} <-
           Localize.DateTime.Format.Match.best_interval_match(widened, locale_id, calendar),
         true <- is_nil(requested_skeleton) or Kernel.to_string(widened_key) == widened do
      requested = "G" <> Kernel.to_string(skeleton)
      interval_split(formats, widened_key, requested, :G, options, skeleton)
    else
      _no_era_pattern -> {:fallback, skeleton}
    end
  end

  # A format with no interval of its own: both dates in full around the
  # fallback pattern, or one where they differ in no field it writes. A
  # skeleton that does not write the month or the year they differ in is
  # widened with it first, as one with an interval is, so a weekday and a day
  # across months take the interval of `MEd`.
  defp format_date_interval_fallback(from, to, format, locale, options, output) do
    with {:ok, locale_id} <- resolve_locale_id(locale),
         {:ok, formats} <- interval_formats(locale_id, from) do
      field_options = Keyword.put_new(options, :locale, locale)

      case fallback_plan(formats, format, {from, to}, locale_id, field_options) do
        :single ->
          format_single(output, Localize.Date, from, Keyword.put(options, :format, format))

        {:split, left, right} ->
          format_split(output, from, to, left, right, locale_id, Map.new(field_options))

        {:fallback, in_full} ->
          format_in_full(output, Localize.Date, {from, to}, in_full, formats, options)

        {:error, _} = error ->
          error
      end
    end
  end

  defp fallback_plan(formats, format, {from, to} = dates, locale_id, options) do
    difference = calendar_difference(from, to)
    lookup = {locale_id, cldr_calendar_for(from)}

    cond do
      not date_difference_visible?(format, difference, dates, locale_id, options) ->
        :single

      across_cycles?(from, to, locale_id) ->
        in_full_with_year(format, from, locale_id, options)

      own_fields?(from, format) ->
        own_fields_in_full(format, difference, from, locale_id, options)

      true ->
        widened_fallback(formats, format, difference, dates, lookup, options) ||
          {:fallback, format}
    end
  end

  # A skeleton for a calendar that writes its dates in a notation of its
  # own, a calendar of weeks, whose month is the week.
  defp own_fields?(from, format) do
    is_atom(format) and not is_nil(format) and format not in [:short, :medium, :long, :full] and
      match?({:ok, true}, Localize.Calendar.own_notation?(calendar_of(from)))
  end

  # Both dates in full with the skeleton, widened with the week or the year
  # they differ in where it writes neither, as a skeleton of months and days
  # is: no interval format is keyed by a week and a weekday, so none is
  # looked for.
  defp own_fields_in_full(format, difference, from, locale_id, options) do
    with widened when is_binary(widened) <- widened_skeleton(format, difference),
         skeleton when is_atom(skeleton) and not is_nil(skeleton) <-
           Localize.Utils.Helpers.existing_atom(widened),
         {:ok, _pattern} <- Localize.Date.resolve_pattern(from, skeleton, locale_id, options) do
      {:fallback, skeleton}
    else
      _as_it_is -> {:fallback, format}
    end
  end

  # Only a skeleton is widened: a pattern is written as it is given, and a
  # standard format writes a whole date.
  defp widened_fallback(formats, format, difference, dates, lookup, options)
       when is_atom(format) and not is_nil(format) and
              format not in [:short, :medium, :long, :full],
       do: widened_split(formats, format, difference, dates, lookup, options)

  defp widened_fallback(_formats, _format, _difference, _dates, _lookup, _options), do: nil

  # TR35's final step: both values formatted in full with `format` and joined
  # by the locale's interval fallback pattern.
  defp format_in_full(output, module, {from, to}, format, formats, options) do
    sub_options =
      options
      |> Keyword.take([:locale, :prefer])
      |> Keyword.put(:format, format)

    with {:ok, fallback} <- get_fallback_pattern(formats) do
      format_fallback(output, {module, from, sub_options}, {module, to, sub_options}, fallback)
    end
  end

  # ── Time-only interval ──────────────────────────────────────

  defp format_time_interval(from, to, options, output) do
    locale = Keyword.get(options, :locale, Localize.get_locale())

    # `:time_format` is the explicit time-axis selector and matches
    # the option used on datetime intervals (where `time_sub_options/1`
    # honours it). For time-only intervals it must take precedence
    # over `:format`, which is overloaded across interval shapes.
    format =
      Keyword.get(options, :time_format) ||
        Keyword.get(options, :format, @default_format)

    case resolve_time_style(format, from, locale, options) do
      {:ok, {:literal, pattern}} ->
        format_time_interval_literal(from, to, pattern, locale, options, output)

      {:ok, {:fallback_style, style}} ->
        # CLDR ships no interval-format data for `:hms` / `:hmsv`
        # skeletons. Format each endpoint via `Localize.Time.to_string/2`
        # with the requested style and join with the interval fallback.
        format_time_interval_literal(from, to, style, locale, options, output)

      {:ok, {:standard, skeleton}} ->
        format_time_interval_styled(from, to, {skeleton, format}, locale, options, output)

      {:ok, format_key} ->
        format_time_interval_styled(from, to, {format_key, nil}, locale, options, output)

      {:error, _} = error ->
        error
    end
  end

  # The same steps as a date interval: an invisible difference formats one
  # time, and a difference the item has no pattern for glues both in full. A
  # time written whole is written with the standard format where one was
  # asked for, as `Localize.Time.to_string/2` writes it, and else with the
  # skeleton.
  defp format_time_interval_styled(from, to, {format_key, standard}, locale, options, output) do
    with {:ok, locale_id} <- resolve_locale_id(locale),
         {:ok, formats} <- interval_formats(locale_id, from) do
      difference = calendar_difference(from, to)
      formats_asked = {format_key, standard}

      if difference_visible?(format_key, difference) do
        locale_data = {locale, locale_id, cldr_calendar_for(from), formats}

        format_time_difference(
          output,
          {from, to},
          formats_asked,
          difference,
          locale_data,
          options
        )
      else
        whole_format = standard || format_key
        format_single(output, Localize.Time, from, Keyword.put(options, :format, whole_format))
      end
    end
  end

  # A standard format's times take the closest item to the fields of its
  # pattern, at the pattern's widths, as the time half of a date and time
  # does, or are both written with the format around the fallback pattern.
  defp format_time_difference(output, {from, to}, {skeleton, standard}, difference, data, options)
       when not is_nil(standard) do
    {locale, locale_id, calendar, formats} = data

    case split_time_range(skeleton, formats, difference, {locale_id, calendar}, options) do
      {:split, left, right} ->
        options_map = options |> Map.new() |> Map.put_new(:locale, locale)
        format_split(output, from, to, left, right, locale_id, options_map)

      {:error, _} = error ->
        error

      _no_item ->
        format_in_full(output, Localize.Time, {from, to}, standard, formats, options)
    end
  end

  defp format_time_difference(output, {from, to}, {format_key, nil}, difference, data, options) do
    {locale, locale_id, calendar, formats} = data
    item_key = time_interval_key(formats, format_key, locale, locale_id, calendar)
    key = difference_key(difference, item_key, Map.get(formats, item_key))

    case interval_split(formats, item_key, nil, key, options, format_key) do
      {:split, left, right} ->
        options_map = options |> Map.new() |> Map.put_new(:locale, locale)
        format_split(output, from, to, left, right, locale_id, options_map)

      {:fallback, skeleton} ->
        format_in_full(output, Localize.Time, {from, to}, skeleton, formats, options)

      {:error, _} = error ->
        error
    end
  end

  # A time skeleton the interval formats have no item for, such as `jm`,
  # takes the closest item (TR35 §Interval Formats step 2) once its `j` is
  # resolved to a `-u-hc-` override's hour symbol or, without one, to the
  # locale's preferred hour cycle.
  defp time_interval_key(formats, format_key, locale, locale_id, calendar) do
    if Map.has_key?(formats, format_key) do
      format_key
    else
      requested = Localize.Time.hour_cycle_skeleton(format_key, locale)

      case Localize.DateTime.Format.Match.best_interval_match(requested, locale_id, calendar) do
        {:ok, matched_key} -> matched_key
        _no_match -> format_key
      end
    end
  end

  # Formats a time interval whose endpoints can't (or shouldn't) be
  # routed through CLDR's skeleton-keyed interval-format table.
  # Handles two cases:
  #
  # * `time_format` is a binary CLDR pattern (e.g. `"HH:mm"`) that the
  #   caller supplied via `:format` or `:time_format`.
  # * `time_format` is a style atom (`:medium`, `:long`, `:full`) for
  #   which CLDR ships no interval-format data — the caller is given
  #   per-style differentiation by formatting each endpoint via
  #   `Localize.Time.to_string/2` instead.
  #
  # Both endpoints are then substituted into the locale's
  # `interval_format_fallback` template — the same wrapper used by
  # datetime intervals when the endpoints span more than one day.
  # Mirrors ex_cldr's `Cldr.Time.Interval.to_string/3` behaviour for
  # binary `:format`.
  defp format_time_interval_literal(from, to, time_format, locale, options, output) do
    with {:ok, locale_id} <- resolve_locale_id(locale),
         {:ok, formats} <- interval_formats(locale_id, from) do
      if difference_visible?(time_format, calendar_difference(from, to)) do
        format_in_full(output, Localize.Time, {from, to}, time_format, formats, options)
      else
        format_single(output, Localize.Time, from, Keyword.put(options, :format, time_format))
      end
    end
  end

  # ── Datetime interval ───────────────────────────────────────
  #
  # TR35 §Interval Formats step 3, for a format combining date and time
  # fields. A day, month or year difference formats both datetimes in full
  # around the fallback pattern. A time difference formats the date once and
  # joins it, through the locale's date-time pattern, to the time interval
  # CLDR ships for the time fields: "7/6/24, 10:00 – 10:30 AM". Where CLDR
  # ships none, as for a format with seconds, the date is still shown once,
  # with both times around the fallback pattern. A difference in a unit
  # neither half displays formats a single datetime.

  defp format_datetime_interval(from, to, options, output) do
    locale = Keyword.get(options, :locale, Localize.get_locale())
    {skeleton, calendar} = datetime_fields(from, options)

    with {:ok, locale_id} <- resolve_locale_id(locale),
         {:ok, halves} <- datetime_halves(options, skeleton, locale_id, calendar) do
      case halves do
        {:date_only, skeleton} ->
          format_date_interval(from, to, Keyword.put(options, :format, skeleton), output)

        halves ->
          format_datetime_halves(from, to, {locale, locale_id, calendar}, halves, options, output)
      end
    end
  end

  # The skeleton an interval of dates and times is written with, and the
  # CLDR calendar whose formats write it: the format given and the values'
  # own calendar, or, for a calendar of weeks' skeleton, its month as the
  # week and its day as the weekday in the formats of the calendar its
  # dates are read in, as a date and time alone is written
  # (`Localize.Date.own_fields/2`). The date written once beside two times
  # of a day was the calendar's period and day number, "M06 2, 2026 AD,
  # 10:30 – 12:30", which names no week.
  defp datetime_fields(from, options) do
    format = Keyword.get(options, :format, @default_format)

    if is_atom(format) and not is_nil(format) and format not in [:short, :medium, :long, :full],
      do: Localize.Date.own_fields(from, format),
      else: {format, cldr_calendar_for(from)}
  end

  defp format_datetime_halves(from, to, lookup, halves, options, output) do
    {locale, locale_id, calendar} = lookup
    {date_format, time_format, time_pattern} = halves
    datetime_options = datetime_sub_options(options) |> Map.to_list()
    time_options = time_sub_options(options, time_pattern) |> Map.to_list()

    # The two values in full are joined as their own calendar's fallback
    # pattern joins them, and the times of a day take the time interval of
    # the calendar whose formats write the skeleton.
    with {:ok, formats} <- interval_formats(locale_id, from),
         {:ok, time_formats} <- Localize.DateTime.Format.interval_formats(locale_id, calendar),
         {:ok, fallback} <- get_fallback_pattern(formats),
         {:ok, date_skeleton} <- format_skeleton(:date, date_format, {from, lookup}, options),
         {:ok, time_skeleton} <- format_skeleton(:time, time_format, {from, lookup}, options) do
      difference = calendar_difference(from, to)
      units = displayed_units(date_skeleton) ++ displayed_units(time_skeleton)
      in_full = {Localize.DateTime, to, datetime_options}
      order = Localize.DateTime.Format.interval_order(formats)

      # The two times about the fallback pattern, the date written once with
      # the time the locale writes first: `from`'s, or `to`'s where the
      # fallback pattern is "{1} – {0}", as ICU4C writes "Jun 16, 2026,
      # 14:30:00 – 10:00:00". A format without a date half writes the times
      # alone.
      {first, second} =
        date_once(order, date_format, {from, to}, {datetime_options, time_options})

      cond do
        not units_show?(units, difference) ->
          format_single(output, Localize.DateTime, from, datetime_options)

        difference in [:era, :year, :month, :day] ->
          format_fallback(output, {Localize.DateTime, from, datetime_options}, in_full, fallback)

        true ->
          time_formats
          |> time_range_split(time_skeleton, difference, locale, {locale_id, calendar}, options)
          |> format_time_range(output, {from, to}, {date_format, calendar}, options, {
            first,
            second,
            fallback
          })
      end
    end
  end

  defp date_once(_order, :none, {from, to}, {_datetime_options, time_options}),
    do: {{Localize.Time, from, time_options}, {Localize.Time, to, time_options}}

  defp date_once(:latest_first, _date_format, {from, to}, {datetime_options, time_options}),
    do: {{Localize.Time, from, time_options}, {Localize.DateTime, to, datetime_options}}

  defp date_once(:earliest_first, _date_format, {from, to}, {datetime_options, time_options}),
    do: {{Localize.DateTime, from, datetime_options}, {Localize.Time, to, time_options}}

  # The formats of a datetime interval's date and time halves: `:date_format`
  # and `:time_format` where given, else `:format` for both. A skeleton is
  # split into its date fields and its time fields, as TR35's interval
  # algorithm separates them (step 3.2): `:yMMMdHm` formats the date with the
  # pattern for `yMMMd` and the times with the `Hm` interval, and a skeleton
  # of time fields alone has no date half (`:none`). A skeleton of date fields
  # alone is a date interval's format. The third element is the time half as
  # a pattern, for the times formatted on their own, or `nil` to take the
  # time format given.
  defp datetime_halves(options, skeleton, locale_id, calendar) do
    format = Keyword.get(options, :format, @default_format)
    given = {Keyword.get(options, :date_format), Keyword.get(options, :time_format)}

    with {:ok, halves} <- split_format(format, skeleton, locale_id, calendar, options) do
      {:ok, with_given_halves(halves, given, format)}
    end
  end

  # `:date_format` and `:time_format` take the place of the halves of
  # `:format`; with either given, a skeleton of date fields alone is the
  # other half's format too.
  defp with_given_halves({:date_only, _skeleton} = date_only, {nil, nil}, _format), do: date_only

  defp with_given_halves({:date_only, _skeleton}, {date_format, time_format}, format),
    do: {date_format || format, time_format || format, nil}

  defp with_given_halves(
         {date_half, _time_half, _time_pattern},
         {date_format, time_format},
         _format
       )
       when not is_nil(time_format),
       do: {date_format || date_half, time_format, nil}

  defp with_given_halves({date_half, time_half, time_pattern}, {date_format, nil}, _format),
    do: {date_format || date_half, time_half, time_pattern}

  # `skeleton` is the skeleton the fields of `format` are written with,
  # which for a calendar of weeks names a week and a weekday
  # (`datetime_fields/2`).
  defp split_format(format, skeleton, locale_id, calendar, options)
       when is_atom(format) and not is_nil(format) and
              format not in [:short, :medium, :long, :full] do
    alias Localize.DateTime.Format.Match

    case Match.separate_date_and_time(skeleton) do
      {date_part, time_part} ->
        with {:ok, date_pattern} <- half_pattern(date_part, format, locale_id, calendar, options),
             {:ok, time_pattern} <- half_pattern(time_part, format, locale_id, calendar, options) do
          {:ok, {date_pattern, {:skeleton, time_part}, time_pattern}}
        end

      nil ->
        cond do
          Match.only_fields?(format, :time) -> {:ok, {:none, format, nil}}
          Match.only_fields?(format, :date) -> {:ok, {:date_only, format}}
          true -> {:ok, {format, format, nil}}
        end
    end
  end

  defp split_format(format, _skeleton, _locale_id, _calendar, _options),
    do: {:ok, {format, format, nil}}

  # A half of a skeleton as a pattern, its widths the ones requested, as
  # `Localize.DateTime.to_string/2` resolves the halves of a skeleton.
  defp half_pattern(half, skeleton, locale_id, calendar, options) do
    case Localize.DateTime.Format.AppendItems.resolve_pattern(half, locale_id, calendar, options) do
      {:ok, pattern} ->
        {:ok,
         Localize.Time.apply_hour_cycle(
           pattern,
           Keyword.get(options, :locale, Localize.get_locale()),
           half
         )}

      {:error, _reason} = error ->
        error

      :error ->
        {:error,
         Localize.DateTimeUnresolvedFormatError.exception(format: skeleton, locale: locale_id)}
    end
  end

  # A time difference shows the date once, joined to the time interval CLDR
  # ships for the time fields, or where it ships none to both times around
  # the fallback pattern. A format without a date half shows the time
  # interval alone.
  defp format_time_range(
         {:split, left, right},
         output,
         {from, to},
         {:none, _calendar},
         options,
         _fallback
       ) do
    locale = Keyword.get(options, :locale, Localize.get_locale())
    options_map = options |> Map.new() |> Map.put_new(:locale, locale)

    with {:ok, locale_id} <- resolve_locale_id(locale) do
      format_split(output, from, to, left, right, locale_id, options_map)
    end
  end

  defp format_time_range(
         {:split, left, right},
         output,
         endpoints,
         date_format_and_calendar,
         options,
         _fallback
       ) do
    format_date_and_time_range(
      output,
      endpoints,
      {left, right},
      date_format_and_calendar,
      options
    )
  end

  defp format_time_range(_no_time_interval, output, _endpoints, _format, _options, fallback) do
    {first, second, pattern} = fallback
    format_fallback(output, first, second, pattern)
  end

  # The skeleton a date or time format displays: for a standard format the
  # skeleton of the pattern it writes a single value with, and else the
  # skeleton or pattern given. A format of any other shape is `nil`, taken
  # to display every unit.
  defp format_skeleton(:date, format, {_from, {_locale, locale_id, calendar}}, options)
       when format in [:short, :medium, :long, :full],
       do: standard_date_skeleton(format, {locale_id, calendar}, options)

  defp format_skeleton(:time, format, {from, lookup}, options)
       when format in [:short, :medium, :long, :full],
       do: standard_time_skeleton(from, format, lookup, options)

  defp format_skeleton(_type, format, _value, _options)
       when is_atom(format) or is_binary(format),
       do: {:ok, format}

  defp format_skeleton(:time, {:skeleton, _time_half} = format, _value, _options),
    do: {:ok, format}

  defp format_skeleton(_type, _format, _value, _options), do: {:ok, nil}

  # The skeleton of the pattern a standard time format writes `time` with,
  # as `Localize.Time.to_string/2` resolves it: with a `-u-hc-` hour cycle
  # in place, and without its zone for a value that has none. CLDR's own
  # skeleton for the format names another hour cycle than the pattern in
  # some locales (`cop`'s "h:mm a" beside `HHmm`), so a time range that
  # asked for it was written in another clock than the time alone. A time's
  # fields are numbers, a day period and a zone, so the pattern's own fields
  # are always its skeleton.
  #
  # A time without one of its fields has no standard pattern, and is written
  # alone in the format of the fields it holds; its interval asks for CLDR's
  # skeleton, which names every unit, and falls back to each value in full.
  defp standard_time_skeleton(time, format, {locale, locale_id, calendar}, options) do
    case Localize.Time.resolve_pattern(time, format, locale, options) do
      {:ok, pattern} ->
        fields = Localize.DateTime.Format.Match.pattern_skeleton(pattern)
        {:ok, skeleton_atom(fields)}

      {:error, _no_standard_pattern} ->
        with {:ok, skeletons} <- Localize.DateTime.Format.time_formats(locale_id, calendar) do
          {:ok, Map.get(skeletons, format)}
        end
    end
  end

  # The interval CLDR ships for the time fields of a datetime format, split in
  # two. A 12-hour hour implies its day period, so `a` is dropped before
  # matching; left in, `ahmm` would match the flexible-period `Bhm` item.
  defp time_range_split(formats, time_skeleton, difference, locale, lookup, options)
       when is_atom(time_skeleton) and not is_nil(time_skeleton) do
    time_skeleton
    |> Localize.Time.hour_cycle_skeleton(locale)
    |> split_time_range(formats, difference, lookup, options)
  end

  # The time half of a skeleton split in two.
  defp time_range_split(formats, {:skeleton, time_half}, difference, locale, lookup, options) do
    time_half
    |> Localize.Time.hour_cycle_skeleton_half(locale)
    |> split_time_range(formats, difference, lookup, options)
  end

  defp time_range_split(_formats, _skeleton, _difference, _locale, _locale_id, _options),
    do: :none

  defp split_time_range(time_skeleton, formats, difference, lookup, options) do
    {locale_id, calendar} = lookup

    requested =
      time_skeleton
      |> Kernel.to_string()
      |> String.replace("a", "")

    with {:ok, matched_key} <-
           Localize.DateTime.Format.Match.best_interval_match(requested, locale_id, calendar) do
      key = difference_key(difference, matched_key, Map.get(formats, matched_key))
      interval_split(formats, matched_key, requested, key, options, :none)
    end
  end

  # TR35 step 3.2: the date formatted once, joined to the time range through
  # the locale's date-time pattern for the date format and `:style`, by
  # default the standard one, as TR35 says an interval takes.
  defp format_date_and_time_range(
         output,
         {from, to},
         {left, right},
         {date_format, calendar},
         options
       ) do
    locale = Keyword.get(options, :locale, Localize.get_locale())
    style = Keyword.get(options, :style, @interval_style)
    options_map = options |> Map.new() |> Map.put_new(:locale, locale)

    date_options =
      options
      |> Keyword.take([:locale, :prefer])
      |> Keyword.put(:format, date_format)

    with {:ok, locale_id} <- resolve_locale_id(locale),
         {:ok, wrapper} <-
           Localize.DateTime.date_time_wrapper(date_format, locale_id, style, calendar),
         {:ok, tokens, _end_line} <- Localize.DateTime.Format.Compiler.tokenize(wrapper),
         {:ok, date_value} <- date_half(output, from, date_options),
         {:ok, time_value} <- format_split(output, from, to, left, right, locale_id, options_map) do
      pieces =
        Enum.map(tokens, fn
          {:date, _line, _count} -> date_value
          {:time, _line, _count} -> time_value
          {:literal, _line, text} -> literal_piece(output, text)
        end)

      {:ok, join_pieces(output, pieces)}
    end
  end

  defp date_half(:string, from, options), do: Localize.Date.to_string(from, options)

  defp date_half(:parts, from, options) do
    with {:ok, parts} <- Localize.Date.to_parts(from, options) do
      {:ok, tag_source(parts, :shared)}
    end
  end

  defp literal_piece(:string, text), do: text
  defp literal_piece(:parts, text), do: [%{type: :literal, value: text, source: :shared}]

  defp join_pieces(:string, pieces), do: IO.iodata_to_binary(pieces)
  defp join_pieces(:parts, pieces), do: Enum.concat(pieces)

  # Derive the datetime-format options from the interval options,
  # applying `:date_format` and `:time_format` overrides if present. The
  # `:style` of date-time pattern goes along, the standard one by default,
  # so a datetime formatted whole is joined as a date joined to a time range
  # is.
  defp datetime_sub_options(options) do
    base =
      options
      |> Keyword.take([:locale, :prefer, :style])
      |> Map.new()
      |> Map.put_new(:style, @interval_style)

    format = Keyword.get(options, :format, @default_format)
    base = Map.put(base, :format, format)

    base =
      case Keyword.get(options, :date_format) do
        nil -> base
        date_format -> Map.put(base, :date_format, date_format)
      end

    case Keyword.get(options, :time_format) do
      nil -> base
      time_format -> Map.put(base, :time_format, time_format)
    end
  end

  # Time-only options: use `:time_format` as the format if given, then the
  # time half of a skeleton as a pattern, and otherwise the main `:format`.
  defp time_sub_options(options, time_pattern) do
    base =
      options
      |> Keyword.take([:locale, :prefer])
      |> Map.new()

    format =
      Keyword.get(options, :time_format) || time_pattern ||
        Keyword.get(options, :format, @default_format)

    Map.put(base, :format, format)
  end

  # ── The difference an interval displays ────────────────────

  # Units from largest to smallest. AM/PM sits above the hour: two times on
  # either side of noon differ in it first. The era sits above the year, as
  # ICU's `UCAL_ERA` does: it changes with the year in most calendars but
  # mid-year in the Japanese one, whose years count from each era.
  @unit_order [:era, :year, :month, :day, :am_pm, :hour, :minute, :second]

  # The pattern symbols that display each unit. A 12-hour hour displays the
  # day period too. A week is smaller than a year and is held by no field of
  # its own, so it ranks with the day, the smallest unit of a date.
  @unit_symbols [
    era: ~w(G),
    year: ~w(y Y u U r),
    month: ~w(M L Q q),
    day: ~w(d D F g E e c w W),
    am_pm: ~w(a b B h K),
    hour: ~w(h H K k j J C),
    minute: ~w(m),
    second: ~w(s S A)
  ]

  # Each date field a pattern writes, at the width that tells its every
  # value apart: a number for a month, a quarter or a weekday, whose narrow
  # names are shared ("J" is January, June and July), and an era's full
  # name. A year's place in the sixty-year cycle, which `y` and `U` write in
  # a calendar of cyclic years, is shared by years sixty apart, so a year
  # is compared by its number through every cycle as well, `u`.
  @comparison_fields %{
    "G" => "GGGG",
    "y" => ~w(y u),
    "Y" => "Y",
    "u" => "u",
    "U" => ~w(U u),
    "r" => "r",
    "Q" => "Q",
    "q" => "Q",
    "M" => "M",
    "L" => "M",
    "w" => "w",
    "W" => "W",
    "d" => "d",
    "D" => "D",
    "F" => "F",
    "g" => "g",
    "E" => "e",
    "e" => "e",
    "c" => "e"
  }

  defp calendar_difference(from, to) do
    Enum.find(@unit_order, &differs?(from, to, &1))
  end

  defp differs?(%{hour: from_hour}, %{hour: to_hour}, :am_pm)
       when is_integer(from_hour) and is_integer(to_hour) do
    from_hour < 12 != to_hour < 12
  end

  defp differs?(_from, _to, :am_pm), do: false

  # Values whose era cannot be settled, such as times and a Japanese year
  # holding two eras, are compared by their other units.
  defp differs?(from, to, :era) do
    with {:ok, {_from_year, from_era}} <- Localize.Calendar.year_of_era(from),
         {:ok, {_to_year, to_era}} <- Localize.Calendar.year_of_era(to) do
      from_era != to_era
    else
      _unsettled -> false
    end
  end

  defp differs?(from, to, unit), do: Map.get(from, unit) != Map.get(to, unit)

  # Whether two dates differ as `format` writes them. TR35's step 4 formats
  # one date where "there is no difference among any of the fields in the
  # pattern", so the fields are compared as the formatter writes them: a
  # week (`w`, `W`), a quarter (`Q`) and a calendar of weeks' period (`M`)
  # by their own values, not by the month and day fields that hold them.
  # Two dates alike in every field written still show as two where they
  # differ in a unit larger than any written, as a month and day a year
  # apart do, which the pattern widened with a year then tells apart. A
  # standard format writes every unit of a date, and a format whose fields
  # cannot be compared is judged by its units.
  defp date_difference_visible?(_format, nil, _dates, _locale_id, _options), do: false

  defp date_difference_visible?(format, difference, _dates, _locale_id, _options)
       when is_nil(format) or format in [:short, :medium, :long, :full],
       do: difference_visible?(format, difference)

  defp date_difference_visible?(format, difference, {from, to}, locale_id, options) do
    with {:ok, pattern} <- Localize.Date.resolve_pattern(from, format, locale_id, options),
         {:ok, differ?} <- written_fields_differ?(pattern, {from, to}, locale_id, options) do
      differ? or larger_than_written?(pattern, difference)
    else
      _incomparable -> difference_visible?(format, difference)
    end
  end

  defp written_fields_differ?(pattern, {from, to}, locale_id, options) do
    alias Localize.DateTime.Formatter

    comparison = comparison_pattern(pattern)
    options_map = Map.new(options)

    with true <- comparison != "",
         {:ok, from_fields} <- Formatter.format(from, comparison, locale_id, options_map),
         {:ok, to_fields} <- Formatter.format(to, comparison, locale_id, options_map) do
      {:ok, from_fields != to_fields}
    else
      _incomparable -> :error
    end
  end

  defp comparison_pattern(pattern) do
    pattern
    |> format_letters()
    |> Enum.flat_map(&List.wrap(Map.get(@comparison_fields, &1)))
    |> Enum.uniq()
    |> Enum.join("'|'")
  end

  defp larger_than_written?(pattern, difference) do
    case displayed_units(pattern) do
      [] -> false
      units -> unit_rank(difference) < units |> Enum.map(&unit_rank/1) |> Enum.min()
    end
  end

  # A difference shows only when the format displays its unit or a smaller
  # one; otherwise the two values are indistinguishable (TR35 step 4).
  defp difference_visible?(format, difference),
    do: units_show?(displayed_units(format), difference)

  defp units_show?(_units, nil), do: false

  defp units_show?(units, difference) do
    difference_rank = unit_rank(difference)
    Enum.any?(units, &(unit_rank(&1) >= difference_rank))
  end

  # A format without a date half displays none of the date's units.
  defp displayed_units(:none), do: []

  defp displayed_units({:skeleton, half}), do: displayed_units(half)

  defp displayed_units(format) when is_nil(format) or format in [:short, :medium, :long, :full],
    do: @unit_order

  defp displayed_units(format) do
    letters = format_letters(format)
    for {unit, symbols} <- @unit_symbols, Enum.any?(symbols, &(&1 in letters)), do: unit
  end

  # The characters of a skeleton or a pattern outside its quoted text.
  defp format_letters(format) do
    format
    |> Kernel.to_string()
    |> then(&Regex.replace(~r/'[^']*'/, &1, ""))
    |> String.graphemes()
  end

  defp unit_rank(unit), do: Enum.find_index(@unit_order, &(&1 == unit))

  # The greatestDifference id CLDR keys each difference by. Hour entries use
  # the skeleton's own hour symbol. An AM/PM difference takes the `a` entry,
  # or the `B` entry of a flexible-day-period item, and otherwise the hour
  # entry, as ICU does for 24-hour items that ship no `a`.
  defp difference_key(:era, _skeleton, _item), do: :G
  defp difference_key(:year, _skeleton, _item), do: :y
  defp difference_key(:month, _skeleton, _item), do: :M
  defp difference_key(:day, _skeleton, _item), do: :d
  defp difference_key(:minute, _skeleton, _item), do: :m
  defp difference_key(:second, _skeleton, _item), do: :s
  defp difference_key(:hour, skeleton, _item), do: hour_key(skeleton)

  defp difference_key(:am_pm, skeleton, item) do
    cond do
      is_map(item) and Map.has_key?(item, :a) -> :a
      is_map(item) and Map.has_key?(item, :B) -> :B
      true -> hour_key(skeleton)
    end
  end

  defp hour_key(skeleton) do
    if skeleton |> Kernel.to_string() |> String.contains?(["H", "k"]), do: :H, else: :h
  end

  # The item's pattern for `key`, adjusted to the requested widths and split
  # in two, or `{:fallback, skeleton}` when the table has no such pattern.
  defp interval_split(formats, format_key, requested_skeleton, key, options, fallback_skeleton) do
    with pattern when not is_nil(pattern) <- item_pattern(Map.get(formats, format_key), key),
         resolved when is_binary(resolved) <-
           Localize.DateTime.Format.resolve_variant(pattern, options),
         {:ok, adjusted} <- adjust_interval_widths(resolved, requested_skeleton, format_key),
         {:ok, [left, right]} <- split_interval(adjusted) do
      {:split, left, right}
    else
      {:error, _} = error -> error
      _no_pattern -> {:fallback, fallback_skeleton}
    end
  end

  defp item_pattern(%{} = item, key), do: Map.get(item, key)
  defp item_pattern(pattern, _key) when is_binary(pattern), do: pattern
  defp item_pattern(_item, _key), do: nil

  # Time-only intervals use skeleton keys that contain time fields.
  # A binary input is a literal CLDR pattern; flagged with the
  # `{:literal, pattern}` tag so the caller dispatches it through the
  # `interval_format_fallback` path instead of attempting an
  # interval-format-key lookup.
  defp resolve_time_style(format, _time, _locale, _options) when is_binary(format) do
    {:ok, {:literal, format}}
  end

  # The standard formats map as follows:
  #
  # * `:short` → the skeleton of the pattern `Localize.Time.to_string/2`
  #   writes the time with, tagged `{:standard, skeleton}`, so the times of
  #   an interval are in the clock and at the widths of the time alone
  #   (user, 2026-10-04: "the pattern"): `ady-JO`, whose region prefers a
  #   12-hour clock and whose short time is "HH:mm", writes "10:05–11:30".
  #   A `-u-hc-` hour cycle is in the pattern already. The skeleton is
  #   dispatched via CLDR's interval-format table, which ships per-locale
  #   collapsing — e.g. en's "12:00 – 12:30 PM" sharing the AM/PM marker
  #   between endpoints.
  #
  # * `:medium`, `:long`, `:full` → tagged `{:fallback_style, style}`.
  #   CLDR does NOT ship `:hms` (or zone-bearing) interval patterns,
  #   so we can't dispatch these via the interval-format table. The
  #   downstream branch instead formats each endpoint using
  #   `Localize.Time.to_string/2` with the requested style and joins
  #   the two strings via the locale's `interval_format_fallback`.
  #   This gives the user the per-style differentiation they expect
  #   (`:short` → no seconds, `:medium`+ → with seconds), matching
  #   the precedent set by `Localize.Time.to_string/2`.
  defp resolve_time_style(:short, time, locale, options) do
    case Localize.Time.resolve_pattern(time, :short, locale, options) do
      {:ok, pattern} ->
        fields = Localize.DateTime.Format.Match.pattern_skeleton(pattern)
        {:ok, {:standard, skeleton_atom(fields)}}

      {:error, _no_standard_pattern} ->
        preferred_hour_skeleton(locale)
    end
  end

  defp resolve_time_style(:medium, _time, _locale, _options),
    do: {:ok, {:fallback_style, :medium}}

  defp resolve_time_style(:long, _time, _locale, _options), do: {:ok, {:fallback_style, :long}}
  defp resolve_time_style(:full, _time, _locale, _options), do: {:ok, {:fallback_style, :full}}

  defp resolve_time_style(format, _time, _locale, _options) when is_atom(format),
    do: {:ok, format}

  # A time without one of its fields has no standard pattern, and is written
  # alone in the format of the fields it holds, so its interval takes the
  # hour and minute of the locale's hour cycle: a `-u-hc-` override's, or
  # the cycle its region prefers.
  defp preferred_hour_skeleton(locale) do
    case Localize.Time.hour_format_from_locale(locale) do
      {:ok, cycle} when cycle in [:h11, :h12] -> {:ok, :hm}
      {:ok, cycle} when cycle in [:h23, :h24] -> {:ok, :Hm}
      {:error, _} = error -> error
    end
  end

  # Open-ended intervals. One endpoint is `nil`; format the known
  # endpoint using its normal single-value formatter, then substitute
  # into the locale's `:interval_format_fallback` pattern (which is
  # of the form `[0, " – ", 1]`). For `:open_start`, the known value
  # goes into slot 1 and we trim the leading separator. For
  # `:open_end`, it goes into slot 0 and we trim the trailing separator.
  defp format_open_interval(value, side, options) do
    locale = Keyword.get(options, :locale, Localize.get_locale())

    with :ok <- Localize.Calendar.validate_value(value),
         {:ok, locale_id} <- resolve_locale_id(locale),
         {:ok, formats} <- interval_formats(locale_id, value),
         {:ok, pattern} <- get_fallback_pattern(formats),
         {:ok, formatted} <- format_single_value(value, options) do
      {a, b} =
        case side do
          :open_start -> {"", formatted}
          :open_end -> {formatted, ""}
        end

      # The pattern leaves a space beside the value that is not there, before
      # its separator or after it as it orders its values.
      result =
        [a, b]
        |> Localize.Substitution.substitute(pattern)
        |> IO.iodata_to_binary()
        |> String.trim()

      {:ok, result}
    end
  end

  # ── Output-mode terminals (string | parts) ──────────────────

  # A split interval pattern: the left half formats the value the locale
  # writes first, `from` in every locale but one, and the right half the
  # other, concatenated directly.
  defp format_split(:string, from, to, left, right, locale_id, options_map) do
    {left, right} = hour_cycle_split(left, right, options_map)
    {first, second} = in_written_order({from, to}, from, locale_id)

    with {:ok, left_str} <-
           Localize.DateTime.Formatter.format(first, left, locale_id, options_map),
         {:ok, right_str} <-
           Localize.DateTime.Formatter.format(second, right, locale_id, options_map) do
      {:ok, left_str <> right_str}
    end
  end

  defp format_split(:parts, from, to, left, right, locale_id, options_map) do
    {left, right} = hour_cycle_split(left, right, options_map)
    {first, second} = in_written_order({from, to}, from, locale_id)
    {first_source, second_source} = in_written_order({:start_range, :end_range}, from, locale_id)

    with {:ok, left_parts} <-
           Localize.DateTime.Formatter.format_to_parts(first, left, locale_id, options_map),
         {:ok, right_parts} <-
           Localize.DateTime.Formatter.format_to_parts(second, right, locale_id, options_map) do
      {:ok,
       join_split_parts(
         tag_source(left_parts, first_source),
         tag_source(right_parts, second_source)
       )}
    end
  end

  # A pair in the order the locale's interval patterns write their two
  # values in. TR35: "The fallback pattern determines the default order of
  # the interval pattern", and with "{1} - {0}" "the first part of the
  # interval patterns in current locale are formatted with the end
  # datetime". `kek`'s Gregorian calendar has the one such pattern in CLDR
  # 49, so its `yMd` item "d/M/y – d/M/y" writes 16 June 2026 to 20 August
  # 2027 as "20/8/2027 – 16/6/2026", as its fallback pattern joins two
  # dates and as ICU4C writes an interval for such a locale.
  defp in_written_order({earlier, later}, value, locale_id) do
    with {:ok, formats} <- interval_formats(locale_id, value),
         :latest_first <- Localize.DateTime.Format.interval_order(formats) do
      {later, earlier}
    else
      _earliest_first -> {earlier, later}
    end
  end

  # An interval's halves take a `-u-hc-` hour cycle's hour symbol, as a
  # single time does.
  defp hour_cycle_split(left, right, options_map) do
    locale = Map.get(options_map, :locale)
    {Localize.Time.apply_hour_cycle(left, locale), Localize.Time.apply_hour_cycle(right, locale)}
  end

  # The split pattern's separator (" – ") sits at the boundary of the
  # two halves, each tagged with the end of the range it writes, as
  # literal text; retag those bridging literals as `:shared` per ECMA-402.
  defp join_split_parts(left, right) do
    {left_body, left_bridge} = split_trailing_literals(left)
    {right_bridge, right_body} = split_leading_literals(right)

    bridge = Enum.map(left_bridge ++ right_bridge, &Map.put(&1, :source, :shared))
    left_body ++ bridge ++ right_body
  end

  defp split_trailing_literals(parts) do
    {reversed_bridge, reversed_body} =
      parts
      |> Enum.reverse()
      |> Enum.split_while(&(&1.type == :literal))

    {Enum.reverse(reversed_body), Enum.reverse(reversed_bridge)}
  end

  defp split_leading_literals(parts) do
    Enum.split_while(parts, &(&1.type == :literal))
  end

  # Each endpoint formatted by its own {module, value, options} spec,
  # substituted into the locale's interval fallback pattern.
  defp format_fallback(
         :string,
         {left_module, from, from_options},
         {right_module, to, to_options},
         fallback
       ) do
    with {:ok, left_str} <- left_module.to_string(from, from_options),
         {:ok, right_str} <- right_module.to_string(to, to_options) do
      result =
        [left_str, right_str]
        |> Localize.Substitution.substitute(fallback)
        |> IO.iodata_to_binary()

      {:ok, result}
    end
  end

  defp format_fallback(
         :parts,
         {left_module, from, from_options},
         {right_module, to, to_options},
         fallback
       ) do
    with {:ok, left_parts} <- left_module.to_parts(from, from_options),
         {:ok, right_parts} <- right_module.to_parts(to, to_options) do
      parts =
        [tag_source(left_parts, :start_range), tag_source(right_parts, :end_range)]
        |> Localize.Substitution.substitute_parts(fallback)
        |> Enum.map(&Map.put_new(&1, :source, :shared))

      {:ok, parts}
    end
  end

  # The equal-endpoints fallback: a single formatted value, tagged
  # `:shared` throughout in parts mode.
  defp format_single(:string, module, value, options), do: module.to_string(value, options)

  defp format_single(:parts, module, value, options) do
    with {:ok, parts} <- module.to_parts(value, options) do
      {:ok, tag_source(parts, :shared)}
    end
  end

  defp tag_source(parts, source) do
    Enum.map(parts, &Map.put(&1, :source, source))
  end

  defp get_fallback_pattern(formats) do
    case Map.get(formats, :interval_format_fallback) do
      nil ->
        {:error, Localize.DateTimeIntervalFormatError.exception(reason: :no_fallback)}

      pattern ->
        {:ok, pattern}
    end
  end

  # Dispatch a single value to the appropriate formatter based on its shape.
  # Pure time values (an hour and no date field) go to Time; pure date values
  # (a year, a month or a day, and no hour) go to Date; everything else
  # (including NaiveDateTime, DateTime, and generic maps with both date and
  # time fields) goes to DateTime.
  defp format_single_value(%Time{} = value, options), do: Localize.Time.to_string(value, options)
  defp format_single_value(%Date{} = value, options), do: Localize.Date.to_string(value, options)

  defp format_single_value(%DateTime{} = value, options),
    do: Localize.DateTime.to_string(value, Keyword.put_new(options, :style, @interval_style))

  defp format_single_value(%NaiveDateTime{} = value, options),
    do: Localize.DateTime.to_string(value, Keyword.put_new(options, :style, @interval_style))

  defp format_single_value(value, options) when is_map(value) do
    cond do
      datetime_value?(value) ->
        Localize.DateTime.to_string(value, Keyword.put_new(options, :style, @interval_style))

      date_value?(value) ->
        Localize.Date.to_string(value, options)

      time_value?(value) ->
        Localize.Time.to_string(value, options)

      true ->
        {:error, Localize.DateTimeInvalidInputError.exception(type: :datetime)}
    end
  end

  defp format_single_value(_value, _options),
    do: {:error, Localize.DateTimeInvalidInputError.exception(type: :datetime)}

  @doc """
  Same as `to_string/3` but raises on error.

  ### Arguments

  * `from` is a `t:Date.t/0`.

  * `to` is a `t:Date.t/0`.

  * `options` is a keyword list of options.

  ### Options

  See `to_string/3` for the supported options.

  ### Returns

  * The formatted interval as a string.

  * Raises an exception if the interval cannot be formatted.

  ### Examples

      iex> Localize.Interval.to_string!(~D[2022-04-22], ~D[2022-04-25], locale: :en)
      "Apr 22\u2009–\u200925, 2022"

      iex> Localize.Interval.to_string!(~D[2022-01-15], ~D[2022-03-20], locale: :en)
      "Jan 15\u2009–\u2009Mar 20, 2022"

  """
  @spec to_string!(map(), map(), Keyword.t()) :: String.t()
  def to_string!(from, to, options \\ []) do
    case to_string(from, to, options) do
      {:ok, string} -> string
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Returns the greatest calendar field difference between
  two dates or datetimes.

  ### Arguments

  * `from` is a date or datetime map.

  * `to` is a date or datetime map.

  ### Returns

  * `{:ok, field}` where field is `:y`, `:M`, `:d`, `:H`, or `:m`.

  * `{:error, %Localize.NoPracticalDifferenceError{}}` if the values
    are equal at every field considered.

  ### Examples

      iex> Localize.Interval.greatest_difference(~D[2022-04-22], ~D[2022-04-27])
      {:ok, :d}

      iex> Localize.Interval.greatest_difference(~D[2021-12-31], ~D[2022-01-01])
      {:ok, :y}

  """
  @spec greatest_difference(map(), map()) ::
          {:ok, :y | :M | :d | :H | :m} | {:error, Exception.t()}
  def greatest_difference(from, to) when is_map(from) and is_map(to) do
    cond do
      Map.get(from, :year) != Map.get(to, :year) ->
        {:ok, :y}

      Map.get(from, :month) != Map.get(to, :month) ->
        {:ok, :M}

      Map.get(from, :day) != Map.get(to, :day) ->
        {:ok, :d}

      Map.get(from, :hour) != Map.get(to, :hour) ->
        {:ok, :H}

      Map.get(from, :minute) != Map.get(to, :minute) ->
        {:ok, :m}

      true ->
        {:error, Localize.NoPracticalDifferenceError.exception(from: from, to: to)}
    end
  end

  def greatest_difference(from, _to) when not is_map(from),
    do: {:error, Localize.Utils.Helpers.invalid_value(from, "a date, time or datetime")}

  def greatest_difference(_from, to),
    do: {:error, Localize.Utils.Helpers.invalid_value(to, "a date, time or datetime")}

  @doc """
  Returns the locale-independent skeletons for the `:fields` option of `to_string/3`.

  Only the non-default `:fields` selections (`:month`,
  `:month_and_day`, `:year_and_month`) appear here, because only
  those are locale-independent. The default `:date` selection is
  resolved per-locale, mirroring `Localize.Date.to_string/2`'s
  `:format` → skeleton mapping for that locale, so it has no fixed
  entry to list.

  ### Returns

  * A map keyed by field selection (`:month`, `:month_and_day`,
    `:year_and_month`), each value a map of `:format`
    (`:short`, `:medium`, `:long`, `:full`) to the CLDR
    skeleton atom used for that combination.

  ### Examples

      iex> Localize.Interval.known_fields()
      %{
        month: %{short: :M, full: :MMM, long: :MMM, medium: :MMM},
        month_and_day: %{short: :Md, full: :MMMEd, long: :MMMEd, medium: :MMMd},
        year_and_month: %{short: :yM, full: :yMMMM, long: :yMMMM, medium: :yMMM}
      }

  """
  @spec known_fields() :: %{
          month: %{short: :M, medium: :MMM, long: :MMM, full: :MMM},
          month_and_day: %{short: :Md, medium: :MMMd, long: :MMMEd, full: :MMMEd},
          year_and_month: %{short: :yM, medium: :yMMM, long: :yMMMM, full: :yMMMM}
        }
  def known_fields, do: @field_skeletons

  # ── Interval pattern resolution ────────────────────────────

  # A whole date at a standard format takes the skeleton of that format's
  # pattern (`standard_date_fields/3`). The other field selections
  # (`:month`, `:month_and_day`, `:year_and_month`) are locale-independent:
  # they describe a deliberate choice of fields unrelated to a single date's
  # standard formats.
  #
  # A skeleton names its fields itself, so it takes the path a standard
  # format's skeleton takes: CLDR's interval item for it, the closest item,
  # or both dates formatted with it around the fallback pattern. CLDR keys
  # interval formats by skeleton, so a format no standard format reaches can
  # be named: `yMMMEd` is "Mon, Jun 15 – Thu, Jun 18, 2026" in `en`.
  defp resolve_fields(:date, skeleton, locale_id, calendar)
       when is_atom(skeleton) and not is_nil(skeleton) do
    with {:ok, interval_formats} <-
           Localize.DateTime.Format.interval_formats(locale_id, calendar) do
      skeleton_or_fallback_style(skeleton, interval_formats, skeleton, {locale_id, calendar})
    end
  end

  # A pattern names no interval item, so both dates are formatted with it
  # around the fallback pattern, or one when they differ in no field it shows,
  # as a time interval's pattern is.
  defp resolve_fields(:date, pattern, _locale_id, _calendar) when is_binary(pattern),
    do: {:ok, {:fallback_style, pattern}}

  defp resolve_fields(fields, format, _locale_id, _calendar)
       when is_atom(fields) and is_atom(format) do
    case get_in(@field_skeletons, [fields, format]) do
      nil ->
        {:error,
         Localize.DateTimeIntervalFormatError.exception(
           reason: :unknown_fields,
           fields: fields,
           format: format
         )}

      format_key ->
        {:ok, format_key}
    end
  end

  defp resolve_fields(fields, format, _locale_id, _calendar) do
    {:error,
     Localize.DateTimeIntervalFormatError.exception(
       reason: :unknown_fields,
       fields: fields,
       format: format
     )}
  end

  # Use the locale's skeleton when CLDR ships an interval format for it.
  # Otherwise take TR35 §Interval Formats step 2 — the closest entry in the
  # table, which may differ only in field width — before signalling the
  # endpoint-formatting fallback of the final step. Only a genuine miss
  # glues two whole dates together: `de` renders "03.–05.05.2026" from
  # `yMd`, not "03.05.2026 – 05.05.2026", because its `yMMdd` style
  # skeleton is a width adjustment away from a pattern CLDR ships.
  defp skeleton_or_fallback_style(skeleton, interval_formats, format, {locale_id, calendar}) do
    if Map.has_key?(interval_formats, skeleton) do
      {:ok, skeleton}
    else
      case Localize.DateTime.Format.Match.best_interval_match(skeleton, locale_id, calendar) do
        {:ok, matched_skeleton} -> {:ok, {matched_skeleton, skeleton}}
        :error -> {:ok, {:fallback_style, format}}
      end
    end
  end

  # TR35 step 2 matches on fields, not widths, so the pattern that comes back
  # spells its fields at the *matched* skeleton's widths. Adjust them to the
  # widths actually requested — a `yMMMd` pattern answering a requested
  # `yMMMMd` must still render "June", not "Jun" — subject to the same rule
  # that governs `availableFormats`: where the matched skeleton already
  # states the requested width, the locale's own choice stands.
  defp adjust_interval_widths(pattern, nil, _format_key), do: {:ok, pattern}

  defp adjust_interval_widths(pattern, requested_skeleton, format_key) do
    {:ok, skeleton_tokens} =
      Localize.DateTime.Format.Match.tokenize_skeleton(requested_skeleton)

    Localize.DateTime.Format.Match.adjust_field_lengths(pattern, skeleton_tokens, format_key)
  end

  # ── Interval splitting ─────────────────────────────────────

  @doc """
  Splits an interval format string into `[left, right]` halves
  at the point where a format character repeats.

  ### Arguments

  * `interval` is an interval format pattern string.

  ### Returns

  * `{:ok, [left, right]}` where `left` and `right` are the two
    halves of the interval pattern.

  * `{:error, exception}` if the pattern is malformed, has no
    repeating field, or is not a string.

  ### Examples

      iex> Localize.Interval.split_interval("MMM d – d")
      {:ok, ["MMM d – ", "d"]}

  """
  @spec split_interval(term()) :: {:ok, [String.t()]} | {:error, Exception.t()}
  # A binary that is not UTF-8 is no pattern, and the split walks the pattern
  # by code point, so it is refused before the walk.
  def split_interval(interval) when is_binary(interval) do
    if String.valid?(interval) do
      case do_split_interval(interval, [], "") do
        [_, _] = result ->
          {:ok, result}

        {:error, _} = error ->
          error
      end
    else
      invalid_interval_format(interval)
    end
  end

  def split_interval(interval), do: invalid_interval_format(interval)

  defp invalid_interval_format(interval) do
    {:error,
     Localize.DateTimeIntervalFormatError.exception(
       reason: :invalid_format,
       detail: inspect(interval)
     )}
  end

  defp do_split_interval("", _acc, left) do
    {:error,
     Localize.DateTimeIntervalFormatError.exception(
       reason: :invalid_format,
       detail: left
     )}
  end

  # Quoted strings pass through
  defp do_split_interval(<<"'", rest::binary>>, acc, left) do
    case String.split(rest, "'", parts: 2) do
      [literal, rest] ->
        do_split_interval(rest, acc, left <> "'" <> literal <> "'")

      [_] ->
        {:error, Localize.DateTimeIntervalFormatError.exception(reason: :unterminated_quote)}
    end
  end

  # Non-format characters pass through
  defp do_split_interval(<<c::utf8, rest::binary>>, acc, left)
       when c not in ?a..?z and c not in ?A..?Z do
    do_split_interval(rest, acc, left <> List.to_string([c]))
  end

  # Format characters — check for repeats of 1-5
  defp do_split_interval(
         <<c, c, c, c, c, rest::binary>>,
         acc,
         left
       )
       when c in ?a..?z or c in ?A..?Z do
    ch = <<c>>
    repeated = String.duplicate(ch, 5)

    if already_seen?(ch, acc) do
      [left, repeated <> rest]
    else
      do_split_interval(rest, [ch | acc], left <> repeated)
    end
  end

  defp do_split_interval(<<c, c, c, c, rest::binary>>, acc, left)
       when c in ?a..?z or c in ?A..?Z do
    ch = <<c>>
    repeated = String.duplicate(ch, 4)

    if already_seen?(ch, acc) do
      [left, repeated <> rest]
    else
      do_split_interval(rest, [ch | acc], left <> repeated)
    end
  end

  defp do_split_interval(<<c, c, c, rest::binary>>, acc, left)
       when c in ?a..?z or c in ?A..?Z do
    ch = <<c>>
    repeated = String.duplicate(ch, 3)

    if already_seen?(ch, acc) do
      [left, repeated <> rest]
    else
      do_split_interval(rest, [ch | acc], left <> repeated)
    end
  end

  defp do_split_interval(<<c, c, rest::binary>>, acc, left)
       when c in ?a..?z or c in ?A..?Z do
    ch = <<c>>
    repeated = String.duplicate(ch, 2)

    if already_seen?(ch, acc) do
      [left, repeated <> rest]
    else
      do_split_interval(rest, [ch | acc], left <> repeated)
    end
  end

  defp do_split_interval(<<c, rest::binary>>, acc, left)
       when c in ?a..?z or c in ?A..?Z do
    ch = <<c>>

    if already_seen?(ch, acc) do
      [left, ch <> rest]
    else
      do_split_interval(rest, [ch | acc], left <> ch)
    end
  end

  # Equivalence classes for interval splitting
  defp already_seen?("Q", acc), do: "Q" in acc || "q" in acc
  defp already_seen?("q", acc), do: "Q" in acc || "q" in acc
  defp already_seen?("L", acc), do: "L" in acc || "M" in acc
  defp already_seen?("M", acc), do: "L" in acc || "M" in acc
  defp already_seen?("E", acc), do: "E" in acc || "e" in acc || "c" in acc
  defp already_seen?("e", acc), do: "E" in acc || "e" in acc || "c" in acc
  defp already_seen?("c", acc), do: "E" in acc || "e" in acc || "c" in acc
  defp already_seen?(c, acc), do: c in acc

  @doc """
  Parses a localized date interval.

  The inverse of `to_string/3`. Accepts either a single string, such as `"May 5 – 10, 2026"`, or a 2-tuple `{from_string, to_string}` for two-input UIs that already have the endpoints split.

  A single string is read with the locale's interval formats, in which the two dates share the fields written once, and otherwise cut where the locale's fallback pattern or a separator people write, a dash or "to", has a date on each side, each read as `Localize.Date.parse/2` reads it. The spaces about an interval format's dash may be left out or put in. Two dates written without a year are of the reference date's year, as a date alone is, and the later is of the year after where it would otherwise come before the earlier: "Dec 28 – Jan 3" ends in the January that follows. Two weeks written without a year are read the same way by their week-based years: "Sun (week: 53) – Mon (week: 1)" ends the day after it begins.

  The result is a `t:Date.Range.t/0` whose endpoints share the calendar named by the `:calendar` option, which defaults to `Calendar.ISO`.

  ### Arguments

  * `input` is either a binary or a `{from_binary, to_binary}` tuple.

  * `options` is a keyword list of options.

  ### Options

  Same as `Localize.Date.parse/2` — `:locale`, `:calendar`, `:format`,
  `:reference_date`, `:as`. As there, `:calendar` is a calendar module and
  the endpoints are returned in it, a calendar of weeks reading them as
  Gregorian dates. `:format` is the format each endpoint was written with:
  each is read with it either side of the locale's separator, and the
  locale's interval patterns, which share fields between the endpoints,
  are not tried. Plus:

  * `:allow_inverted` is a boolean. When `true`, an end-before-start
    interval is returned as-is, since `Date.range/3` builds a descending
    range. When `false`, the default, an inverted interval is rejected
    with a `t:Localize.DateRangeParseError.t/0`. Applies only when
    `as: :struct`, the default; `as: :map` skips the comparison because
    partial maps may not carry enough fields to compare.

  ### Returns

  * `{:ok, range}`, a `t:Date.Range.t/0`, when `as: :struct`, or

  * `{:ok, {from_map, to_map}}` when `as: :map`. Each endpoint is a field
    map; missing fields are inherited from the other endpoint per the
    CLDR interval convention, so `"May 5 – May 10, 2026"` yields two maps
    both carrying `:year`. A field given a value no date has is an error,
    never inherited, or

  * `{:error, exception}`, a `t:Localize.DateParseError.t/0` or
    `t:Localize.DateRangeParseError.t/0`, on failure, or a
    `t:Localize.InvalidValueError.t/0` if an endpoint is not a string or
    an option is malformed.

  ### Examples

      iex> {:ok, range} = Localize.Interval.parse({"2026-05-05", "2026-05-10"})
      iex> {range.first, range.last}
      {~D[2026-05-05], ~D[2026-05-10]}

      iex> Localize.Interval.parse("May 5 – May 10, 2026", locale: :en, as: :map)
      {:ok,
       {%{calendar: Calendar.ISO, year: 2026, month: 5, day: 5},
        %{calendar: Calendar.ISO, year: 2026, month: 5, day: 10}}}

      iex> {:ok, range} = Localize.Interval.parse("May 5, 2026 – May 10, 2026", locale: :en)
      iex> {range.first, range.last}
      {~D[2026-05-05], ~D[2026-05-10]}

      iex> Localize.Interval.parse("May 5–10, 2026", locale: :en)
      {:ok, Date.range(~D[2026-05-05], ~D[2026-05-10])}

      iex> Localize.Interval.parse("May 5 – 10", locale: :en, reference_date: ~D[2026-01-01])
      {:ok, Date.range(~D[2026-05-05], ~D[2026-05-10])}

  """
  @spec parse(String.t() | {String.t(), String.t()}, Keyword.t()) ::
          {:ok, Date.Range.t() | {map(), map()}} | {:error, Exception.t()}
  def parse(input, options \\ [])

  def parse({from_string, to_string}, options) do
    with :ok <- Localize.DateTime.ParseOptions.validate(from_string, options),
         :ok <- Localize.DateTime.ParseOptions.validate(to_string, options) do
      Localize.Date.Parser.parse_range_pair(from_string, to_string, options)
    end
  end

  def parse(input, options) do
    with :ok <- Localize.DateTime.ParseOptions.validate(input, options) do
      Localize.Date.Parser.parse_range(input, options)
    end
  end

  # ── Locale resolution ──────────────────────────────────────

  defp resolve_locale_id(locale), do: Localize.Locale.cldr_locale_id_from(locale)
end
