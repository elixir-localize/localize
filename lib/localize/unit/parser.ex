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
    cap = max_unit_bytes()

    cond do
      byte_size(input) > cap ->
        {:error,
         Localize.ParseError.exception(
           reason: :input_too_large,
           detail: "unit identifier",
           size: byte_size(input),
           limit: cap
         )}

      custom_unit_name?(input) ->
        {:ok, custom_unit_ast(String.trim(input))}

      true ->
        do_parse(input)
    end
  end

  # A runtime-registered custom unit name matches wholesale before
  # the grammar runs: hyphenated custom names ("double-cubit") would
  # otherwise be split at the hyphens, which the grammar treats as
  # the compound product operator. Standard hyphenated identifiers
  # ("g-force", "kilowatt-hour") are compiled into the grammar's
  # base-unit alternation and take the normal path. The AST shape is
  # exactly what the grammar produces for a bare custom base.
  defp custom_unit_name?(input) do
    Localize.Unit.CustomRegistry.registered?(String.trim(input))
  end

  defp custom_unit_ast(name) do
    {:unit,
     [
       type: nil,
       numerator: [{:single_unit, [prefix: nil, power: nil, base: name]}],
       denominator: []
     ]}
  end

  # Maximum byte length accepted by `parse/1`/`parse!/1`. Caps the
  # parser's CPU exposure on hostile input. Override with
  # `config :localize, :max_unit_bytes, n` (default 256 — even a
  # heavily-compounded `meter-per-second-per-second-per-…` fits well
  # under this).
  @default_max_unit_bytes 256

  @doc false
  def max_unit_bytes do
    Application.get_env(:localize, :max_unit_bytes, @default_max_unit_bytes)
  end

  defp do_parse(input) do
    case unit_identifier(input) do
      {:ok, [result], "", _, _, _} ->
        {:ok, result}

      {:ok, _result, rest, _, _, offset} ->
        {:error,
         Localize.ParseError.exception(
           input: input,
           reason: :unexpected_trailing_input,
           offset: offset,
           rest: rest
         )}

      {:error, detail, rest, _, _, offset} ->
        {:error,
         Localize.ParseError.exception(
           input: input,
           reason: :unexpected_input,
           detail: detail,
           offset: offset,
           rest: rest
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
  #
  # SI-prefixed custom units are tried before bare custom units but are
  # guarded by a post_traverse that validates the base (after stripping
  # the prefix) is actually a registered custom unit. This prevents
  # greedy consumption of the full name when an SI prefix happens to
  # appear at the start (e.g., "decathlon" won't be split into
  # "deca" + "thlon").
  single_unit_v =
    choice([
      parsec(:currency_unit_p),
      optional(power_prefix())
      |> choice([
        parsec(:base_unit_p),
        parsec(:si_prefix_p) |> concat(parsec(:base_unit_p)),
        parsec(:si_prefix_p)
        |> concat(parsec(:custom_base_unit_p))
        |> post_traverse(:validate_prefixed_custom_unit),
        parsec(:custom_base_unit_p)
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

  @doc """
  Parses the given `binary` as a CLDR unit identifier, returning the
  raw NimbleParsec result tuple.

  This is the low-level parsec entry point. Most callers should use
  `parse/1`, which unwraps the result and returns tagged
  `{:ok, ast}` / `{:error, exception}` tuples.

  ### Arguments

  * `binary` is a unit identifier string such as `"meter"`.

  * `opts` is a keyword list of NimbleParsec options (`:byte_offset`,
    `:line`, and `:context`).

  ### Returns

  * `{:ok, [token], rest, context, position, byte_offset}` on success.

  * `{:error, reason, rest, context, line, byte_offset}` on failure.

  ### Examples

      iex> Localize.Unit.Parser.unit_identifier("meter")
      {:ok, [unit: [type: nil, numerator: [single_unit: [prefix: nil, power: nil, base: "meter"]], denominator: []]], "", %{}, {1, 0}, 5}

  """
  defparsec(:unit_identifier, unit_identifier_v)

  # parsec:Localize.Unit.Parser
end
