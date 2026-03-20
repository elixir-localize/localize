defmodule Localize.Unit.Parser do
  @moduledoc """
  Parses CLDR Unit of Measure identifier strings into structured ASTs.

  Implements the unit identifier syntax defined in
  [Unicode TR35](https://www.unicode.org/reports/tr35/tr35-general.html#unit-syntax).

  """

  import NimbleParsec
  import Localize.Unit.Parser.Combinator

  defparsec(:unit_identifier, unit_identifier())

  @doc """
  Parses a CLDR unit identifier string.

  ### Arguments

  * `input` is a unit identifier string such as `"meter-per-second"` or
    `"length-kilometer"`.

  ### Returns

  * `{:ok, ast}` where `ast` is the parsed unit structure, or

  * `{:error, reason}` if the input cannot be parsed.

  ### Examples

      iex> Localize.Unit.Parser.parse("meter")
      {:ok, {:unit, type: nil, numerator: [{:single_unit, prefix: nil, power: nil, base: "meter"}], denominator: []}}

      iex> Localize.Unit.Parser.parse("meter-per-second")
      {:ok, {:unit, type: nil, numerator: [{:single_unit, prefix: nil, power: nil, base: "meter"}], denominator: [{:single_unit, prefix: nil, power: nil, base: "second"}]}}

  """
  @spec parse(String.t()) :: {:ok, tuple()} | {:error, String.t()}

  def parse(input) when is_binary(input) do
    case unit_identifier(input) do
      {:ok, [result], "", _, _, _} ->
        {:ok, result}

      {:ok, _result, rest, _, _, offset} ->
        {:error,
         Localize.ParseError.exception(
           input: input,
           reason:
             "Could not parse the remaining #{inspect(rest)} starting at position #{offset + 1}"
         )}

      {:error, reason, rest, _, _, offset} ->
        {:error,
         Localize.ParseError.exception(
           input: input,
           reason:
             "#{reason}. Could not parse the remaining #{inspect(rest)} at position #{offset + 1}"
         )}
    end
  end

  @doc """
  Parses a CLDR unit identifier string, raising on error.

  Same as `parse/1` but returns the AST directly or raises
  `ArgumentError`.

  ### Arguments

  * `input` is a unit identifier string.

  ### Returns

  * The parsed unit AST.

  ### Examples

      iex> Localize.Unit.Parser.parse!("meter")
      {:unit, type: nil, numerator: [{:single_unit, prefix: nil, power: nil, base: "meter"}], denominator: []}

  """
  @spec parse!(String.t()) :: tuple() | no_return()

  def parse!(input) when is_binary(input) do
    case parse(input) do
      {:ok, parsed} -> parsed
      {:error, %{__exception__: true} = exception} -> raise exception
    end
  end
end
