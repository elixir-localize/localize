defmodule Localize.Interval do
  @moduledoc """
  Formats date and time intervals as localized strings.

  Interval formats produce strings like "Jan 10 – 12, 2008" from
  two dates, rather than repeating "Jan 10, 2008 – Jan 12, 2008".
  The format is selected based on the greatest calendar field
  difference between the start and end values.

  """

  import Kernel, except: [to_string: 1]

  @date_styles %{
    date: %{long: :yMMMEd, medium: :yMMMd, short: :yMd},
    month: %{long: :MMM, medium: :MMM, short: :M},
    month_and_day: %{long: :MMMEd, medium: :MMMd, short: :Md},
    year_and_month: %{long: :yMMMM, medium: :yMMM, short: :yM}
  }

  @default_date_style :date
  @default_format :medium

  @doc """
  Formats a date interval as a localized string.

  ### Arguments

  * `from` is a `t:Date.t/0`.

  * `to` is a `t:Date.t/0`.

  * `options` is a keyword list of options.

  ### Options

  * `:locale` is a locale identifier. The default is `:en`.

  * `:format` is `:short`, `:medium`, or `:long`. The default
    is `:medium`.

  * `:style` is `:date`, `:month`, `:month_and_day`, or
    `:year_and_month`. The default is `:date`.

  ### Returns

  * `{:ok, formatted_string}` on success.

  * `{:error, exception}` on failure.

  ### Examples

      iex> {:ok, result} = Localize.Interval.to_string(~D[2022-04-22], ~D[2022-04-25], locale: :en)
      iex> String.contains?(result, "Apr")
      true

      iex> {:ok, result} = Localize.Interval.to_string(~D[2022-01-15], ~D[2022-03-20], locale: :en)
      iex> String.contains?(result, "Jan") and String.contains?(result, "Mar")
      true

  """
  @spec to_string(map() | nil, map() | nil, Keyword.t()) ::
          {:ok, String.t()} | {:error, Exception.t()}
  def to_string(from, to, options \\ [])

  def to_string(nil, nil, _options) do
    {:error, Localize.DateTimeInvalidInputError.exception(type: :datetime)}
  end

  def to_string(nil, to, options) when not is_nil(to) do
    format_open_interval(to, :open_start, options)
  end

  def to_string(from, nil, options) when not is_nil(from) do
    format_open_interval(from, :open_end, options)
  end

  def to_string(from, to, options) do
    cond do
      datetime_value?(from) and datetime_value?(to) ->
        format_datetime_interval(from, to, options)

      time_value?(from) and time_value?(to) ->
        format_time_interval(from, to, options)

      true ->
        format_date_interval(from, to, options)
    end
  end

  # ── Type detection ───────────────────────────────────────────
  #
  # A "datetime" value has both a date part (year/month/day) and a
  # time part (hour). Struct types Date/Time/NaiveDateTime/DateTime
  # are handled explicitly; generic maps fall back to key-presence.

  defp datetime_value?(%DateTime{}), do: true
  defp datetime_value?(%NaiveDateTime{}), do: true
  defp datetime_value?(%Date{}), do: false
  defp datetime_value?(%Time{}), do: false
  defp datetime_value?(%{year: _, hour: _}), do: true
  defp datetime_value?(_), do: false

  defp time_value?(%Time{}), do: true
  defp time_value?(%DateTime{}), do: false
  defp time_value?(%NaiveDateTime{}), do: false
  defp time_value?(%Date{}), do: false
  defp time_value?(%{hour: _} = map), do: not Map.has_key?(map, :year)
  defp time_value?(_), do: false

  # ── Date-only interval (the original path) ──────────────────

  defp format_date_interval(from, to, options) do
    locale = Keyword.get(options, :locale, Localize.get_locale())
    format = Keyword.get(options, :format, @default_format)
    style = Keyword.get(options, :style, @default_date_style)

    with {:ok, locale_id} <- resolve_locale_id(locale),
         {:ok, formats} <- Localize.DateTime.Format.interval_formats(locale_id),
         {:ok, greatest_diff} <- greatest_difference(from, to),
         {:ok, format_key} <- resolve_style(style, format),
         {:ok, interval_pattern} <- get_interval_pattern(formats, format_key, greatest_diff),
         {:ok, [left, right]} <- split_interval(interval_pattern) do
      options_map = Map.new(options)

      with {:ok, left_str} <-
             Localize.DateTime.Formatter.format(from, left, locale_id, options_map),
           {:ok, right_str} <-
             Localize.DateTime.Formatter.format(to, right, locale_id, options_map) do
        {:ok, left_str <> right_str}
      end
    else
      {:error, :no_practical_difference} ->
        Localize.Date.to_string(from, options)

      {:error, _} = error ->
        error
    end
  end

  # ── Time-only interval ──────────────────────────────────────

  defp format_time_interval(from, to, options) do
    locale = Keyword.get(options, :locale, Localize.get_locale())

    # `:time_format` is the explicit time-axis selector and matches
    # the option used on datetime intervals (where `time_sub_options/1`
    # honours it). For time-only intervals it must take precedence
    # over `:format`, which is overloaded across interval shapes.
    format =
      Keyword.get(options, :time_format) ||
        Keyword.get(options, :format, @default_format)

    case resolve_time_style(format) do
      {:ok, {:literal, pattern}} ->
        format_time_interval_literal(from, to, pattern, locale, options)

      {:ok, {:fallback_style, style}} ->
        # CLDR ships no interval-format data for `:hms` / `:hmsv`
        # skeletons. Format each endpoint via `Localize.Time.to_string/2`
        # with the requested style and join with the interval fallback.
        format_time_interval_literal(from, to, style, locale, options)

      {:ok, format_key} ->
        format_time_interval_styled(from, to, format_key, locale, options)
    end
  end

  defp format_time_interval_styled(from, to, format_key, locale, options) do
    with {:ok, locale_id} <- resolve_locale_id(locale),
         {:ok, formats} <- Localize.DateTime.Format.interval_formats(locale_id),
         {:ok, greatest_diff} <- greatest_difference(from, to),
         # Time interval maps use lowercase `:h` for hour-level differences
         # (the :hm/:h format maps use `h` as the key); callers/tests see
         # the same pattern selected as greatest_difference returns :H.
         time_diff = normalize_time_diff(greatest_diff),
         {:ok, interval_pattern} <- get_interval_pattern(formats, format_key, time_diff),
         {:ok, [left, right]} <- split_interval(interval_pattern) do
      options_map = Map.new(options)

      with {:ok, left_str} <-
             Localize.DateTime.Formatter.format(from, left, locale_id, options_map),
           {:ok, right_str} <-
             Localize.DateTime.Formatter.format(to, right, locale_id, options_map) do
        {:ok, left_str <> right_str}
      end
    else
      {:error, :no_practical_difference} ->
        Localize.Time.to_string(from, options)

      {:error, _} = error ->
        error
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
  defp format_time_interval_literal(from, to, time_format, locale, options) do
    with {:ok, locale_id} <- resolve_locale_id(locale),
         {:ok, formats} <- Localize.DateTime.Format.interval_formats(locale_id),
         {:ok, fallback} <- get_fallback_pattern(formats),
         {:ok, left_str} <- Localize.Time.to_string(from, [{:format, time_format} | options]),
         {:ok, right_str} <- Localize.Time.to_string(to, [{:format, time_format} | options]) do
      result =
        [left_str, right_str]
        |> Localize.Substitution.substitute(fallback)
        |> IO.iodata_to_binary()

      {:ok, result}
    end
  end

  # ── Datetime interval ───────────────────────────────────────
  #
  # Mirrors ex_cldr_dates_times' `Cldr.DateTime.Interval` behaviour:
  #
  # * Same day (hour/minute differs only) — format `from` as a full
  #   datetime and `to` as a time-only string; combine with the locale's
  #   `interval_format_fallback` pattern. Produces output like
  #   `"Apr 8, 2026, 12:00 PM – 2:00 PM"`.
  #
  # * Different day (day/month/year differs) — format both endpoints
  #   as full datetimes; combine with the same fallback pattern.
  #   Produces `"Apr 15, 2026, 12:49 AM – Apr 16, 2026, 1:49 AM"`.

  defp format_datetime_interval(from, to, options) do
    locale = Keyword.get(options, :locale, Localize.get_locale())

    with {:ok, locale_id} <- resolve_locale_id(locale),
         {:ok, formats} <- Localize.DateTime.Format.interval_formats(locale_id),
         {:ok, fallback} <- get_fallback_pattern(formats),
         {:ok, greatest_diff} <- greatest_difference(from, to) do
      datetime_options = datetime_sub_options(options)
      time_options = time_sub_options(options)

      with {:ok, left_str, right_str} <-
             format_datetime_parts(from, to, greatest_diff, datetime_options, time_options) do
        result =
          [left_str, right_str]
          |> Localize.Substitution.substitute(fallback)
          |> IO.iodata_to_binary()

        {:ok, result}
      end
    else
      {:error, :no_practical_difference} ->
        Localize.DateTime.to_string(from, datetime_sub_options(options) |> Map.to_list())

      {:error, _} = error ->
        error
    end
  end

  # Same-day datetime interval: from is a full datetime, to is just time.
  defp format_datetime_parts(from, to, diff, datetime_options, time_options)
       when diff in [:H, :m] do
    with {:ok, left} <- Localize.DateTime.to_string(from, Map.to_list(datetime_options)),
         {:ok, right} <- Localize.Time.to_string(to, Map.to_list(time_options)) do
      {:ok, left, right}
    end
  end

  # Different-day datetime interval: both sides are full datetimes.
  defp format_datetime_parts(from, to, diff, datetime_options, _time_options)
       when diff in [:y, :M, :d] do
    with {:ok, left} <- Localize.DateTime.to_string(from, Map.to_list(datetime_options)),
         {:ok, right} <- Localize.DateTime.to_string(to, Map.to_list(datetime_options)) do
      {:ok, left, right}
    end
  end

  # Derive the datetime-format options from the interval options,
  # applying `:date_format` and `:time_format` overrides if present.
  defp datetime_sub_options(options) do
    base =
      options
      |> Keyword.take([:locale, :prefer])
      |> Map.new()

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

  # Time-only options: use `:time_format` as the format if given,
  # otherwise fall back to the main `:format` option.
  defp time_sub_options(options) do
    base =
      options
      |> Keyword.take([:locale, :prefer])
      |> Map.new()

    format =
      Keyword.get(options, :time_format) ||
        Keyword.get(options, :format, @default_format)

    Map.put(base, :format, format)
  end

  # Time-only interval format maps use `:h` as the hour-level difference
  # key (mirroring CLDR's `intervalFormatItem` notation). Our
  # `greatest_difference/2` returns `:H` for any hour-level difference.
  # Translate at the lookup boundary so the existing `get_interval_pattern`
  # fallback chain (`:M → :d → :y`) still works unchanged.
  defp normalize_time_diff(:H), do: :h
  defp normalize_time_diff(diff), do: diff

  # Time-only intervals use skeleton keys that contain time fields.
  # A binary input is a literal CLDR pattern; flagged with the
  # `{:literal, pattern}` tag so the caller dispatches it through the
  # `interval_format_fallback` path instead of attempting an
  # interval-format-key lookup.
  defp resolve_time_style(format) when is_binary(format) do
    {:ok, {:literal, format}}
  end

  # The standard styles map as follows:
  #
  # * `:short` → `:hm` skeleton, dispatched via CLDR's interval-format
  #   table. CLDR ships `:hm` (and `:Hm`/`:hmv`/`:Hmv`/`:Bhm`) interval
  #   patterns that collapse repeated parts (e.g. "12:00 – 12:30 PM"
  #   for en, sharing the AM/PM marker between endpoints).
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
  #
  # The previous implementation collapsed all atom styles to `:hm`,
  # producing identical output for `:short` / `:medium` / `:long`.
  defp resolve_time_style(:short), do: {:ok, :hm}
  defp resolve_time_style(:medium), do: {:ok, {:fallback_style, :medium}}
  defp resolve_time_style(:long), do: {:ok, {:fallback_style, :long}}
  defp resolve_time_style(:full), do: {:ok, {:fallback_style, :full}}
  defp resolve_time_style(format) when is_atom(format), do: {:ok, format}

  # Open-ended intervals. One endpoint is `nil`; format the known
  # endpoint using its normal single-value formatter, then substitute
  # into the locale's `:interval_format_fallback` pattern (which is
  # of the form `[0, " – ", 1]`). For `:open_start`, the known value
  # goes into slot 1 and we trim the leading separator. For
  # `:open_end`, it goes into slot 0 and we trim the trailing separator.
  defp format_open_interval(value, side, options) do
    locale = Keyword.get(options, :locale, Localize.get_locale())

    with {:ok, locale_id} <- resolve_locale_id(locale),
         {:ok, formats} <- Localize.DateTime.Format.interval_formats(locale_id),
         {:ok, pattern} <- get_fallback_pattern(formats),
         {:ok, formatted} <- format_single_value(value, options) do
      {a, b} =
        case side do
          :open_start -> {"", formatted}
          :open_end -> {formatted, ""}
        end

      result =
        [a, b]
        |> Localize.Substitution.substitute(pattern)
        |> IO.iodata_to_binary()
        |> trim_open_interval(side)

      {:ok, result}
    end
  end

  defp trim_open_interval(string, :open_start), do: String.trim_leading(string)
  defp trim_open_interval(string, :open_end), do: String.trim_trailing(string)

  defp get_fallback_pattern(formats) do
    case Map.get(formats, :interval_format_fallback) do
      nil ->
        {:error, Localize.DateTimeIntervalFormatError.exception(reason: :no_fallback)}

      pattern ->
        {:ok, pattern}
    end
  end

  # Dispatch a single value to the appropriate formatter based on its shape.
  # Pure time values (hour but no year) go to Time; pure date values (year but
  # no hour) go to Date; everything else (including NaiveDateTime, DateTime,
  # and generic maps with both date and time fields) goes to DateTime.
  defp format_single_value(%Time{} = value, options), do: Localize.Time.to_string(value, options)
  defp format_single_value(%Date{} = value, options), do: Localize.Date.to_string(value, options)

  defp format_single_value(%DateTime{} = value, options),
    do: Localize.DateTime.to_string(value, options)

  defp format_single_value(%NaiveDateTime{} = value, options),
    do: Localize.DateTime.to_string(value, options)

  defp format_single_value(value, options) when is_map(value) do
    cond do
      Map.has_key?(value, :year) and Map.has_key?(value, :hour) ->
        Localize.DateTime.to_string(value, options)

      Map.has_key?(value, :year) ->
        Localize.Date.to_string(value, options)

      Map.has_key?(value, :hour) ->
        Localize.Time.to_string(value, options)

      true ->
        {:error, Localize.DateTimeInvalidInputError.exception(type: :datetime)}
    end
  end

  @doc """
  Same as `to_string/3` but raises on error.

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

  * `{:error, :no_practical_difference}` if the values are equal.

  """
  @spec greatest_difference(map(), map()) ::
          {:ok, :y | :M | :d | :H | :m} | {:error, :no_practical_difference}
  def greatest_difference(from, to) do
    cond do
      Map.get(from, :year) != Map.get(to, :year) -> {:ok, :y}
      Map.get(from, :month) != Map.get(to, :month) -> {:ok, :M}
      Map.get(from, :day) != Map.get(to, :day) -> {:ok, :d}
      Map.get(from, :hour) != Map.get(to, :hour) -> {:ok, :H}
      Map.get(from, :minute) != Map.get(to, :minute) -> {:ok, :m}
      true -> {:error, :no_practical_difference}
    end
  end

  @doc """
  Returns the date interval style configurations.

  """
  @spec date_styles() :: %{
          date: %{short: :yMd, medium: :yMMMd, long: :yMMMEd},
          month: %{short: :M, medium: :MMM, long: :MMM},
          month_and_day: %{short: :Md, medium: :MMMd, long: :MMMEd},
          year_and_month: %{short: :yM, medium: :yMMM, long: :yMMMM}
        }
  def date_styles, do: @date_styles

  # ── Interval pattern resolution ────────────────────────────

  defp resolve_style(style, format) when is_atom(style) and is_atom(format) do
    case get_in(@date_styles, [style, format]) do
      nil ->
        {:error,
         Localize.DateTimeIntervalFormatError.exception(
           reason: :unknown_style,
           style: style,
           format: format
         )}

      format_key ->
        {:ok, format_key}
    end
  end

  defp get_interval_pattern(formats, format_key, greatest_diff) do
    case Map.get(formats, format_key) do
      nil ->
        {:error,
         Localize.DateTimeIntervalFormatError.exception(
           reason: :no_format,
           format_key: format_key
         )}

      format_map when is_map(format_map) ->
        # Look up by greatest difference, with fallbacks
        pattern =
          Map.get(format_map, greatest_diff) ||
            Map.get(format_map, :M) ||
            Map.get(format_map, :d) ||
            Map.get(format_map, :y)

        if pattern do
          {:ok, pattern}
        else
          {:error,
           Localize.DateTimeIntervalFormatError.exception(
             reason: :no_pattern,
             format_key: format_key,
             detail: greatest_diff
           )}
        end

      pattern when is_binary(pattern) ->
        {:ok, pattern}
    end
  end

  # ── Interval splitting ─────────────────────────────────────

  @doc """
  Splits an interval format string into `[left, right]` halves
  at the point where a format character repeats.

  """
  @spec split_interval(String.t()) :: {:ok, [String.t()]} | {:error, Exception.t()}
  def split_interval(interval) when is_binary(interval) do
    case do_split_interval(interval, [], "") do
      [_, _] = result ->
        {:ok, result}

      {:error, _} = error ->
        error
    end
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

  # ── Locale resolution ──────────────────────────────────────

  defp resolve_locale_id(locale), do: Localize.Locale.cldr_locale_id_from(locale)
end
