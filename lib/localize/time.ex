defmodule Localize.Time do
  @moduledoc """
  Provides localized formatting of `Time` structs and time-like maps.

  Formats are defined in CLDR and described in
  [TR35](http://unicode.org/reports/tr35/tr35-dates.html).

  """

  import Kernel, except: [to_string: 1]

  @default_format :medium

  @doc """
  Formats a time according to a CLDR format pattern.

  ### Arguments

  * `time` is a `t:Time.t/0` or any map with `:hour`, `:minute`,
    `:second` keys.

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

  * `{:error, exception}` if the time cannot be formatted.

  ### Examples

      iex> Localize.Time.to_string(~T[14:30:00], locale: :en, prefer: :ascii)
      {:ok, "2:30:00 PM"}

      iex> Localize.Time.to_string(~T[14:30:00], format: :short, locale: :en, prefer: :ascii)
      {:ok, "2:30 PM"}

  """
  @spec to_string(map(), Keyword.t()) :: {:ok, String.t()} | {:error, Exception.t()}
  def to_string(time, options \\ [])

  def to_string(%{hour: _, minute: _} = time, options) do
    locale = Keyword.get(options, :locale, :en)
    format = Keyword.get(options, :format, @default_format)

    with {:ok, locale_id} <- resolve_locale_id(locale),
         {:ok, pattern} <- resolve_format(format, locale_id, options),
         {:ok, formatted} <-
           Localize.DateTime.Formatter.format(time, pattern, locale_id, Map.new(options)) do
      {:ok, formatted}
    end
  end

  def to_string(_time, _options) do
    {:error,
     Localize.DateTimeFormatError.exception(
       format: nil,
       reason: "time must have :hour and :minute keys"
     )}
  end

  @doc """
  Same as `to_string/2` but raises on error.

  """
  @spec to_string!(map(), Keyword.t()) :: String.t()
  def to_string!(time, options \\ []) do
    case to_string(time, options) do
      {:ok, string} -> string
      {:error, exception} -> raise exception
    end
  end

  defp resolve_format(format, _locale_id, _options) when is_binary(format) do
    {:ok, format}
  end

  defp resolve_format(format, locale_id, options) when is_atom(format) do
    Localize.DateTime.Format.resolve_format(:time, format, locale_id, :gregorian, options)
  end

  defp resolve_locale_id(%Localize.LanguageTag{cldr_locale_id: id}), do: {:ok, id}

  defp resolve_locale_id(locale) when is_atom(locale) or is_binary(locale) do
    case Localize.validate_locale(locale) do
      {:ok, tag} -> {:ok, tag.cldr_locale_id}
      error -> error
    end
  end
end
