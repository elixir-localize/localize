defmodule Localize.Utils.Math do
  @moduledoc """
  Mathematical helper functions used by the plural rules
  compiler and other Localize subsystems.

  Provides modulo, range membership, power-of-10 computation,
  and Decimal-to-float conversion functions required by the
  CLDR plural rules specification.

  """

  @default_rounding 3

  @doc """
  Returns the default number of rounding digits.

  ### Returns

  * An integer (`#{@default_rounding}`).

  ### Examples

      iex> Localize.Utils.Math.default_rounding()
      3

  """
  @spec default_rounding :: pos_integer()
  def default_rounding do
    @default_rounding
  end

  @doc """
  Check if a `number` is within a `range`.

  For integers the comparison uses the standard `in` operator.
  For floats the comparison checks that the float has no
  fractional part and falls within the range endpoints.

  ### Arguments

  * `number` is an integer or float.

  * `range` is an Elixir `Range`.

  ### Returns

  * `true` if the number is within the range.

  * `false` otherwise.

  ### Examples

      iex> Localize.Utils.Math.within(2, 1..3)
      true

      iex> Localize.Utils.Math.within(2.0, 1..3)
      true

      iex> Localize.Utils.Math.within(2.1, 1..3)
      false

  """
  @spec within(number(), Range.t()) :: boolean()
  def within(number, range) when is_integer(number) do
    number in range
  end

  def within(number, %{first: first, last: last}) when is_float(number) do
    number == trunc(number) && number >= first && number <= last
  end

  @doc """
  Calculates the modulo of a number (integer, float, or Decimal).

  Uses floored division rather than truncated division. This
  matches the semantics required by the CLDR plural rules
  specification.

  ### Arguments

  * `number` is an integer, float, or Decimal.

  * `modulus` is an integer, float, or Decimal.

  ### Returns

  * The modulo result in the same type as the input.

  ### Examples

      iex> Localize.Utils.Math.mod(1234.0, 5)
      4.0

      iex> Localize.Utils.Math.mod(7, 3)
      1

  """
  @spec mod(number() | Decimal.t(), number() | Decimal.t()) :: number() | Decimal.t()
  def mod(number, modulus) when is_float(number) and is_number(modulus) do
    number - Float.floor(number / modulus) * modulus
  end

  def mod(number, modulus) when is_integer(number) and is_integer(modulus) do
    modulo =
      number
      |> Integer.floor_div(modulus)
      |> Kernel.*(modulus)

    number - modulo
  end

  def mod(number, modulus) when is_integer(number) and is_number(modulus) do
    modulo =
      number
      |> Kernel./(modulus)
      |> Float.floor()
      |> Kernel.*(modulus)

    number - modulo
  end

  def mod(%Decimal{} = number, %Decimal{} = modulus) do
    modulo =
      number
      |> Decimal.div(modulus)
      |> Decimal.round(0, :floor)
      |> Decimal.mult(modulus)

    Decimal.sub(number, modulo)
  end

  def mod(%Decimal{} = number, modulus) when is_integer(modulus) do
    mod(number, Decimal.new(modulus))
  end

  def mod(%Decimal{} = number, modulus) when is_float(modulus) do
    mod(number, Decimal.from_float(modulus))
  end

  @doc """
  Convert a Decimal to a float.

  Note that this conversion may lose precision for numbers
  that cannot be exactly represented as IEEE 754 floats.

  ### Arguments

  * `decimal` is a `%Decimal{}` struct.

  ### Returns

  * A float value.

  ### Examples

      iex> Localize.Utils.Math.to_float(Decimal.new("1.5"))
      1.5

  """
  @spec to_float(Decimal.t()) :: float()
  def to_float(%Decimal{sign: sign, coef: coef, exp: exp}) do
    sign * coef * 1.0 * power_of_10(exp)
  end

  @doc """
  Returns 10 raised to the given power.

  Powers 0 through 326 are precomputed for efficiency.
  Negative powers return the reciprocal.

  ### Arguments

  * `n` is an integer exponent.

  ### Returns

  * An integer for non-negative exponents.

  * A float for negative exponents.

  ### Examples

      iex> Localize.Utils.Math.power_of_10(0)
      1

      iex> Localize.Utils.Math.power_of_10(3)
      1000

      iex> Localize.Utils.Math.power_of_10(-1)
      0.1

  """
  @spec power_of_10(integer()) :: number()
  Enum.reduce(0..326, 1, fn x, acc ->
    def power_of_10(unquote(x)), do: unquote(acc)
    acc * 10
  end)

  def power_of_10(n) when n < 0 do
    1 / power_of_10(abs(n))
  end
end
