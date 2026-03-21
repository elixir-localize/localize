defmodule Localize.Date do
  @moduledoc """
  Provides localized formatting of `Date` structs and date-like maps.

  Formats are defined in CLDR and described in
  [TR35](http://unicode.org/reports/tr35/tr35-dates.html).

  """

  import Kernel, except: [to_string: 1]

  @default_format :medium

  @doc """
  Formats a date according to a CLDR format pattern.

  ### Arguments

  * `date` is a `t:Date.t/0` or any map with `:year`, `:month`,
    `:day` keys.

  * `options` is a keyword list of options.

  ### Options

  * `:format` is a standard format name (`:short`, `:medium`,
    `:long`, `:full`), a format skeleton atom, or a format
    pattern string. The default is `:medium`.

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

  """
  @spec to_string(map(), Keyword.t()) :: {:ok, String.t()} | {:error, Exception.t()}
  def to_string(date, options \\ [])

  def to_string(%{year: _, month: _, day: _} = date, options) do
    locale = Keyword.get(options, :locale, :en)
    format = Keyword.get(options, :format, @default_format)

    with {:ok, locale_id} <- resolve_locale_id(locale),
         {:ok, pattern} <- resolve_format(format, locale_id, options),
         {:ok, formatted} <-
           Localize.DateTime.Formatter.format(date, pattern, locale_id, Map.new(options)) do
      {:ok, formatted}
    end
  end

  def to_string(_date, _options) do
    {:error,
     Localize.DateTimeFormatError.exception(
       format: nil,
       reason: "date must have :year, :month, and :day keys"
     )}
  end

  @doc """
  Same as `to_string/2` but raises on error.

  """
  @spec to_string!(map(), Keyword.t()) :: String.t()
  def to_string!(date, options \\ []) do
    case to_string(date, options) do
      {:ok, string} -> string
      {:error, exception} -> raise exception
    end
  end

  defp resolve_format(format, locale_id, options) when is_binary(format) do
    {:ok, format}
  end

  defp resolve_format(format, locale_id, options) when is_atom(format) do
    Localize.DateTime.Format.resolve_format(:date, format, locale_id, :gregorian, options)
  end

  defp resolve_locale_id(%Localize.LanguageTag{cldr_locale_id: id}), do: {:ok, id}

  defp resolve_locale_id(locale) when is_atom(locale) do
    Localize.validate_locale(locale)
    |> case do
      {:ok, tag} -> {:ok, tag.cldr_locale_id}
      error -> error
    end
  end

  defp resolve_locale_id(locale) when is_binary(locale) do
    Localize.validate_locale(locale)
    |> case do
      {:ok, tag} -> {:ok, tag.cldr_locale_id}
      error -> error
    end
  end
end
