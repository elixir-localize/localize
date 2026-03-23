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
  @spec to_string(map(), map(), Keyword.t()) ::
          {:ok, String.t()} | {:error, Exception.t()}
  def to_string(from, to, options \\ []) do
    locale = Keyword.get(options, :locale, Localize.get_locale())
    format = Keyword.get(options, :format, @default_format)
    style = Keyword.get(options, :style, @default_date_style)

    with {:ok, locale_id} <- resolve_locale_id(locale),
         {:ok, formats} <-
           Localize.DateTime.Format.interval_formats(locale_id),
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
          {:ok, atom()} | {:error, :no_practical_difference}
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
  @spec date_styles() :: map()
  def date_styles, do: @date_styles

  # ── Interval pattern resolution ────────────────────────────

  defp resolve_style(style, format) when is_atom(style) and is_atom(format) do
    case get_in(@date_styles, [style, format]) do
      nil ->
        {:error,
         Localize.DateTimeIntervalFormatError.exception(
           reason: "unknown style #{inspect(style)} or format #{inspect(format)}"
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
           reason: "no interval format found for #{inspect(format_key)}"
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
             reason:
               "no interval pattern for difference #{inspect(greatest_diff)} in format #{inspect(format_key)}"
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
       reason: "invalid interval format #{inspect(left)}"
     )}
  end

  # Quoted strings pass through
  defp do_split_interval(<<"'", rest::binary>>, acc, left) do
    case String.split(rest, "'", parts: 2) do
      [literal, rest] ->
        do_split_interval(rest, acc, left <> "'" <> literal <> "'")

      [_] ->
        {:error,
         Localize.DateTimeIntervalFormatError.exception(
           reason: "unterminated quote in interval format"
         )}
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

  defp resolve_locale_id(%Localize.LanguageTag{cldr_locale_id: id}), do: {:ok, id}

  defp resolve_locale_id(locale) when is_atom(locale) or is_binary(locale) do
    case Localize.validate_locale(locale) do
      {:ok, tag} -> {:ok, tag.cldr_locale_id}
      error -> error
    end
  end

  defp resolve_locale_id(invalid) do
    {:error, Localize.InvalidLocaleError.exception(locale_id: inspect(invalid))}
  end
end
