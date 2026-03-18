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
          value: number() | nil
        }

  @doc """
  Creates a new unit from a CLDR unit identifier string.

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
end
