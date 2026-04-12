defmodule Localize.Unit.Parser do
  @moduledoc """
  Parses CLDR Unit of Measure identifier strings into structured ASTs.

  Implements the unit identifier syntax defined in
  [Unicode TR35](https://www.unicode.org/reports/tr35/tr35-general.html#unit-syntax).

  """

  import Localize.Unit.Parser.Helpers

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
  @spec parse(String.t()) :: {:ok, tuple()} | {:error, Exception.t()}

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
  @spec parse!(String.t()) :: {atom(), keyword()} | no_return()
  @dialyzer {:nowarn_function, parse!: 1}

  def parse!(input) when is_binary(input) do
    case parse(input) do
      {:ok, parsed} -> parsed
      {:error, exception} -> raise exception
    end
  end

  # parsec:Localize.Unit.Parser

  import NimbleParsec

  import Localize.Unit.Parser.Combinator,
    except: [
      wrap_pow: 1,
      wrap_constant: 1,
      wrap_currency_unit: 1,
      wrap_single_unit: 1,
      wrap_per_leading: 1,
      wrap_core_unit: 1,
      wrap_long_unit: 1,
      wrap_mixed_unit: 1
    ]

  # Break out the two largest choice lists as defparsecp
  # so they compile once instead of being inlined at every call site.
  defparsecp(:base_unit_p, base_unit())
  defparsecp(:si_prefix_p, si_prefix())
  defparsecp(:currency_unit_p, currency_unit())
  defparsecp(:custom_base_unit_p, custom_base_unit())

  # Rebuild single_unit to reference the defparsecp versions.
  # The custom_base_unit_p fallback accepts any lowercase identifier,
  # enabling custom unit names. A validation pass after parsing checks
  # that all base names resolve to known CLDR units or registered custom units.
  single_unit_v =
    choice([
      parsec(:currency_unit_p),
      optional(power_prefix())
      |> choice([
        parsec(:base_unit_p),
        parsec(:si_prefix_p) |> concat(parsec(:base_unit_p)),
        parsec(:custom_base_unit_p),
        parsec(:si_prefix_p) |> concat(parsec(:custom_base_unit_p))
      ])
      |> reduce(:wrap_single_unit),
      unit_constant()
    ])

  defparsecp(:single_unit_p, single_unit_v)

  product_unit_v =
    parsec(:single_unit_p)
    |> repeat(
      lookahead_not(string("-per-"))
      |> lookahead_not(string("-and-"))
      |> ignore(string("-"))
      |> concat(parsec(:single_unit_p))
    )
    |> tag(:product)

  defparsecp(:product_unit_p, product_unit_v)

  core_unit_v =
    choice([
      ignore(string("per-"))
      |> concat(parsec(:product_unit_p))
      |> repeat(ignore(string("-per-")) |> concat(parsec(:product_unit_p)))
      |> reduce(:wrap_per_leading),
      parsec(:product_unit_p)
      |> repeat(ignore(string("-per-")) |> concat(parsec(:product_unit_p)))
      |> reduce(:wrap_core_unit)
    ])

  long_unit_v =
    category()
    |> ignore(string("-"))
    |> concat(core_unit_v)
    |> reduce(:wrap_long_unit)

  mixed_unit_v =
    parsec(:single_unit_p)
    |> times(ignore(string("-and-")) |> concat(parsec(:single_unit_p)), min: 1)
    |> reduce(:wrap_mixed_unit)

  unit_identifier_v =
    choice([
      mixed_unit_v,
      core_unit_v,
      long_unit_v
    ])
    |> eos()

  defparsec(:unit_identifier, unit_identifier_v)

  # parsec:Localize.Unit.Parser
end
