defmodule Localize.Utils.Decimal do
  # Compatibility layer for `Decimal` library operations.
  #
  # Provides normalized function signatures for common `Decimal`
  # operations used throughout Localize.
  #
  @moduledoc false

  @doc """
  Normalizes a `Decimal` value by removing trailing zeros from the coefficient.

  ### Arguments

  * `decimal` — a `Decimal.t()` value to normalize.

  ### Returns

  * A normalized `Decimal.t()`.

  ### Examples

      iex> Localize.Utils.Decimal.reduce(Decimal.new("1.20"))
      Decimal.new("1.2")

  """
  @spec reduce(Decimal.t()) :: Decimal.t()
  def reduce(decimal) do
    Decimal.normalize(decimal)
  end

  @doc """
  Compares two `Decimal` values.

  ### Arguments

  * `decimal_1` — a `Decimal.t()` value.

  * `decimal_2` — a `Decimal.t()` value.

  ### Returns

  * `:lt` if `decimal_1` is less than `decimal_2`.

  * `:eq` if they are equal.

  * `:gt` if `decimal_1` is greater than `decimal_2`.

  ### Examples

      iex> Localize.Utils.Decimal.compare(Decimal.new("1.0"), Decimal.new("2.0"))
      :lt

  """
  @spec compare(Decimal.t(), Decimal.t()) :: :eq | :lt | :gt
  def compare(decimal_1, decimal_2) do
    Decimal.compare(decimal_1, decimal_2)
  end

  @doc """
  Parses a string into a `Decimal` value.

  ### Arguments

  * `string` — a string representation of a number.

  ### Returns

  * `{decimal, ""}` if the string was successfully parsed.

  * `{:error, string}` if the string could not be parsed.

  ### Examples

      iex> Localize.Utils.Decimal.parse("3.14")
      {Decimal.new("3.14"), ""}

      iex> Localize.Utils.Decimal.parse("not_a_number")
      {:error, "not_a_number"}

  """
  @spec parse(String.t()) :: {Decimal.t(), String.t()} | {:error, String.t()}
  def parse(string) do
    case Decimal.parse(string) do
      {decimal, ""} -> {decimal, ""}
      _other -> {:error, string}
    end
  end
end
