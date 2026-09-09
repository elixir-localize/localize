defmodule Localize.DateTime.Parser do
  @moduledoc false

  # Locale-aware parser for user-typed date-time strings.
  #
  # Public entry point: `Localize.DateTime.parse/2`.
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

  alias Localize.DateTimeParseError
  alias Localize.DateTime.Format

  @standard_formats [:short, :medium, :long, :full]

  @doc """
  Parses `input` as a locale-formatted datetime string.

  See `Localize.DateTime.parse/2` for the public contract.
  """
  @spec parse(String.t(), Keyword.t()) ::
          {:ok, NaiveDateTime.t() | DateTime.t() | map()} | {:error, Exception.t()}
  def parse(input, options \\ []) when is_binary(input) do
    locale = Keyword.get(options, :locale) || Localize.get_locale()

    cldr_calendar =
      Localize.Date.Parser.normalise_calendar(Keyword.get(options, :calendar, :gregorian))

    as = Keyword.get(options, :as, :struct)

    # Strip weekday prefix here too — the glue-splitting step
    # doesn't know which half is the date, so a leading
    # `"Sun, "` would otherwise survive into the date half
    # regardless of where the date/time boundary lands. Ordinal
    # stripping doesn't need to be applied here because each
    # half is forwarded through `Localize.Date.parse/2` /
    # `Localize.Time.parse/2`, and `Date.parse/2` already
    # runs the ordinal-fallback retry per endpoint.
    input =
      input
      |> Localize.Date.Parser.normalise_input()
      |> Localize.Date.Parser.preprocess_safe(locale, cldr_calendar)

    case try_iso(input) do
      {:ok, value} ->
        {:ok, finalise_datetime(value, as)}

      :error ->
        try_locale_glue(input, locale, options, as)
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
    |> Map.put(:time_zone, dt.time_zone)
    |> Map.put(:utc_offset, dt.utc_offset)
    |> Map.put(:std_offset, dt.std_offset)
    |> Map.put(:zone_abbr, dt.zone_abbr)
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
    case glue_separators(locale) do
      [] ->
        {:error, no_match_error(input, locale)}

      separators ->
        # The glue separator (e.g. `, ` in en) often appears
        # inside the date half too — `MMM d, y` puts a comma
        # between day and year. Try every split point for every
        # candidate separator and accept the first that yields
        # parseable date + time halves.
        candidates =
          for sep <- separators,
              {left, right} <- enumerate_splits(input, sep) do
            {sep, left, right}
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

  defp try_split_as_struct({_sep, left, right}, options) do
    # Check the time half first: it is cheaper to parse and far more
    # selective (a time needs an hour), so a failing right half
    # short-circuits the expensive date parse on every non-time split.
    with {:ok, time, zone} <-
           Localize.Time.Parser.parse_with_zone(right, options),
         {:ok, date} <- Localize.Date.parse(left, options),
         {:ok, ndt} <- NaiveDateTime.new(date, time) do
      case zone do
        nil -> {:ok, ndt}
        _ -> {:ok, resolve_zone(zone, ndt, options)}
      end
    else
      _ -> nil
    end
  end

  # A fixed UTC offset — ISO 8601 (`+05:30`, `Z`) or the localized GMT
  # format in any locale's spelling (`GMT+10:30`, `UTC-5`, `غرينتش+03:00`)
  # — is arithmetic, so it resolves here with no dependency.
  #
  # A named zone (`PST`, `Asia/Tokyo`) carries no offset of its own and
  # needs a TZ database, which this library does not ship. That is reached
  # optionally through `calendrical`; failure for any reason — no resolver,
  # no TZ database, an unknown IANA name — falls back to the
  # `NaiveDateTime`, preserving the parse rather than failing the whole
  # input.
  defp resolve_zone(zone, naive_datetime, options) do
    case Localize.DateTime.Timezone.parse_offset(zone, options) do
      {:ok, offset} ->
        datetime_at_offset(naive_datetime, offset)

      {:error, _not_a_fixed_offset} ->
        case Localize.OptionalDependency.call(
               "Calendrical.TimeZone",
               :resolve,
               [zone, naive_datetime, options],
               package: "calendrical",
               operation: "resolving the time zone #{inspect(zone)}"
             ) do
          {:ok, %DateTime{} = datetime} -> datetime
          _no_resolver -> naive_datetime
        end
    end
  end

  # `DateTime` stores local wall fields plus the offset, so the instant
  # the user typed is kept as they wrote it and rendered back as
  # `<local +offset>`. Note this differs from the ISO 8601 path, where
  # `DateTime.from_iso8601/1` normalises to UTC and the original offset
  # is lost.
  defp datetime_at_offset(naive_datetime, offset) do
    %DateTime{
      calendar: naive_datetime.calendar,
      year: naive_datetime.year,
      month: naive_datetime.month,
      day: naive_datetime.day,
      hour: naive_datetime.hour,
      minute: naive_datetime.minute,
      second: naive_datetime.second,
      microsecond: naive_datetime.microsecond,
      std_offset: 0,
      utc_offset: offset,
      zone_abbr: offset_abbreviation(offset),
      time_zone: "Etc/UTC"
    }
  end

  defp offset_abbreviation(0), do: "UTC"

  defp offset_abbreviation(offset) do
    sign = if offset < 0, do: "-", else: "+"
    absolute = abs(offset)
    hours = absolute |> div(3600) |> pad_offset()
    minutes = absolute |> rem(3600) |> div(60) |> pad_offset()
    "#{sign}#{hours}:#{minutes}"
  end

  defp pad_offset(value) when value < 10, do: "0#{value}"
  defp pad_offset(value), do: "#{value}"

  defp try_split_as_map({_sep, left, right}, options) do
    date_opts = Keyword.put(options, :as, :map)
    time_opts = Keyword.put(options, :as, :map)

    # Time half first — cheaper and more selective — so a failing right
    # half short-circuits the expensive date parse (see try_split_as_struct).
    with {:ok, %{} = time_map, _zone} <-
           Localize.Time.Parser.parse_with_zone(right, time_opts),
         {:ok, %{} = date_map} <- Localize.Date.parse(left, date_opts) do
      # Date map carries `:calendar`; time map carries the time
      # fields plus `:time_zone` if any. Merge — date's
      # `:calendar` wins (the time map has no calendar key).
      {:ok, Map.merge(time_map, date_map)}
    else
      _ -> nil
    end
  end

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

  defp try_iso(input) do
    # Shape `YYYY-MM-DD<sep>HH:MM:SS[…]` where <sep> is `T`
    # (RFC 3339 / ISO 8601) or a space (Elixir stdlib also
    # accepts; widely used by Postgres, SQLite, logs, etc.).
    if iso_datetime_shape?(input) do
      case DateTime.from_iso8601(input) do
        {:ok, dt, _offset} -> {:ok, dt}
        _ -> try_iso_naive(input)
      end
    else
      :error
    end
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

  # The CLDR date-time glue pattern is always `{1}<sep>{0}` —
  # `{1}` is the date portion and `{0}` is the time portion.
  # Extract `<sep>` from each standard glue pattern; the
  # caller backtracks through every split point in the input
  # to find one where both halves parse.
  defp glue_separators(locale) do
    cldr =
      case Format.date_time_formats(locale, :gregorian) do
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
      case Format.date_time_at_formats(locale, :gregorian) do
        {:ok, %{standard: at_map}} when is_map(at_map) ->
          @standard_formats
          |> Enum.map(&Map.get(at_map, &1))
          |> Enum.flat_map(&extract_separator/1)

        _ ->
          []
      end

    (cldr ++ at_time ++ @fallback_glue_separators)
    |> Enum.uniq()
    |> Enum.sort_by(&(-byte_size(&1)))
  end

  # Pattern shape is `{1}<sep>{0}`; pull <sep> via regex.
  # Returns the separator(s) as a list (most patterns yield
  # one; we wrap in a list for `flat_map` ergonomics).
  defp extract_separator(pattern) when is_binary(pattern) do
    case Regex.run(~r/\{1\}(.*?)\{0\}/u, pattern) do
      [_, sep] when sep != "" -> [unquote_cldr_literal(sep)]
      _ -> []
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
