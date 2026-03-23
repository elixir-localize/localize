defmodule Localize.DateTime do
  @moduledoc """
  Provides localized formatting of `DateTime`, `NaiveDateTime`,
  and datetime-like maps.

  The primary function is `to_string/2` which accepts a datetime
  value and an options keyword list. Format patterns are defined
  in CLDR and described in
  [TR35](http://unicode.org/reports/tr35/tr35-dates.html).

  ## Predefined formats

  * `:short` — abbreviated date and time (e.g., "1/2/25, 3:04 PM").

  * `:medium` — standard date and time (default).

  * `:long` — includes time zone name.

  * `:full` — verbose day-of-week, date, and time zone.

  Custom CLDR skeleton strings and raw format patterns are also
  supported via the `:format` option.

  """

  import Kernel, except: [to_string: 1]

  @default_format :medium
  @standard_formats [:short, :medium, :long, :full]

  @doc """
  Formats a datetime according to a CLDR format pattern.

  ### Arguments

  * `datetime` is a `t:DateTime.t/0`, `t:NaiveDateTime.t/0`,
    or any map with date and time keys.

  * `options` is a keyword list of options.

  ### Options

  * `:format` is a standard format name (`:short`, `:medium`,
    `:long`, `:full`) or a format pattern string. The default
    is `:medium`.

  * `:locale` is a locale identifier. The default is `:en`.

  * `:prefer` is `:unicode` or `:ascii` for variant selection.
    The default is `:unicode`.

  ### Returns

  * `{:ok, formatted_string}` on success.

  * `{:error, exception}` if the datetime cannot be formatted.

  ### Examples

      iex> Localize.DateTime.to_string(~N[2017-07-10 14:30:00], locale: :en, prefer: :ascii)
      {:ok, "Jul 10, 2017, 2:30:00 PM"}

      iex> Localize.DateTime.to_string(~N[2017-07-10 14:30:00], format: :short, locale: :en, prefer: :ascii)
      {:ok, "7/10/17, 2:30 PM"}

  """
  @spec to_string(map(), Keyword.t()) :: {:ok, String.t()} | {:error, Exception.t()}
  def to_string(datetime, options \\ [])

  def to_string(%{year: _, month: _, day: _, hour: _, minute: _} = datetime, options) do
    locale = Keyword.get(options, :locale, Localize.get_locale())
    format = Keyword.get(options, :format, @default_format)
    style = Keyword.get(options, :style, :default)

    with {:ok, locale_id} <- resolve_locale_id(locale) do
      cond do
        # Explicit pattern string — format directly
        is_binary(format) ->
          Localize.DateTime.Formatter.format(datetime, format, locale_id, Map.new(options))

        # Standard format with separate date/time formats — use wrapper
        format in @standard_formats or
            (Keyword.has_key?(options, :date_format) and
               Keyword.has_key?(options, :time_format)) ->
          format_with_wrapper(datetime, options, locale_id, format, style)

        # Skeleton atom — resolve to a pattern from available_formats
        is_atom(format) ->
          format_with_skeleton(datetime, options, locale_id, format)
      end
    end
  end

  def to_string(datetime, options) when is_map(datetime) do
    # Try as date-only or time-only
    cond do
      Map.has_key?(datetime, :year) and Map.has_key?(datetime, :month) ->
        Localize.Date.to_string(datetime, options)

      Map.has_key?(datetime, :hour) ->
        Localize.Time.to_string(datetime, options)

      true ->
        {:error,
         Localize.DateTimeFormatError.exception(
           format: nil,
           reason: "datetime must have date and/or time keys"
         )}
    end
  end

  @doc """
  Same as `to_string/2` but raises on error.

  """
  @spec to_string!(map(), Keyword.t()) :: String.t()
  def to_string!(datetime, options \\ []) do
    case to_string(datetime, options) do
      {:ok, string} -> string
      {:error, exception} -> raise exception
    end
  end

  defp format_with_wrapper(datetime, options, locale_id, format, style) do
    date_format = Keyword.get(options, :date_format, format)
    time_format = Keyword.get(options, :time_format, format)

    # The wrapper style should match the date format level
    # (e.g., full date + short time → use full wrapper)
    wrapper_format =
      if Keyword.has_key?(options, :date_format),
        do: date_format,
        else: format

    options_map =
      options
      |> Map.new()
      |> Map.put(:date_format, date_format)
      |> Map.put(:time_format, time_format)

    with {:ok, wrapper} <- resolve_wrapper(wrapper_format, locale_id, style) do
      Localize.DateTime.Formatter.format(datetime, wrapper, locale_id, options_map)
    end
  end

  defp format_with_skeleton(datetime, options, locale_id, skeleton) do
    prefer = Keyword.get(options, :prefer, :unicode)

    with {:ok, available} <- Localize.DateTime.Format.available_formats(locale_id) do
      case Map.get(available, skeleton) do
        nil ->
          # Try best-match algorithm for skeletons not found exactly
          case Localize.DateTime.Format.Match.best_match(skeleton, locale_id) do
            {:ok, matched_skeleton} when is_atom(matched_skeleton) ->
              case Map.get(available, matched_skeleton) do
                nil ->
                  {:error,
                   Localize.DateTimeUnresolvedFormatError.exception(
                     format: skeleton,
                     locale: locale_id
                   )}

                matched_pattern ->
                  pattern = resolve_prefer(matched_pattern, prefer)

                  Localize.DateTime.Formatter.format(
                    datetime,
                    pattern,
                    locale_id,
                    Map.new(options)
                  )
              end

            {:ok, {date_skeleton, time_skeleton}} ->
              date_pattern = resolve_prefer(Map.get(available, date_skeleton, ""), prefer)
              time_pattern = resolve_prefer(Map.get(available, time_skeleton, ""), prefer)

              options_map =
                options
                |> Map.new()
                |> Map.put(:date_format, :medium)
                |> Map.put(:time_format, :medium)

              with {:ok, wrapper} <- resolve_wrapper(:medium, locale_id, :default) do
                combined = String.replace(wrapper, "{0}", time_pattern)
                combined = String.replace(combined, "{1}", date_pattern)
                Localize.DateTime.Formatter.format(datetime, combined, locale_id, options_map)
              end

            _ ->
              {:error,
               Localize.DateTimeUnresolvedFormatError.exception(
                 format: skeleton,
                 locale: locale_id
               )}
          end

        %{} = variant_map ->
          pattern = Map.get(variant_map, prefer) || Map.get(variant_map, :unicode)
          Localize.DateTime.Formatter.format(datetime, pattern, locale_id, Map.new(options))

        pattern when is_binary(pattern) ->
          Localize.DateTime.Formatter.format(datetime, pattern, locale_id, Map.new(options))
      end
    end
  end

  defp resolve_prefer(%{} = variant_map, prefer) do
    Map.get(variant_map, prefer) || Map.get(variant_map, :unicode)
  end

  defp resolve_prefer(pattern, _prefer) when is_binary(pattern), do: pattern

  defp resolve_wrapper(format, locale_id, style) do
    standard_format = if is_atom(format), do: format, else: :medium

    case style do
      :at ->
        # Use at-style format (e.g., "{1} 'at' {0}")
        with {:ok, at_formats} <-
               Localize.DateTime.Format.date_time_at_formats(locale_id) do
          pattern =
            get_in(at_formats, [:standard, standard_format]) ||
              fallback_wrapper(standard_format, locale_id)

          {:ok, pattern}
        else
          _ -> {:ok, fallback_wrapper(standard_format, locale_id)}
        end

      _ ->
        # Use standard wrapper format (e.g., "{1}, {0}")
        {:ok, fallback_wrapper(standard_format, locale_id)}
    end
  end

  defp fallback_wrapper(standard_format, locale_id) do
    case Localize.DateTime.Format.date_time_formats(locale_id) do
      {:ok, dt_formats} -> Map.get(dt_formats, standard_format, "{1}, {0}")
      _ -> "{1}, {0}"
    end
  end

  defp resolve_locale_id(%Localize.LanguageTag{cldr_locale_id: id}), do: {:ok, id}

  defp resolve_locale_id(locale) when is_atom(locale) or is_binary(locale) do
    case Localize.validate_locale(locale) do
      {:ok, tag} -> {:ok, tag.cldr_locale_id}
      error -> error
    end
  end
end
