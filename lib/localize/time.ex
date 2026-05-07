defmodule Localize.Time do
  @moduledoc """
  Provides localized formatting of `Time` structs and time-like maps.

  Supports both full times (`%{hour: _, minute: _, second: _}`) and
  partial times (any map with one or more of `:hour`, `:minute`,
  `:second`). For partial times, the format is derived from the
  available fields.

  Formats are defined in CLDR and described in
  [TR35](http://unicode.org/reports/tr35/tr35-dates.html).

  """

  import Kernel, except: [to_string: 1]

  @standard_formats [:short, :medium, :long, :full]
  @default_format :medium
  # Ordered by CLDR canonical skeleton order: hour, minute, second
  @time_fields_ordered [{:hour, "h"}, {:minute, "m"}, {:second, "s"}]
  # @time_field_names Enum.map(@time_fields_ordered, &elem(&1, 0))

  defguardp is_full_time(time)
            when is_map_key(time, :hour) and is_map_key(time, :minute) and
                   is_map_key(time, :second)

  defguardp has_time_field(time)
            when is_map_key(time, :hour) or is_map_key(time, :minute) or
                   is_map_key(time, :second)

  @doc """
  Formats a time according to a CLDR format pattern.

  ### Arguments

  * `time` is a `t:Time.t/0` or any map with one or more of
    `:hour`, `:minute`, `:second` keys.

  * `options` is a keyword list of options.

  ### Options

  * `:format` is a standard format name (`:short`, `:medium`,
    `:long`, `:full`), a format skeleton atom, or a format
    pattern string. The default is `:medium` for full times.
    For partial times the format is derived from the available
    fields.

  * `:locale` is a locale identifier. The default is `:en`.

  * `:prefer` selects between CLDR `alt` variants. Accepts an
    atom or a list of atoms in priority order. Recognised values:
    `:unicode` / `:ascii` (NBSP and curly quotes vs ASCII) and
    `:standard` / `:variant` (a few locales publish two preferred
    forms). Examples: `prefer: :ascii`,
    `prefer: [:variant, :ascii]`. The default is
    `[:standard, :unicode]`.

  ### Returns

  * `{:ok, formatted_string}` on success.

  * `{:error, exception}` if the time cannot be formatted.

  ### Examples

      iex> Localize.Time.to_string(~T[14:30:00], locale: :en, prefer: :ascii)
      {:ok, "2:30:00 PM"}

      iex> Localize.Time.to_string(~T[14:30:00], format: :short, locale: :en, prefer: :ascii)
      {:ok, "2:30 PM"}

      iex> Localize.Time.to_string(%{hour: 14, minute: 30}, format: :hm, locale: :en, prefer: :ascii)
      {:ok, "2:30 PM"}

  """
  @spec to_string(map(), Keyword.t()) :: {:ok, String.t()} | {:error, Exception.t()}
  def to_string(time, options \\ [])

  # Full time
  def to_string(%{hour: _, minute: _, second: _} = time, options) do
    locale = Keyword.get(options, :locale, Localize.get_locale())
    format = Keyword.get(options, :format, @default_format)

    with {:ok, locale_id} <- resolve_locale_id(locale),
         {:ok, pattern} <- find_format(time, format, locale_id, options),
         {:ok, formatted} <-
           Localize.DateTime.Formatter.format(time, pattern, locale_id, Map.new(options)) do
      {:ok, formatted}
    end
  end

  # Partial time (has at least one time field but not all three)
  def to_string(time, options) when has_time_field(time) do
    locale = Keyword.get(options, :locale, Localize.get_locale())
    format = Keyword.get(options, :format)

    with {:ok, locale_id} <- resolve_locale_id(locale) do
      # Standard format atoms (`:short`/`:medium`/`:long`/`:full`) are
      # designed for full h/m/s times. For partial times we derive a
      # CLDR skeleton from the fields that are actually present
      # (`:h`, `:hm`, `:hms`, `:ms`, etc.) and resolve that instead.
      resolved_format =
        cond do
          is_binary(format) -> format
          is_atom(format) and format in @standard_formats -> derive_format_id(time)
          is_atom(format) and not is_nil(format) -> format
          true -> derive_format_id(time)
        end

      with {:ok, pattern} <- find_format(time, resolved_format, locale_id, options),
           {:ok, formatted} <-
             Localize.DateTime.Formatter.format(time, pattern, locale_id, Map.new(options)) do
        {:ok, formatted}
      end
    end
  end

  def to_string(_time, _options) do
    {:error, Localize.DateTimeInvalidInputError.exception(type: :time)}
  end

  @doc """
  Same as `to_string/2` but raises on error.

  ### Examples

      iex> Localize.Time.to_string!(~T[14:30:00], locale: :en, prefer: :ascii)
      "2:30:00 PM"

  """
  @spec to_string!(map(), Keyword.t()) :: String.t()
  def to_string!(time, options \\ []) do
    case to_string(time, options) do
      {:ok, string} -> string
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Returns the locale's preferred hour cycle.

  CLDR ships a per-territory (and per locale-territory) preference
  for how time-of-day is presented. The four cycles are:

  | Atom  | Range | Description                              |
  | :---- | :---- | :--------------------------------------- |
  | `:h11`| 0–11  | 12-hour clock, midnight is 0             |
  | `:h12`| 1–12  | 12-hour clock, midnight is 12            |
  | `:h23`| 0–23  | 24-hour clock, midnight is 0             |
  | `:h24`| 1–24  | 24-hour clock, midnight is 24            |

  A `-u-hc-` Unicode extension on the locale (e.g.
  `"fr-u-hc-h12"`) overrides the territory default.

  ### Arguments

  * `locale` is a locale name (atom or binary) or a
    `t:Localize.LanguageTag.t/0`.

  ### Returns

  * `{:ok, hour_cycle}` where `hour_cycle` is one of `:h11`,
    `:h12`, `:h23`, `:h24`.

  * `{:error, exception}` if the locale cannot be validated.

  ### Examples

      iex> Localize.Time.hour_format_from_locale(:ja)
      {:ok, :h23}

      iex> Localize.Time.hour_format_from_locale("en-AU")
      {:ok, :h12}

      iex> Localize.Time.hour_format_from_locale("fr-u-hc-h12")
      {:ok, :h12}

  """
  @spec hour_format_from_locale(Localize.LanguageTag.t() | atom() | String.t()) ::
          {:ok, :h11 | :h12 | :h23 | :h24} | {:error, Exception.t()}
  def hour_format_from_locale(%Localize.LanguageTag{locale: %{hc: hc}}) when not is_nil(hc) do
    {:ok, hc}
  end

  def hour_format_from_locale(%Localize.LanguageTag{cldr_locale_id: locale_id}) do
    prefs = Localize.DateTime.Format.Match.time_preferences_for(locale_id)
    {:ok, hour_cycle_from_symbol(prefs.preferred)}
  end

  def hour_format_from_locale(locale) do
    with {:ok, language_tag} <- Localize.validate_locale(locale) do
      hour_format_from_locale(language_tag)
    end
  end

  @doc """
  Same as `hour_format_from_locale/1` but raises on error.

  ### Examples

      iex> Localize.Time.hour_format_from_locale!(:ja)
      :h23

  """
  @spec hour_format_from_locale!(Localize.LanguageTag.t() | atom() | String.t()) ::
          :h11 | :h12 | :h23 | :h24
  def hour_format_from_locale!(locale) do
    case hour_format_from_locale(locale) do
      {:ok, cycle} -> cycle
      {:error, exception} -> raise exception
    end
  end

  defp hour_cycle_from_symbol("h"), do: :h12
  defp hour_cycle_from_symbol("K"), do: :h11
  defp hour_cycle_from_symbol("H"), do: :h23
  defp hour_cycle_from_symbol("k"), do: :h24

  # ── Format resolution ──────────────────────────────────────

  defp find_format(_time, format, _locale_id, _options) when is_binary(format) do
    {:ok, format}
  end

  defp find_format(time, format, locale_id, options) when is_atom(format) do
    if format in @standard_formats and is_full_time(time) do
      Localize.DateTime.Format.resolve_format(:time, format, locale_id, :gregorian, options)
    else
      resolve_skeleton(format, locale_id, options)
    end
  end

  defp find_format(_time, format, _locale_id, _options) do
    {:error, Localize.DateTimeFormatError.exception(format: format, reason: :invalid_format)}
  end

  defp resolve_skeleton(skeleton, locale_id, options) when is_atom(skeleton) do
    with {:ok, available} <-
           Localize.DateTime.Format.available_formats(locale_id, :gregorian) do
      case Map.get(available, skeleton) do
        nil ->
          case Localize.DateTime.Format.Match.best_match(skeleton, locale_id) do
            {:ok, matched_id} when is_atom(matched_id) ->
              resolve_skeleton(matched_id, locale_id, options)

            {:ok, {_date_id, _time_id}} ->
              {:error,
               Localize.DateTimeUnresolvedFormatError.exception(
                 format: skeleton,
                 locale: locale_id
               )}

            {:error, _} = error ->
              error
          end

        %{} = variant_map ->
          case Localize.DateTime.Format.resolve_variant(variant_map, options) do
            nil ->
              {:error,
               Localize.DateTimeUnresolvedFormatError.exception(
                 format: skeleton,
                 locale: locale_id
               )}

            pattern ->
              {:ok, pattern}
          end

        pattern when is_binary(pattern) ->
          {:ok, pattern}
      end
    end
  end

  @doc false
  def derive_format_id(time) do
    @time_fields_ordered
    |> Enum.filter(fn {field, _symbol} -> Map.has_key?(time, field) end)
    |> Enum.map(fn {_field, symbol} -> symbol end)
    |> Enum.join()
    |> String.to_atom()
  end

  # ── Locale resolution ──────────────────────────────────────

  defp resolve_locale_id(locale), do: Localize.Locale.cldr_locale_id_from(locale)
end
