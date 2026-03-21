defmodule Localize.Number do
  @moduledoc """
  Functions for formatting numbers in a locale-aware manner.

  This module provides the primary public API for converting
  numbers to localized string representations, including
  standard decimal formatting, currency formatting, percentage
  formatting, and scientific notation.

  All formatting is driven by CLDR locale data accessed at
  runtime via the locale provider.

  """

  alias Localize.Number.Format.Options
  alias Localize.Number.Formatter

  @doc """
  Formats a number as a localized string.

  ### Arguments

  * `number` is an integer, float, or Decimal.

  * `options` is a keyword list of options.

  ### Options

  * `:locale` is a locale identifier atom, string, or a
    `t:Localize.LanguageTag.t/0`. The default is `:en`.

  * `:number_system` is a number system name or type atom.
    The default is `:default`.

  * `:format` is a format style atom or a format pattern string.
    The default is `:standard`. Common styles include `:standard`,
    `:currency`, `:accounting`, `:percent`, `:scientific`,
    `:decimal_short`, `:decimal_long`.

  * `:currency` is a currency code atom (e.g., `:USD`). When
    provided, currency formatting is applied.

  * `:rounding_mode` is one of `:down`, `:half_up`, `:half_even`,
    `:ceiling`, `:floor`, `:half_down`, `:up`. The default is
    `:half_even`.

  * `:fractional_digits` is an integer specifying the exact number
    of fractional digits to display.

  * `:maximum_integer_digits` is an integer specifying the maximum
    number of integer digits to display.

  * `:wrapper` is a function of arity 2 that wraps formatted
    components. Useful for adding HTML markup.

  ### Returns

  * `{:ok, formatted_string}` on success.

  * `{:error, exception}` if options are invalid or formatting fails.

  ### Examples

      iex> Localize.Number.to_string(1234)
      {:ok, "1,234"}

      iex> Localize.Number.to_string(1234.5, locale: :en)
      {:ok, "1,234.5"}

      iex> Localize.Number.to_string(0.56, format: :percent, locale: :en)
      {:ok, "56%"}

  """
  @spec to_string(number() | Decimal.t(), Keyword.t() | Options.t()) ::
          {:ok, String.t()} | {:error, Exception.t()}
  def to_string(number, options \\ [])

  def to_string(number, %Options{} = validated_options) do
    dispatch_format(number, validated_options)
  end

  def to_string(number, options) when is_list(options) do
    with {:ok, validated_options} <- Options.validate_options(number, options) do
      dispatch_format(number, validated_options)
    end
  end

  defp dispatch_format(number, validated_options) do
    format = validated_options.format

    cond do
      is_binary(format) ->
        Formatter.Decimal.to_string(number, format, validated_options)

      is_atom(format) and format in [:decimal_short, :decimal_long, :currency_short] ->
        Formatter.Short.to_string(number, format, validated_options)

      is_atom(format) and format in [:currency_long, :currency_long_with_symbol] ->
        Formatter.Currency.to_string(number, format, validated_options)

      true ->
        {:error,
         Localize.InvalidValueError.exception(
           value: format,
           expected: "a format string or known format style",
           context: "Localize.Number.to_string/2"
         )}
    end
  end

  @doc """
  Same as `to_string/2` but raises on error.

  ### Arguments

  * `number` is an integer, float, or Decimal.

  * `options` is a keyword list of options.

  ### Returns

  * A formatted string.

  ### Raises

  * Raises an exception if formatting fails.

  ### Examples

      iex> Localize.Number.to_string!(1234)
      "1,234"

  """
  @spec to_string!(number() | Decimal.t(), Keyword.t()) :: String.t()
  def to_string!(number, options \\ []) do
    case to_string(number, options) do
      {:ok, string} -> string
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Scans a string and returns a list of strings and numbers.

  Delegates to `Localize.Number.Parser.scan/2`.

  ### Arguments

  * `string` is any string.

  * `options` is a keyword list of options.

  ### Returns

  * A list of strings and numbers.

  """
  defdelegate scan(string, options \\ []), to: Localize.Number.Parser

  @doc """
  Parses a string to a number in a locale-aware manner.

  Delegates to `Localize.Number.Parser.parse/2`.

  ### Arguments

  * `string` is any string.

  * `options` is a keyword list of options.

  ### Returns

  * `{:ok, number}` or `{:error, exception}`.

  """
  defdelegate parse(string, options \\ []), to: Localize.Number.Parser

  @doc """
  Resolves currencies from strings within a list.

  Delegates to `Localize.Number.Parser.resolve_currencies/2`.

  """
  defdelegate resolve_currencies(list, options \\ []), to: Localize.Number.Parser

  @doc """
  Resolves a currency from a string.

  Delegates to `Localize.Number.Parser.resolve_currency/2`.

  """
  defdelegate resolve_currency(string, options \\ []), to: Localize.Number.Parser

  @doc """
  Resolves percent and permille symbols from strings within a list.

  Delegates to `Localize.Number.Parser.resolve_pers/2`.

  """
  defdelegate resolve_pers(list, options \\ []), to: Localize.Number.Parser

  @doc """
  Resolves percent or permille from a string.

  Delegates to `Localize.Number.Parser.resolve_per/2`.

  """
  defdelegate resolve_per(string, options \\ []), to: Localize.Number.Parser
end
