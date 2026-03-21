defmodule Localize.DateTime do
  @moduledoc """
  Provides localized formatting of `DateTime`, `NaiveDateTime`,
  and datetime-like maps.

  Formats are defined in CLDR and described in
  [TR35](http://unicode.org/reports/tr35/tr35-dates.html).

  """

  import Kernel, except: [to_string: 1]

  @default_format :medium

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
    locale = Keyword.get(options, :locale, :en)
    format = Keyword.get(options, :format, @default_format)
    date_format = Keyword.get(options, :date_format, format)
    time_format = Keyword.get(options, :time_format, format)

    with {:ok, locale_id} <- resolve_locale_id(locale),
         {:ok, wrapper} <- resolve_wrapper(format, locale_id),
         {:ok, date_pattern} <- resolve_date_format(date_format, locale_id, options),
         {:ok, time_pattern} <- resolve_time_format(time_format, locale_id, options),
         {:ok, date_str} <-
           Localize.DateTime.Formatter.format(datetime, date_pattern, locale_id, Map.new(options)),
         {:ok, time_str} <-
           Localize.DateTime.Formatter.format(datetime, time_pattern, locale_id, Map.new(options)) do
      # Substitute into the wrapper pattern: {1} = date, {0} = time
      result =
        wrapper
        |> String.replace("{1}", date_str)
        |> String.replace("{0}", time_str)

      {:ok, result}
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

  defp resolve_wrapper(format, locale_id) do
    standard_format = if is_atom(format), do: format, else: :medium

    with {:ok, dt_formats} <-
           Localize.DateTime.Format.date_time_formats(locale_id) do
      pattern = Map.get(dt_formats, standard_format, "{1}, {0}")
      {:ok, pattern}
    end
  end

  defp resolve_date_format(format, locale_id, options) when is_atom(format) do
    Localize.DateTime.Format.resolve_format(:date, format, locale_id, :gregorian, options)
  end

  defp resolve_date_format(format, _locale_id, _options) when is_binary(format) do
    {:ok, format}
  end

  defp resolve_time_format(format, locale_id, options) when is_atom(format) do
    Localize.DateTime.Format.resolve_format(:time, format, locale_id, :gregorian, options)
  end

  defp resolve_time_format(format, _locale_id, _options) when is_binary(format) do
    {:ok, format}
  end

  defp resolve_locale_id(%Localize.LanguageTag{cldr_locale_id: id}), do: {:ok, id}

  defp resolve_locale_id(locale) when is_atom(locale) or is_binary(locale) do
    case Localize.validate_locale(locale) do
      {:ok, tag} -> {:ok, tag.cldr_locale_id}
      error -> error
    end
  end
end
