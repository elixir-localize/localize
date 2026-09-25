defmodule Localize.Interval do
  @moduledoc """
  Formats date and time intervals as localized strings.

  Interval formats produce strings like "Jan 10 – 12, 2008" from
  two dates, rather than repeating "Jan 10, 2008 – Jan 12, 2008".
  The format is selected based on the greatest calendar field
  difference between the start and end values.

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

  # The year-bearing skeleton for each field skeleton without a year. An
  # interval across a year boundary formats with it, as ICU does.
  @year_widened_skeletons %{M: :yM, MMM: :yMMM, Md: :yMd, MMMd: :yMMMd, MMMEd: :yMMMEd}

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

  * `:numeric_date_separator` and `:numeric_time_separator` are
    strings replacing the locale's own separators in the rendered
    pattern, as they do on `Localize.Date.to_string/2`. A separator
    the pattern merges with neighbouring literal text is left alone
    — fi's day-differing interval pattern is `"d.–d.M.y"`, whose
    first separator carries the range dash — so an interval may
    substitute one endpoint and not the other.

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

        {:ok, {format_key, requested_skeleton}} ->
          format_date_interval_styled(
            from,
            to,
            format_key,
            requested_skeleton,
            locale,
            options,
            output
          )

        {:ok, format_key} ->
          format_date_interval_styled(from, to, format_key, nil, locale, options, output)

        {:error, _} = error ->
          error
      end
    end
  end

  defp format_date_interval_styled(
         from,
         to,
         format_key,
         requested_skeleton,
         locale,
         options,
         output
       ) do
    skeleton = requested_skeleton || format_key

    with {:ok, locale_id} <- resolve_locale_id(locale),
         {:ok, formats} <- Localize.DateTime.Format.interval_formats(locale_id) do
      options_map = options |> Map.new() |> Map.put_new(:locale, locale)

      case date_interval_plan(formats, format_key, requested_skeleton, from, to, options) do
        :single ->
          format_single(output, Localize.Date, from, Keyword.put(options, :format, skeleton))

        {:split, left, right} ->
          format_split(output, from, to, left, right, locale_id, options_map)

        {:fallback, fallback_skeleton} ->
          format_in_full(output, Localize.Date, {from, to}, fallback_skeleton, formats, options)

        {:error, _} = error ->
          error
      end
    end
  end

  # TR35 §Interval Formats steps 4 to 7, as ICU implements them. Values that
  # differ in no unit the skeleton displays format as one. A year difference
  # for a skeleton without a year takes the pattern of the skeleton widened
  # with one, so an interval across a year boundary keeps both years. Any
  # other difference takes the item's pattern for it, or failing that the
  # fallback pattern around both values in full.
  defp date_interval_plan(formats, format_key, requested_skeleton, from, to, options) do
    skeleton = requested_skeleton || format_key
    difference = calendar_difference(from, to)

    cond do
      not difference_visible?(skeleton, difference) ->
        :single

      difference == :year and Map.has_key?(@year_widened_skeletons, format_key) ->
        widened = Map.get(@year_widened_skeletons, format_key)
        interval_split(formats, widened, nil, :y, options, widened)

      true ->
        key = difference_key(difference, skeleton, Map.get(formats, format_key))
        interval_split(formats, format_key, requested_skeleton, key, options, skeleton)
    end
  end

  defp format_date_interval_fallback(from, to, format, locale, options, output) do
    with {:ok, locale_id} <- resolve_locale_id(locale),
         {:ok, formats} <- Localize.DateTime.Format.interval_formats(locale_id) do
      if calendar_difference(from, to) do
        format_in_full(output, Localize.Date, {from, to}, format, formats, options)
      else
        format_single(output, Localize.Date, from, Keyword.put(options, :format, format))
      end
    end
  end

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

  # The same steps as a date interval: an invisible difference formats one
  # time, and a difference the item has no pattern for glues both in full.
  defp format_time_interval_styled(from, to, format_key, locale, options, output) do
    with {:ok, locale_id} <- resolve_locale_id(locale),
         {:ok, formats} <- Localize.DateTime.Format.interval_formats(locale_id) do
      difference = calendar_difference(from, to)

      if difference_visible?(format_key, difference) do
        locale_data = {locale, locale_id, formats}
        format_time_difference(output, {from, to}, format_key, difference, locale_data, options)
      else
        format_single(output, Localize.Time, from, Keyword.put(options, :format, format_key))
      end
    end
  end

  defp format_time_difference(output, {from, to}, format_key, difference, locale_data, options) do
    {locale, locale_id, formats} = locale_data
    item_key = time_interval_key(formats, format_key, locale, locale_id)
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
  defp time_interval_key(formats, format_key, locale, locale_id) do
    if Map.has_key?(formats, format_key) do
      format_key
    else
      requested = Localize.Time.hour_cycle_skeleton(format_key, locale)

      case Localize.DateTime.Format.Match.best_interval_match(requested, locale_id) do
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
         {:ok, formats} <- Localize.DateTime.Format.interval_formats(locale_id) do
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
    datetime_options = datetime_sub_options(options) |> Map.to_list()
    time_options = time_sub_options(options) |> Map.to_list()
    format = Keyword.get(options, :format, @default_format)
    date_format = Keyword.get(options, :date_format) || format
    time_format = Keyword.get(options, :time_format) || format

    with {:ok, locale_id} <- resolve_locale_id(locale),
         {:ok, formats} <- Localize.DateTime.Format.interval_formats(locale_id),
         {:ok, fallback} <- get_fallback_pattern(formats),
         {:ok, date_skeleton} <- format_skeleton(:date, date_format, locale_id),
         {:ok, time_skeleton} <- format_skeleton(:time, time_format, locale_id) do
      difference = calendar_difference(from, to)
      units = displayed_units(date_skeleton) ++ displayed_units(time_skeleton)
      in_full = {Localize.DateTime, to, datetime_options}
      time_only = {Localize.Time, to, time_options}

      cond do
        not units_show?(units, difference) ->
          format_single(output, Localize.DateTime, from, datetime_options)

        difference in [:year, :month, :day] ->
          format_fallback(output, {Localize.DateTime, from, datetime_options}, in_full, fallback)

        true ->
          formats
          |> time_range_split(time_skeleton, difference, locale, locale_id, options)
          |> format_time_range(output, {from, to}, date_format, options, {
            {Localize.DateTime, from, datetime_options},
            time_only,
            fallback
          })
      end
    end
  end

  # A time difference shows the date once, joined to the time interval CLDR
  # ships for the time fields, or where it ships none to both times around
  # the fallback pattern.
  defp format_time_range(
         {:split, left, right},
         output,
         endpoints,
         date_format,
         options,
         _fallback
       ) do
    format_date_and_time_range(output, endpoints, {left, right}, date_format, options)
  end

  defp format_time_range(_no_time_interval, output, _endpoints, _format, _options, fallback) do
    {first, second, pattern} = fallback
    format_fallback(output, first, second, pattern)
  end

  # The skeleton a date or time format displays: a standard format's
  # skeleton in the locale, or the skeleton or pattern given. A format of any
  # other shape is `nil`, taken to display every unit.
  defp format_skeleton(:date, format, locale_id) when format in [:short, :medium, :long, :full] do
    with {:ok, skeletons} <- Localize.DateTime.Format.date_formats(locale_id) do
      {:ok, Map.get(skeletons, format)}
    end
  end

  defp format_skeleton(:time, format, locale_id) when format in [:short, :medium, :long, :full] do
    with {:ok, skeletons} <- Localize.DateTime.Format.time_formats(locale_id) do
      {:ok, Map.get(skeletons, format)}
    end
  end

  defp format_skeleton(_type, format, _locale_id) when is_atom(format) or is_binary(format),
    do: {:ok, format}

  defp format_skeleton(_type, _format, _locale_id), do: {:ok, nil}

  # The interval CLDR ships for the time fields of a datetime format, split in
  # two. A 12-hour hour implies its day period, so `a` is dropped before
  # matching; left in, `ahmm` would match the flexible-period `Bhm` item.
  defp time_range_split(formats, time_skeleton, difference, locale, locale_id, options)
       when is_atom(time_skeleton) and not is_nil(time_skeleton) do
    requested =
      time_skeleton
      |> Localize.Time.hour_cycle_skeleton(locale)
      |> Kernel.to_string()
      |> String.replace("a", "")

    with {:ok, matched_key} <-
           Localize.DateTime.Format.Match.best_interval_match(requested, locale_id) do
      key = difference_key(difference, matched_key, Map.get(formats, matched_key))
      interval_split(formats, matched_key, requested, key, options, :none)
    end
  end

  defp time_range_split(_formats, _skeleton, _difference, _locale, _locale_id, _options),
    do: :none

  # TR35 step 3.2: the date formatted once, joined to the time range through
  # the locale's date-time pattern for the date format and `:style`.
  defp format_date_and_time_range(output, {from, to}, {left, right}, date_format, options) do
    locale = Keyword.get(options, :locale, Localize.get_locale())
    style = Keyword.get(options, :style, :at)
    options_map = options |> Map.new() |> Map.put_new(:locale, locale)

    date_options =
      options
      |> Keyword.take([:locale, :prefer])
      |> Keyword.put(:format, date_format)

    with {:ok, locale_id} <- resolve_locale_id(locale),
         {:ok, wrapper} <- Localize.DateTime.date_time_wrapper(date_format, locale_id, style),
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

  # ── The difference an interval displays ────────────────────

  # Units from largest to smallest. AM/PM sits above the hour: two times on
  # either side of noon differ in it first.
  @unit_order [:year, :month, :day, :am_pm, :hour, :minute, :second]

  # The pattern symbols that display each unit. A 12-hour hour displays the
  # day period too.
  @unit_symbols [
    year: ~w(G y Y u U r),
    month: ~w(M L Q q),
    day: ~w(d D F g E e c),
    am_pm: ~w(a b B h K),
    hour: ~w(h H K k j J C),
    minute: ~w(m),
    second: ~w(s S A)
  ]

  defp calendar_difference(from, to) do
    Enum.find(@unit_order, &differs?(from, to, &1))
  end

  defp differs?(%{hour: from_hour}, %{hour: to_hour}, :am_pm)
       when is_integer(from_hour) and is_integer(to_hour) do
    from_hour < 12 != to_hour < 12
  end

  defp differs?(_from, _to, :am_pm), do: false
  defp differs?(from, to, unit), do: Map.get(from, unit) != Map.get(to, unit)

  # A difference shows only when the format displays its unit or a smaller
  # one; otherwise the two values are indistinguishable (TR35 step 4).
  defp difference_visible?(format, difference),
    do: units_show?(displayed_units(format), difference)

  defp units_show?(_units, nil), do: false

  defp units_show?(units, difference) do
    difference_rank = unit_rank(difference)
    Enum.any?(units, &(unit_rank(&1) >= difference_rank))
  end

  defp displayed_units(format) when is_nil(format) or format in [:short, :medium, :long, :full],
    do: @unit_order

  defp displayed_units(format) do
    letters =
      format
      |> Kernel.to_string()
      |> then(&Regex.replace(~r/'[^']*'/, &1, ""))
      |> String.graphemes()

    for {unit, symbols} <- @unit_symbols, Enum.any?(symbols, &(&1 in letters)), do: unit
  end

  defp unit_rank(unit), do: Enum.find_index(@unit_order, &(&1 == unit))

  # The greatestDifference id CLDR keys each difference by. Hour entries use
  # the skeleton's own hour symbol. An AM/PM difference takes the `a` entry,
  # or the `B` entry of a flexible-day-period item, and otherwise the hour
  # entry, as ICU does for 24-hour items that ship no `a`.
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
    {left, right} = hour_cycle_split(left, right, options_map)

    with {:ok, left_str} <-
           Localize.DateTime.Formatter.format(from, left, locale_id, options_map),
         {:ok, right_str} <-
           Localize.DateTime.Formatter.format(to, right, locale_id, options_map) do
      {:ok, left_str <> right_str}
    end
  end

  defp format_split(:parts, from, to, left, right, locale_id, options_map) do
    {left, right} = hour_cycle_split(left, right, options_map)

    with {:ok, left_parts} <-
           Localize.DateTime.Formatter.format_to_parts(from, left, locale_id, options_map),
         {:ok, right_parts} <-
           Localize.DateTime.Formatter.format_to_parts(to, right, locale_id, options_map) do
      {:ok, join_split_parts(left_parts, right_parts)}
    end
  end

  # An interval's halves take a `-u-hc-` hour cycle's hour symbol, as a
  # single time does.
  defp hour_cycle_split(left, right, options_map) do
    locale = Map.get(options_map, :locale)
    {Localize.Time.apply_hour_cycle(left, locale), Localize.Time.apply_hour_cycle(right, locale)}
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
          skeleton_or_fallback_style(skeleton, interval_formats, format, locale_id)

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

  defp resolve_fields(fields, format, _locale_id) do
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
  defp skeleton_or_fallback_style(skeleton, interval_formats, format, locale_id) do
    if Map.has_key?(interval_formats, skeleton) do
      {:ok, skeleton}
    else
      case Localize.DateTime.Format.Match.best_interval_match(skeleton, locale_id) do
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
  def split_interval(interval) when is_binary(interval) do
    case do_split_interval(interval, [], "") do
      [_, _] = result ->
        {:ok, result}

      {:error, _} = error ->
        error
    end
  end

  def split_interval(interval) do
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

  The inverse of `to_string/3`. Accepts either a single string
  (e.g. `"May 5 – May 10, 2026"`) in which case the parser splits on the
  locale's CLDR `intervalFormatFallback` separator, **or** a 2-tuple
  `{from_string, to_string}` for two-input UIs that already have the
  endpoints split.

  Each endpoint is parsed independently via `Localize.Date.parse/2`. The
  result is a `t:Date.Range.t/0` whose endpoints share the calendar named
  by the `:calendar` option, which defaults to `Calendar.ISO`.

  ### Arguments

  * `input` is either a binary or a `{from_binary, to_binary}` tuple.

  * `options` is a keyword list of options.

  ### Options

  Same as `Localize.Date.parse/2` — `:locale`, `:calendar`,
  `:reference_date`, `:as`. As there, `:calendar` is a calendar module and
  the endpoints are built in it. Plus:

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
    both carrying `:year`, or

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
