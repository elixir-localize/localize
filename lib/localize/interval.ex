defmodule Localize.Interval do
  @moduledoc """
  Formats date and time intervals as localized strings.

  Interval formats produce strings like "Jan 10 – 12, 2008" from
  two dates, rather than repeating "Jan 10, 2008 – Jan 12, 2008".
  The format is selected based on the greatest calendar field
  difference between the start and end values.

  """

  import Kernel, except: [to_string: 1]

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

  @doc """
  Formats a date interval as a localized string.

  ### Arguments

  * `from` is a `t:Date.t/0`.

  * `to` is a `t:Date.t/0`.

  * `options` is a keyword list of options.

  ### Options

  * `:locale` is a locale identifier. The default is `:en`.

  * `:fields` selects *which* date fields appear: `:date` (the
    whole date, the default), `:month`, `:month_and_day`, or
    `:year_and_month`. See `known_fields/0`.

  * `:format` selects *how wide* those fields are rendered:
    `:short`, `:medium`, `:long`, or `:full`. The default is
    `:medium`.

  The two are independent axes: `:fields` chooses which fields
  appear, `:format` chooses how wide they are rendered. So
  `fields: :year_and_month` renders the two months against a
  single year either way — numerically for `format: :short`
  ("1/2022" … "3/2022") and spelled out for `format: :long`
  ("January" … "March 2022").

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
    format_closed_interval(from, to, options, :string)
  end

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

  def to_parts(from, to, _options) when is_nil(from) or is_nil(to) do
    {:error, Localize.DateTimeInvalidInputError.exception(type: :datetime)}
  end

  def to_parts(from, to, options) do
    format_closed_interval(from, to, options, :parts)
  end

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

  defp format_closed_interval(from, to, options, output) do
    cond do
      datetime_value?(from) and datetime_value?(to) ->
        format_datetime_interval(from, to, options, output)

      time_value?(from) and time_value?(to) ->
        format_time_interval(from, to, options, output)

      date_value?(from) and date_value?(to) ->
        format_date_interval(from, to, options, output)

      true ->
        {:error,
         Localize.DateTimeIntervalFormatError.exception(
           reason: :mixed_endpoints,
           detail: "#{inspect(from)} and #{inspect(to)}"
         )}
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

  defp date_value?(%Date{}), do: true
  defp date_value?(%{year: _} = map), do: not Map.has_key?(map, :hour)
  defp date_value?(_), do: false

  defp time_value?(%Time{}), do: true
  defp time_value?(%DateTime{}), do: false
  defp time_value?(%NaiveDateTime{}), do: false
  defp time_value?(%Date{}), do: false
  defp time_value?(%{hour: _} = map), do: not Map.has_key?(map, :year)
  defp time_value?(_), do: false

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
      case resolve_fields(fields, format, locale_id) do
        {:ok, {:fallback_style, fallback_format}} ->
          # CLDR ships no skeleton-keyed interval-format data for the
          # per-locale skeleton (e.g. ja's `:yMMdd` for `:short`,
          # en's `:yMMMMd` for `:long`, every locale's `:yMMMMEEEEd`
          # for `:full`). Format each endpoint via
          # `Localize.Date.to_string/2` with the requested style and
          # join via the locale's `interval_format_fallback`.
          format_date_interval_fallback(from, to, fallback_format, locale, options, output)

        {:ok, format_key} ->
          format_date_interval_styled(from, to, format_key, locale, options, output)

        {:error, _} = error ->
          error
      end
    end
  end

  defp format_date_interval_styled(from, to, format_key, locale, options, output) do
    with {:ok, locale_id} <- resolve_locale_id(locale),
         {:ok, formats} <- Localize.DateTime.Format.interval_formats(locale_id),
         {:ok, greatest_diff} <- greatest_difference(from, to),
         {:ok, interval_pattern} <- get_interval_pattern(formats, format_key, greatest_diff),
         {:ok, [left, right]} <- split_interval(interval_pattern) do
      options_map = options |> Map.new() |> Map.put_new(:locale, locale)
      format_split(output, from, to, left, right, locale_id, options_map)
    else
      {:error, %Localize.NoPracticalDifferenceError{}} ->
        format_single(output, Localize.Date, from, options)

      {:error, _} = error ->
        error
    end
  end

  defp format_date_interval_fallback(from, to, format, locale, options, output) do
    sub_options =
      options
      |> Keyword.take([:locale, :prefer])
      |> Keyword.put(:format, format)

    with {:ok, locale_id} <- resolve_locale_id(locale),
         {:ok, formats} <- Localize.DateTime.Format.interval_formats(locale_id),
         {:ok, fallback} <- get_fallback_pattern(formats) do
      format_fallback(
        output,
        {Localize.Date, from, sub_options},
        {Localize.Date, to, sub_options},
        fallback
      )
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

    case resolve_time_style(format, locale) do
      {:ok, {:literal, pattern}} ->
        format_time_interval_literal(from, to, pattern, locale, options, output)

      {:ok, {:fallback_style, style}} ->
        # CLDR ships no interval-format data for `:hms` / `:hmsv`
        # skeletons. Format each endpoint via `Localize.Time.to_string/2`
        # with the requested style and join with the interval fallback.
        format_time_interval_literal(from, to, style, locale, options, output)

      {:ok, format_key} ->
        format_time_interval_styled(from, to, format_key, locale, options, output)

      {:error, _} = error ->
        error
    end
  end

  defp format_time_interval_styled(from, to, format_key, locale, options, output) do
    with {:ok, locale_id} <- resolve_locale_id(locale),
         {:ok, formats} <- Localize.DateTime.Format.interval_formats(locale_id),
         {:ok, greatest_diff} <- greatest_difference(from, to),
         # `greatest_difference/2` returns `:H` for any hour-level
         # difference. CLDR's interval-format maps key the entry by
         # the skeleton's hour symbol — `:hm`/`:Bhm` use `:h`, while
         # `:Hm`/`:Hmv` use `:H`. Pick the key that matches `format_key`.
         time_diff = normalize_time_diff(greatest_diff, format_key),
         {:ok, interval_pattern} <- get_interval_pattern(formats, format_key, time_diff),
         {:ok, [left, right]} <- split_interval(interval_pattern) do
      options_map = options |> Map.new() |> Map.put_new(:locale, locale)

      format_split(output, from, to, left, right, locale_id, options_map)
    else
      {:error, %Localize.NoPracticalDifferenceError{}} ->
        format_single(output, Localize.Time, from, single_time_options(options))

      {:error, _} = error ->
        error
    end
  end

  # Options for formatting a single time endpoint (the equal-endpoint
  # fallback). `:time_format` is the explicit time-axis selector and
  # must win over the overloaded `:format` option, mirroring the
  # precedence applied in `format_time_interval/3`.
  defp single_time_options(options) do
    case Keyword.get(options, :time_format) do
      nil -> options
      time_format -> Keyword.put(options, :format, time_format)
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
    sub_options = [{:format, time_format} | options]

    with {:ok, locale_id} <- resolve_locale_id(locale),
         {:ok, formats} <- Localize.DateTime.Format.interval_formats(locale_id),
         {:ok, fallback} <- get_fallback_pattern(formats) do
      format_fallback(
        output,
        {Localize.Time, from, sub_options},
        {Localize.Time, to, sub_options},
        fallback
      )
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

  defp format_datetime_interval(from, to, options, output) do
    locale = Keyword.get(options, :locale, Localize.get_locale())

    with {:ok, locale_id} <- resolve_locale_id(locale),
         {:ok, formats} <- Localize.DateTime.Format.interval_formats(locale_id),
         {:ok, fallback} <- get_fallback_pattern(formats),
         {:ok, greatest_diff} <- greatest_difference(from, to) do
      datetime_options = datetime_sub_options(options) |> Map.to_list()
      time_options = time_sub_options(options) |> Map.to_list()

      left_spec = {Localize.DateTime, from, datetime_options}

      # Same-day intervals render the end as a time only; different-day
      # intervals render both endpoints as full datetimes.
      right_spec =
        if greatest_diff in [:H, :m] do
          {Localize.Time, to, time_options}
        else
          {Localize.DateTime, to, datetime_options}
        end

      format_fallback(output, left_spec, right_spec, fallback)
    else
      {:error, %Localize.NoPracticalDifferenceError{}} ->
        format_single(
          output,
          Localize.DateTime,
          from,
          datetime_sub_options(options) |> Map.to_list()
        )

      {:error, _} = error ->
        error
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

  # Time-only interval format maps key the hour-level entry by the
  # skeleton's own hour symbol. 12-hour skeletons (`:hm`, `:Bhm`,
  # `:hmv`) use `:h`; 24-hour skeletons (`:Hm`, `:Hmv`, `:H`) use
  # `:H`. Our `greatest_difference/2` always returns `:H` for an
  # hour-level difference, so collapse to `:h` only when the
  # `format_key` doesn't contain an uppercase `H`.
  defp normalize_time_diff(:H, format_key) when is_atom(format_key) do
    if format_key |> Atom.to_string() |> String.contains?("H"), do: :H, else: :h
  end

  defp normalize_time_diff(diff, _format_key), do: diff

  # Time-only intervals use skeleton keys that contain time fields.
  # A binary input is a literal CLDR pattern; flagged with the
  # `{:literal, pattern}` tag so the caller dispatches it through the
  # `interval_format_fallback` path instead of attempting an
  # interval-format-key lookup.
  defp resolve_time_style(format, _locale) when is_binary(format) do
    {:ok, {:literal, format}}
  end

  # The standard styles map as follows:
  #
  # * `:short` → `:hm` or `:Hm` skeleton, chosen from the locale's
  #   preferred hour cycle (via `Localize.Time.hour_format_from_locale/1`,
  #   which honours any `-u-hc-` Unicode-extension override).
  #   12-hour locales (h11/h12) use `:hm`; 24-hour locales (h23/h24)
  #   use `:Hm`. Both are dispatched via CLDR's interval-format table,
  #   which ships per-locale collapsing — e.g. en's
  #   "12:00 – 12:30 PM" sharing the AM/PM marker between endpoints.
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
  # The previous implementation hard-coded `:short` to `:hm`, which
  # ignored the locale's hour-cycle preference and produced 12-hour
  # output for 24-hour locales like `:ja` and `:de`.
  defp resolve_time_style(:short, locale) do
    case Localize.Time.hour_format_from_locale(locale) do
      {:ok, cycle} when cycle in [:h11, :h12] -> {:ok, :hm}
      {:ok, cycle} when cycle in [:h23, :h24] -> {:ok, :Hm}
      {:error, _} = error -> error
    end
  end

  defp resolve_time_style(:medium, _locale), do: {:ok, {:fallback_style, :medium}}
  defp resolve_time_style(:long, _locale), do: {:ok, {:fallback_style, :long}}
  defp resolve_time_style(:full, _locale), do: {:ok, {:fallback_style, :full}}
  defp resolve_time_style(format, _locale) when is_atom(format), do: {:ok, format}

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

  # ── Output-mode terminals (string | parts) ──────────────────

  # A split interval pattern: the left half formats `from`, the right
  # half formats `to`, concatenated directly.
  defp format_split(:string, from, to, left, right, locale_id, options_map) do
    with {:ok, left_str} <-
           Localize.DateTime.Formatter.format(from, left, locale_id, options_map),
         {:ok, right_str} <-
           Localize.DateTime.Formatter.format(to, right, locale_id, options_map) do
      {:ok, left_str <> right_str}
    end
  end

  defp format_split(:parts, from, to, left, right, locale_id, options_map) do
    with {:ok, left_parts} <-
           Localize.DateTime.Formatter.format_to_parts(from, left, locale_id, options_map),
         {:ok, right_parts} <-
           Localize.DateTime.Formatter.format_to_parts(to, right, locale_id, options_map) do
      {:ok, join_split_parts(left_parts, right_parts)}
    end
  end

  # The split pattern's separator (" – ") sits at the boundary of the
  # two halves as literal text; retag those bridging literals as
  # `:shared` per ECMA-402.
  defp join_split_parts(left_parts, right_parts) do
    left = tag_source(left_parts, :start_range)
    right = tag_source(right_parts, :end_range)

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
  def greatest_difference(from, to) do
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

  # The `:date` style aligns with the per-locale skeleton single
  # `Localize.Date.to_string/2` resolves for the same `:format`,
  # ensuring date intervals use the same conventions as single
  # dates. The locale's skeleton (e.g. ja's `:yMMdd` for `:medium`,
  # en's `:yMMMMd` for `:long`) may not be shipped in CLDR's
  # interval-format table; if not, the caller falls back to
  # formatting each endpoint with `Localize.Date.to_string/2` and
  # joining via the locale's `interval_format_fallback`.
  #
  # Other styles (`:month`, `:month_and_day`, `:year_and_month`)
  # remain locale-independent — they describe a deliberate field
  # selection unrelated to single Date's standard styles.
  defp resolve_fields(:date, format, locale_id) when format in [:short, :medium, :long, :full] do
    with {:ok, date_formats} <- Localize.DateTime.Format.date_formats(locale_id),
         {:ok, interval_formats} <- Localize.DateTime.Format.interval_formats(locale_id) do
      case Map.get(date_formats, format) do
        skeleton when is_atom(skeleton) ->
          skeleton_or_fallback_style(skeleton, interval_formats, format)

        _ ->
          {:error,
           Localize.DateTimeIntervalFormatError.exception(
             reason: :unknown_fields,
             fields: :date,
             format: format
           )}
      end
    end
  end

  defp resolve_fields(fields, format, _locale_id) when is_atom(fields) and is_atom(format) do
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

  # Use the locale's skeleton when CLDR ships an interval format
  # for it, otherwise signal the endpoint-formatting fallback.
  defp skeleton_or_fallback_style(skeleton, interval_formats, format) do
    if Map.has_key?(interval_formats, skeleton) do
      {:ok, skeleton}
    else
      {:ok, {:fallback_style, format}}
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

  ### Arguments

  * `interval` is an interval format pattern string.

  ### Returns

  * `{:ok, [left, right]}` where `left` and `right` are the two
    halves of the interval pattern.

  * `{:error, exception}` if the pattern is malformed or has no
    repeating field.

  ### Examples

      iex> Localize.Interval.split_interval("MMM d – d")
      {:ok, ["MMM d – ", "d"]}

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
