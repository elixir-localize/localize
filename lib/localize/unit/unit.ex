defmodule Localize.Unit do
  @moduledoc """
  Represents a CLDR unit of measure with its parsed structure.

  A `Localize.Unit` struct holds the original unit name string,
  its parsed AST representation, and an optional numeric value.

  """

  defstruct [
    :name,
    :parsed,
    :value
  ]

  @type t :: %__MODULE__{
          name: String.t(),
          parsed: tuple(),
          value: number() | Decimal.t() | nil
        }

  @doc """
  Creates a new unit with a value and a CLDR unit identifier string.

  ### Arguments

  * `amount` is the numeric value (integer, float, or Decimal).

  * `unit` is a unit identifier string such as `"meter-per-second"`.

  ### Returns

  * `{:ok, unit}` where `unit` is a `%Localize.Unit{}` struct, or

  * `{:error, reason}` if the value is not a valid number or
    the identifier cannot be parsed.

  ### Examples

      iex> {:ok, unit} = Localize.Unit.new(100, "meter")
      iex> unit.value
      100
      iex> unit.name
      "meter"

      iex> {:ok, unit} = Localize.Unit.new(Decimal.new("3.14"), "kilogram")
      iex> unit.value
      Decimal.new("3.14")

  """
  @spec new(number() | Decimal.t(), String.t()) :: {:ok, t()} | {:error, String.t()}

  def new(amount, unit) when is_binary(unit) do
    with {:ok, _} <- validate_value(amount),
         {:ok, parsed} <- Localize.Unit.Parser.parse(unit) do
      {:ok, %__MODULE__{name: unit, parsed: parsed, value: amount}}
    end
  end

  @doc """
  Creates a new unit from a CLDR unit identifier string without a value.

  ### Arguments

  * `name` is a unit identifier string such as `"meter-per-second"`.

  ### Returns

  * `{:ok, unit}` where `unit` is a `%Localize.Unit{}` struct, or

  * `{:error, reason}` if the identifier cannot be parsed.

  ### Examples

      iex> {:ok, unit} = Localize.Unit.new("meter")
      iex> unit.name
      "meter"

  """
  @spec new(String.t()) :: {:ok, t()} | {:error, String.t()}

  def new(name) when is_binary(name) do
    case Localize.Unit.Parser.parse(name) do
      {:ok, parsed} -> {:ok, %__MODULE__{name: name, parsed: parsed}}
      {:error, _} = error -> error
    end
  end

  @doc """
  Creates a new unit with a value and a CLDR unit identifier string,
  raising on error.

  Same as `new/2` but returns the struct directly or raises
  `ArgumentError`.

  ### Arguments

  * `amount` is the numeric value (integer, float, or Decimal).

  * `unit` is a unit identifier string.

  ### Returns

  * A `%Localize.Unit{}` struct.

  ### Examples

      iex> unit = Localize.Unit.new!(42, "kilogram")
      iex> unit.value
      42

  """
  @spec new!(number() | Decimal.t(), String.t()) :: t() | no_return()

  def new!(amount, unit) when is_binary(unit) do
    case new(amount, unit) do
      {:ok, result} -> result
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  @doc """
  Creates a new unit from a CLDR unit identifier string, raising on error.

  Same as `new/1` but returns the struct directly or raises
  `ArgumentError`.

  ### Arguments

  * `name` is a unit identifier string.

  ### Returns

  * A `%Localize.Unit{}` struct.

  ### Examples

      iex> unit = Localize.Unit.new!("meter")
      iex> unit.name
      "meter"

  """
  @spec new!(String.t()) :: t() | no_return()

  def new!(name) when is_binary(name) do
    case new(name) do
      {:ok, unit} -> unit
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  # ── Private ─────────────────────────────────────────────────────────

  defp validate_value(value) when is_integer(value), do: {:ok, value}
  defp validate_value(value) when is_float(value), do: {:ok, value}

  defp validate_value(%Decimal{} = value), do: {:ok, value}

  defp validate_value(value) do
    {:error, "Expected a number (integer, float, or Decimal), got: #{inspect(value)}"}
  end
end
