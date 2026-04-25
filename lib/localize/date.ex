defmodule Localize.Date do
  @moduledoc """
  Provides localized formatting of `Date` structs and date-like maps.

  Supports both full dates (`%{year: _, month: _, day: _}`) and partial
  dates (any map with one or more of `:year`, `:month`, `:day`). For
  partial dates, the format is derived from the available fields.

  Formats are defined in CLDR and described in
  [TR35](http://unicode.org/reports/tr35/tr35-dates.html).

  """

  import Kernel, except: [to_string: 1]

  @standard_formats [:short, :medium, :long, :full]
  @default_format :medium
  # Ordered by CLDR canonical skeleton order: year, month, day
  @date_fields_ordered [{:year, "y"}, {:month, "M"}, {:day, "d"}]
  # @date_field_names Enum.map(@date_fields_ordered, &elem(&1, 0))

  defguardp is_full_date(date)
            when is_map_key(date, :year) and is_map_key(date, :month) and is_map_key(date, :day)

  defguardp has_date_field(date)
            when is_map_key(date, :year) or is_map_key(date, :month) or is_map_key(date, :day)

  @doc """
  Formats a date according to a CLDR format pattern.

  ### Arguments

  * `date` is a `t:Date.t/0` or any map with one or more of
    `:year`, `:month`, `:day` keys.

  * `options` is a keyword list of options.

  ### Options

  * `:format` is a standard format name (`:short`, `:medium`,
    `:long`, `:full`), a format skeleton atom, or a format
    pattern string. The default is `:medium` for full dates.
    For partial dates the format is derived from the available
    fields.

  * `:locale` is a locale identifier. The default is `:en`.

  * `:prefer` is `:unicode` or `:ascii` for variant selection.
    The default is `:unicode`.

  ### Returns

  * `{:ok, formatted_string}` on success.

  * `{:error, exception}` if the date cannot be formatted.

  ### Examples

      iex> Localize.Date.to_string(~D[2017-07-10], locale: :en)
      {:ok, "Jul 10, 2017"}

      iex> Localize.Date.to_string(~D[2017-07-10], format: :full, locale: :en)
      {:ok, "Monday, July 10, 2017"}

      iex> Localize.Date.to_string(~D[2017-07-10], format: :short, locale: :en)
      {:ok, "7/10/17"}

      iex> Localize.Date.to_string(~D[2017-07-10], format: :short, locale: :fr)
      {:ok, "10/07/2017"}

      iex> Localize.Date.to_string(%{year: 2024, month: 6}, format: :yMMM, locale: :fr)
      {:ok, "juin 2024"}

  """
  @spec to_string(map(), Keyword.t()) :: {:ok, String.t()} | {:error, Exception.t()}
  def to_string(date, options \\ [])

  # Full date
  def to_string(%{year: _, month: _, day: _} = date, options) do
    locale = Keyword.get(options, :locale, Localize.get_locale())
    format = Keyword.get(options, :format, @default_format)

    with {:ok, locale_id} <- resolve_locale_id(locale),
         {:ok, pattern} <- find_format(date, format, locale_id, options),
         {:ok, formatted} <-
           Localize.DateTime.Formatter.format(date, pattern, locale_id, Map.new(options)) do
      {:ok, formatted}
    end
  end

  # Partial date
  def to_string(date, options) when has_date_field(date) do
    locale = Keyword.get(options, :locale, Localize.get_locale())
    format = Keyword.get(options, :format)

    with {:ok, locale_id} <- resolve_locale_id(locale) do
      resolved_format =
        cond do
          is_binary(format) ->
            format

          is_atom(format) and format != nil and format not in @standard_formats ->
            format

          format in @standard_formats ->
            # Standard formats not accepted for partial dates
            nil

          true ->
            # Derive format skeleton from available fields
            derive_format_id(date)
        end

      if resolved_format == nil do
        {:error,
         Localize.DateTimeUnresolvedFormatError.exception(
           format: format,
           locale: locale_id
         )}
      else
        with {:ok, pattern} <- find_format(date, resolved_format, locale_id, options),
             {:ok, formatted} <-
               Localize.DateTime.Formatter.format(date, pattern, locale_id, Map.new(options)) do
          {:ok, formatted}
        end
      end
    end
  end

  def to_string(_date, _options) do
    {:error, Localize.DateTimeInvalidInputError.exception(type: :date)}
  end

  @doc """
  Same as `to_string/2` but raises on error.

  ### Examples

      iex> Localize.Date.to_string!(~D[2017-07-10], locale: :en)
      "Jul 10, 2017"

      iex> Localize.Date.to_string!(%{year: 2024, month: 6}, format: :yMMM, locale: :fr)
      "juin 2024"

  """
  @spec to_string!(map(), Keyword.t()) :: String.t()
  def to_string!(date, options \\ []) do
    case to_string(date, options) do
      {:ok, string} -> string
      {:error, exception} -> raise exception
    end
  end

  # ── Format resolution ──────────────────────────────────────

  defp find_format(_date, format, _locale_id, _options) when is_binary(format) do
    {:ok, format}
  end

  defp find_format(date, format, locale_id, options) when is_atom(format) do
    # For standard formats on full dates, resolve via the standard format map
    if format in @standard_formats and is_full_date(date) do
      Localize.DateTime.Format.resolve_format(:date, format, locale_id, :gregorian, options)
    else
      # Skeleton format — look up in available_formats
      resolve_skeleton(format, locale_id, options)
    end
  end

  defp find_format(_date, format, _locale_id, _options) do
    {:error, Localize.DateTimeFormatError.exception(format: format, reason: :invalid_format)}
  end

  defp resolve_skeleton(skeleton, locale_id, options) when is_atom(skeleton) do
    prefer = Keyword.get(options, :prefer, :unicode)

    with {:ok, available} <-
           Localize.DateTime.Format.available_formats(locale_id, :gregorian) do
      case Map.get(available, skeleton) do
        nil ->
          # Try best match
          case Localize.DateTime.Format.Match.best_match(skeleton, locale_id) do
            {:ok, matched_id} when is_atom(matched_id) ->
              resolve_skeleton(matched_id, locale_id, options)

            {:ok, {_date_id, _time_id}} ->
              # Combined date+time skeleton — not applicable for date-only formatting
              {:error,
               Localize.DateTimeUnresolvedFormatError.exception(
                 format: skeleton,
                 locale: locale_id
               )}

            {:error, _} = error ->
              error
          end

        %{} = variant_map ->
          case resolve_variant(variant_map, prefer) do
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

  defp resolve_variant(%{} = variant_map, prefer) do
    cond do
      Map.has_key?(variant_map, :unicode) or Map.has_key?(variant_map, :ascii) ->
        Map.get(variant_map, prefer) || Map.get(variant_map, :unicode) ||
          Map.get(variant_map, :ascii)

      # CLDR plural-keyed variant — fall back to `:other`.
      Map.has_key?(variant_map, :other) ->
        Map.get(variant_map, :other)

      true ->
        nil
    end
  end

  @doc false
  def derive_format_id(date) do
    @date_fields_ordered
    |> Enum.filter(fn {field, _symbol} -> Map.has_key?(date, field) end)
    |> Enum.map(fn {_field, symbol} -> symbol end)
    |> Enum.join()
    |> String.to_atom()
  end

  # ── Locale resolution ──────────────────────────────────────

  defp resolve_locale_id(locale), do: Localize.Locale.cldr_locale_id_from(locale)
end
