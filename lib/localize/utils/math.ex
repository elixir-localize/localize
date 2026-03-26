defmodule Localize.Utils.Math do
  @moduledoc """
  Mathematical helper functions for number formatting and
  Localize subsystems.

  Provides arithmetic operations (add, subtract, multiply, divide),
  modulo, rounding (to arbitrary precision with selectable rounding
  modes), logarithms, powers, roots, square roots, significant-digit
  rounding, coefficient/exponent decomposition, and float-to-rational
  conversion.

  All arithmetic operations accept integers, floats, and Decimals and
  return the most appropriate type.

  """

  import Kernel, except: [div: 2]
  alias Localize.Utils.Digits
  require Integer

  @type rounding ::
          :down
          | :half_up
          | :half_even
          | :ceiling
          | :floor
          | :half_down
          | :up

  @type number_or_decimal :: number | Decimal.t()
  @type normalised_decimal :: {%Decimal{}, integer}

  @default_rounding 3
  @default_rounding_mode :half_even
  @zero Decimal.new(0)
  @one Decimal.new(1)
  @two Decimal.new(2)
  @ten Decimal.new(10)

  @doc """
  Adds two numbers together.

  The numbers can be integers, floats, or Decimals.
  If either argument is a Decimal the result will be a Decimal.
  If both arguments are integers the result is an integer;
  if either is a float the result is a float.

  ### Arguments

  * `number_1` is an integer, float, or Decimal.

  * `number_2` is an integer, float, or Decimal.

  ### Returns

  * The sum of the two numbers.

  ### Examples

      iex> Localize.Utils.Math.add(1, 2)
      3

      iex> Localize.Utils.Math.add(Decimal.new("1.5"), 2)
      Decimal.new("3.5")

  """
  @spec add(number_or_decimal, number_or_decimal) :: number_or_decimal
  def add(%Decimal{} = number_1, %Decimal{} = number_2) do
    Decimal.add(number_1, number_2)
  end

  def add(%Decimal{} = number_1, number_2) when is_integer(number_2) do
    Decimal.add(number_1, number_2)
  end

  def add(%Decimal{} = number_1, number_2) when is_float(number_2) do
    Decimal.add(number_1, Decimal.from_float(number_2))
  end

  def add(number_1, %Decimal{} = number_2) when is_integer(number_1) do
    Decimal.add(number_1, number_2)
  end

  def add(number_1, %Decimal{} = number_2) when is_float(number_1) do
    Decimal.add(Decimal.from_float(number_1), number_2)
  end

  def add(number_1, number_2) when is_number(number_1) and is_number(number_2) do
    number_1 + number_2
  end

  @doc """
  Subtracts one number from another.

  The numbers can be integers, floats, or Decimals.
  If either argument is a Decimal the result will be a Decimal.
  If both arguments are integers the result is an integer;
  if either is a float the result is a float.

  ### Arguments

  * `number_1` is an integer, float, or Decimal.

  * `number_2` is an integer, float, or Decimal.

  ### Returns

  * The difference of the two numbers.

  ### Examples

      iex> Localize.Utils.Math.sub(5, 3)
      2

      iex> Localize.Utils.Math.sub(Decimal.new("5.5"), 3)
      Decimal.new("2.5")

  """
  @spec sub(number_or_decimal, number_or_decimal) :: number_or_decimal
  def sub(%Decimal{} = number_1, %Decimal{} = number_2) do
    Decimal.sub(number_1, number_2)
  end

  def sub(%Decimal{} = number_1, number_2) when is_integer(number_2) do
    Decimal.sub(number_1, number_2)
  end

  def sub(%Decimal{} = number_1, number_2) when is_float(number_2) do
    Decimal.sub(number_1, Decimal.from_float(number_2))
  end

  def sub(number_1, %Decimal{} = number_2) when is_integer(number_1) do
    Decimal.sub(number_1, number_2)
  end

  def sub(number_1, %Decimal{} = number_2) when is_float(number_1) do
    Decimal.sub(Decimal.from_float(number_1), number_2)
  end

  def sub(number_1, number_2) when is_number(number_1) and is_number(number_2) do
    number_1 - number_2
  end

  @doc """
  Multiplies two numbers together.

  The numbers can be integers, floats, or Decimals.
  If either argument is a Decimal the result will be a Decimal.
  If both arguments are integers the result is an integer;
  if either is a float the result is a float.

  ### Arguments

  * `number_1` is an integer, float, or Decimal.

  * `number_2` is an integer, float, or Decimal.

  ### Returns

  * The product of the two numbers.

  ### Examples

      iex> Localize.Utils.Math.mult(3, 4)
      12

      iex> Localize.Utils.Math.mult(Decimal.new("1.5"), 2)
      Decimal.new("3.0")

  """
  @spec mult(number_or_decimal, number_or_decimal) :: number_or_decimal
  def mult(%Decimal{} = number_1, %Decimal{} = number_2) do
    Decimal.mult(number_1, number_2)
  end

  def mult(%Decimal{} = number_1, number_2) when is_integer(number_2) do
    Decimal.mult(number_1, number_2)
  end

  def mult(%Decimal{} = number_1, number_2) when is_float(number_2) do
    Decimal.mult(number_1, Decimal.from_float(number_2))
  end

  def mult(number_1, %Decimal{} = number_2) when is_integer(number_1) do
    Decimal.mult(number_1, number_2)
  end

  def mult(number_1, %Decimal{} = number_2) when is_float(number_1) do
    Decimal.mult(Decimal.from_float(number_1), number_2)
  end

  def mult(number_1, number_2) when is_number(number_1) and is_number(number_2) do
    number_1 * number_2
  end

  @doc """
  Divides one number by another.

  The numbers can be integers, floats, or Decimals.
  If either argument is a Decimal the result will be a Decimal.
  If both arguments are plain numbers the result will be a Decimal.

  ### Arguments

  * `number_1` is an integer, float, or Decimal.

  * `number_2` is an integer, float, or Decimal.

  ### Returns

  * The quotient of the two numbers as a Decimal.

  ### Examples

      iex> Localize.Utils.Math.div(Decimal.new(10), 2)
      Decimal.new("5")

  """
  @spec div(number_or_decimal, number_or_decimal) :: Decimal.t()
  def div(%Decimal{} = number_1, %Decimal{} = number_2) do
    Decimal.div(number_1, number_2)
  end

  def div(%Decimal{} = number_1, number_2) when is_integer(number_2) do
    Decimal.div(number_1, number_2)
  end

  def div(%Decimal{} = number_1, number_2) when is_float(number_2) do
    Decimal.div(number_1, Decimal.from_float(number_2))
  end

  def div(number_1, %Decimal{} = number_2) when is_integer(number_1) do
    Decimal.div(number_1, number_2)
  end

  def div(number_1, %Decimal{} = number_2) when is_float(number_1) do
    Decimal.div(Decimal.from_float(number_1), number_2)
  end

  def div(number_1, number_2) when is_number(number_1) and is_number(number_2) do
    Decimal.from_float(number_1 / number_2)
  end

  @doc """
  Converts a Decimal to an integer if possible, otherwise returns
  the value unchanged.

  ### Arguments

  * `number` is a Decimal, float, or integer.

  ### Returns

  * An integer if the number has no fractional part.

  * The original value otherwise.

  ### Examples

      iex> Localize.Utils.Math.maybe_integer(Decimal.new("3.0"))
      3

      iex> Localize.Utils.Math.maybe_integer(2.0)
      2

      iex> Localize.Utils.Math.maybe_integer(5)
      5

  """
  def maybe_integer(%Decimal{} = number) do
    Decimal.to_integer(number)
  rescue
    FunctionClauseError ->
      number

    ArgumentError ->
      number
  end

  def maybe_integer(number) when is_float(number) do
    case trunc(number) do
      truncated when number == truncated -> truncated
      _truncated -> number
    end
  end

  def maybe_integer(number) when is_integer(number) do
    number
  end

  @doc """
  Returns the default number of rounding digits.

  ### Returns

  * An integer (`#{@default_rounding}`).

  ### Examples

      iex> Localize.Utils.Math.default_rounding()
      3

  """
  @spec default_rounding :: 3
  def default_rounding do
    @default_rounding
  end

  @doc """
  Returns the default rounding mode for rounding operations.

  ### Returns

  * The atom `:half_even`.

  ### Examples

      iex> Localize.Utils.Math.default_rounding_mode()
      :half_even

  """
  @spec default_rounding_mode :: :half_even
  def default_rounding_mode do
    @default_rounding_mode
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
  @spec mod(number_or_decimal, number_or_decimal) :: number_or_decimal
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
  Returns the adjusted modulus of `x` and `y`.

  If the modulo result is zero, returns `y` instead.

  ### Arguments

  * `x` is an integer, float, or Decimal.

  * `y` is an integer, float, or Decimal.

  ### Returns

  * The adjusted modulo result.

  ### Examples

      iex> Localize.Utils.Math.amod(10, 5)
      5

      iex> Localize.Utils.Math.amod(7, 3)
      1

  """
  @spec amod(number_or_decimal, number_or_decimal) :: number_or_decimal
  def amod(x, y) do
    case modulo = mod(x, y) do
      %Decimal{} = decimal_mod ->
        if Localize.Utils.Decimal.compare(decimal_mod, @zero) == :eq, do: y, else: modulo

      _ ->
        if modulo == 0, do: y, else: modulo
    end
  end

  @doc """
  Returns the quotient and remainder of two integers.

  ### Arguments

  * `integer_1` is an integer.

  * `integer_2` is an integer.

  ### Returns

  * A tuple `{quotient, remainder}`.

  ### Examples

      iex> Localize.Utils.Math.div_mod(7, 3)
      {2, 1}

  """
  @spec div_mod(integer, integer) :: {integer, integer}
  def div_mod(integer_1, integer_2) when is_integer(integer_1) and is_integer(integer_2) do
    quotient = Kernel.div(integer_1, integer_2)
    remainder = integer_1 - quotient * integer_2
    {quotient, remainder}
  end

  @doc """
  Returns the adjusted quotient and remainder of two integers.

  This version returns the divisor if the remainder would
  otherwise be zero, and decrements the quotient by one.

  ### Arguments

  * `integer_1` is an integer.

  * `integer_2` is an integer.

  ### Returns

  * A tuple `{quotient, adjusted_remainder}`.

  ### Examples

      iex> Localize.Utils.Math.div_amod(10, 5)
      {1, 5}

      iex> Localize.Utils.Math.div_amod(7, 3)
      {2, 1}

  """
  @spec div_amod(integer, integer) :: {integer, integer}
  def div_amod(integer_1, integer_2) when is_integer(integer_1) and is_integer(integer_2) do
    {quotient, remainder} = div_mod(integer_1, integer_2)

    if remainder == 0 do
      {quotient - 1, integer_2}
    else
      {quotient, remainder}
    end
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
  Rounds a number to a specified number of significant digits.

  This is not the same as rounding fractional digits which is performed
  by `Decimal.round/2` and `Float.round/2`.

  ### Arguments

  * `number` is a float, integer, or Decimal.

  * `n` is the number of significant digits to which the `number`
    should be rounded.

  ### Returns

  * The number rounded to `n` significant digits.

  ### Examples

      iex> Localize.Utils.Math.round_significant(3.14159, 3)
      3.14

      iex> Localize.Utils.Math.round_significant(10.3554, 1)
      10.0

      iex> Localize.Utils.Math.round_significant(0.00035, 1)
      0.0004

  """
  @spec round_significant(number_or_decimal, integer) :: number_or_decimal
  def round_significant(number, n) when is_number(number) and n <= 0 do
    number
  end

  def round_significant(number, n) when is_number(number) and n > 0 do
    sign = if number < 0, do: -1, else: 1
    number = abs(number)
    d = Float.ceil(:math.log10(number))
    power = n - d

    magnitude = :math.pow(10, power)
    rounded = Float.round(number * magnitude) / magnitude

    sign *
      if is_integer(number) do
        trunc(rounded)
      else
        rounded
      end
  end

  def round_significant(%Decimal{sign: sign} = number, n) when sign < 0 and n > 0 do
    round_significant(Decimal.abs(number), n)
    |> Decimal.negate()
  end

  def round_significant(%Decimal{sign: sign} = number, n) when sign > 0 and n > 0 do
    d =
      number
      |> log10
      |> Decimal.round(0, :ceiling)

    power =
      n
      |> Decimal.new()
      |> Decimal.sub(d)
      |> Decimal.to_integer()

    magnitude = power(@ten, power)

    number
    |> Decimal.mult(magnitude)
    |> Decimal.round(0)
    |> Decimal.div(magnitude)
  end

  @doc """
  Returns the natural log of a number.

  For integers and floats it calls the BIF `:math.log/1` function.
  For Decimals the log is computed using a series expansion.

  ### Arguments

  * `number` is an integer, float, or Decimal.

  ### Returns

  * The natural logarithm of the number.

  ### Examples

      iex> Localize.Utils.Math.log(123)
      4.812184355372417

      iex> Localize.Utils.Math.log(Decimal.new(9000))
      Decimal.new("9.103886231350952380952380952")

  """
  def log(number) when is_number(number) do
    :math.log(number)
  end

  @ln10 Decimal.from_float(2.30258509299)
  def log(%Decimal{} = number) do
    {mantissa, exp} = coef_exponent(number)
    exp = Decimal.new(exp)
    ln1 = Decimal.mult(exp, @ln10)

    sqrt_mantissa = sqrt(mantissa)
    y = Decimal.div(Decimal.sub(sqrt_mantissa, @one), Decimal.add(sqrt_mantissa, @one))

    ln2 =
      y
      |> log_polynomial([3, 5, 7])
      |> Decimal.add(y)
      |> Decimal.mult(@two)

    Decimal.add(Decimal.mult(@two, ln2), ln1)
  end

  defp log_polynomial(%Decimal{} = value, iterations) do
    Enum.reduce(iterations, @zero, fn i, acc ->
      i = Decimal.new(i)

      value
      |> power(i)
      |> Decimal.div(i)
      |> Decimal.add(acc)
    end)
  end

  @doc """
  Returns the log base 10 of a number.

  For integers and floats it calls the BIF `:math.log10/1` function.
  For Decimals the identity `log10(x) = ln(x) / ln(10)` is used.

  ### Arguments

  * `number` is an integer, float, or Decimal.

  ### Returns

  * The base-10 logarithm of the number.

  ### Examples

      iex> Localize.Utils.Math.log10(100)
      2.0

      iex> Localize.Utils.Math.log10(123)
      2.089905111439398

      iex> Localize.Utils.Math.log10(Decimal.new(9000))
      Decimal.new("3.953767554157656512064441441")

  """
  @spec log10(number_or_decimal) :: float() | Decimal.t()
  def log10(number) when is_number(number) do
    :math.log10(number)
  end

  def log10(%Decimal{} = number) do
    Decimal.div(log(number), @ln10)
  end

  @doc """
  Raises a number to an integer power.

  Uses the binary exponentiation method. For Decimal numbers
  raising 10 to a power, the exponent is shifted directly for
  efficiency.

  ### Arguments

  * `number` is an integer, float, or Decimal.

  * `n` is an integer exponent (or Decimal integer).

  ### Returns

  * The number raised to the given power.

  ### Examples

      iex> Localize.Utils.Math.power(10, 2)
      100

      iex> Localize.Utils.Math.power(10, 3)
      1000

      iex> Localize.Utils.Math.power(2, 10)
      1024

  """
  # Decimal number and decimal n
  @spec power(number_or_decimal, number_or_decimal) :: number_or_decimal
  def power(%Decimal{} = _number, %Decimal{coef: n}) when n == 0 do
    @one
  end

  def power(%Decimal{} = number, %Decimal{sign: sign} = n) when sign < 1 do
    Decimal.div(@one, do_power(number, Decimal.abs(n), mod(Decimal.abs(n), @two)))
  end

  def power(%Decimal{} = number, %Decimal{coef: n}) when n == 1 do
    number
  end

  def power(%Decimal{} = number, %Decimal{} = n) do
    do_power(number, n, mod(n, @two))
  end

  # Decimal number and integer/float n
  def power(%Decimal{} = _number, n) when n == 0 do
    @one
  end

  def power(%Decimal{} = number, n) when n == 1 do
    number
  end

  def power(%Decimal{} = number, n) when n > 1 do
    do_power(number, n, mod(n, 2))
  end

  def power(%Decimal{} = number, n) when n < 0 do
    Decimal.div(@one, do_power(number, abs(n), mod(abs(n), 2)))
  end

  # n is between 0 and 1
  def power(%Decimal{} = number, n) do
    do_power(number, n, mod(number, n))
  end

  # For integers and floats
  def power(number, n) when n == 0 do
    if is_integer(number), do: 1, else: 1.0
  end

  def power(number, n) when n == 1 do
    number
  end

  def power(number, n) when n > 1 do
    do_power(number, n, mod(n, 2))
  end

  def power(number, n) when n < 1 do
    1 / do_power(number, abs(n), mod(abs(n), 2))
  end

  # Decimal number and decimal n
  defp do_power(%Decimal{} = number, %Decimal{coef: coef}, %Decimal{coef: modulo})
       when modulo == 0 and coef == 2 do
    Decimal.mult(number, number)
  end

  defp do_power(%Decimal{} = number, %Decimal{coef: coef} = n, %Decimal{coef: modulo})
       when modulo == 0 and coef != 2 do
    power(power(number, Decimal.div(n, @two)), @two)
  end

  defp do_power(%Decimal{} = number, %Decimal{} = n, _mod) do
    Decimal.mult(number, power(number, Decimal.sub(n, @one)))
  end

  # Decimal number but integer n
  defp do_power(%Decimal{} = number, 1, 1) do
    number
  end

  defp do_power(%Decimal{} = number, n, modulo)
       when is_number(n) and modulo == 0 and n == 2 do
    Decimal.mult(number, number)
  end

  defp do_power(%Decimal{} = number, n, modulo)
       when is_number(n) and modulo == 0 and n != 2 do
    power(power(number, n / 2), 2)
  end

  defp do_power(%Decimal{} = number, n, _mod)
       when is_number(n) and n > 1 do
    Decimal.mult(number, power(number, n - 1))
  end

  # Escape hatch for when the exponent < 1
  defp do_power(%Decimal{} = number, n, _mod) when n < 1 do
    number
    |> Decimal.to_float()
    |> :math.pow(n)
  end

  # integer/float number and integer/float n
  defp do_power(number, n, modulo)
       when is_number(n) and modulo == 0 and n == 2 do
    number * number
  end

  defp do_power(number, n, modulo)
       when is_number(n) and modulo == 0 and n != 2 do
    power(power(number, n / 2), 2)
  end

  defp do_power(number, n, _mod) when is_number(number) and is_number(n) do
    if Kernel.round(n) != n do
      :math.pow(number, n)
    else
      number * power(number, n - 1)
    end
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

  @doc """
  Raises one number to an exponent.

  Delegates to `power/2`.

  ### Arguments

  * `n` is the base number.

  * `m` is the exponent.

  ### Returns

  * The result of `n` raised to the power `m`.

  """
  defdelegate pow(n, m), to: __MODULE__, as: :power

  @doc """
  Returns a tuple representing a number in normalized form with
  the mantissa in the range `0 < m < 10` and a base 10 exponent.

  ### Arguments

  * `number` is an integer, float, or Decimal.

  ### Returns

  * A tuple `{mantissa, exponent}` where the mantissa is in the
    range `0 < m < 10`.

  ### Examples

      iex> Localize.Utils.Math.coef_exponent(Decimal.new(465))
      {Decimal.new("4.65"), 2}

  """
  # An integer should be returned as a float mantissa
  @spec coef_exponent(number_or_decimal) :: {number_or_decimal, integer}
  def coef_exponent(number) when is_integer(number) do
    {mantissa_digits, exponent} = coef_exponent_digits(number)
    {Digits.to_float(mantissa_digits), exponent}
  end

  # All other numbers are returned as the same type as the parameter
  def coef_exponent(number) do
    {mantissa_digits, exponent} = coef_exponent_digits(number)
    {Digits.to_number(mantissa_digits, number), exponent}
  end

  @doc """
  Returns a tuple representing a number in normalized form with
  the mantissa as a `Digits.t` tuple and a base 10 exponent.

  ### Arguments

  * `number` is an integer, float, or Decimal.

  ### Returns

  * A tuple `{digits_tuple, exponent}` where `digits_tuple` is of
    the form `{digit_list, place, sign}`.

  """
  @spec coef_exponent_digits(number_or_decimal) :: {Digits.t(), integer()}
  def coef_exponent_digits(number) do
    {digits, place, sign} = Digits.to_digits(number)
    {{digits, 1, sign}, place - 1}
  end

  @doc """
  Calculates the square root of a Decimal number using Newton's method.

  For integers and floats, delegates to the erlang `:math` module.
  For Decimals, an initial estimate from `:math.sqrt` is refined
  iteratively.

  ### Arguments

  * `number` is an integer, float, or Decimal.

  * `precision` is the desired precision (default: 0.0001).

  ### Returns

  * The square root of the number.

  ### Examples

      iex> Localize.Utils.Math.sqrt(Decimal.new(9))
      Decimal.new("3.0")

      iex> Localize.Utils.Math.sqrt(Decimal.new("9.869"))
      Decimal.new("3.141496458696078173887197038")

  """
  @precision 0.0001
  @decimal_precision Decimal.from_float(@precision)
  def sqrt(number, precision \\ @precision)

  def sqrt(%Decimal{sign: sign} = number, _precision)
      when sign == -1 do
    raise ArgumentError, "bad argument in arithmetic expression #{inspect(number)}"
  end

  def sqrt(%Decimal{} = number, precision)
      when is_number(precision) do
    initial_estimate =
      number
      |> to_float
      |> :math.sqrt()
      |> Decimal.from_float()

    decimal_precision =
      if is_integer(precision) do
        Decimal.new(precision)
      else
        Decimal.from_float(precision)
      end

    do_sqrt(number, initial_estimate, @decimal_precision, decimal_precision)
  end

  def sqrt(number, _precision) do
    :math.sqrt(number)
  end

  defp do_sqrt(
         %Decimal{} = number,
         %Decimal{} = estimate,
         %Decimal{} = old_estimate,
         %Decimal{} = precision
       ) do
    diff =
      estimate
      |> Decimal.sub(old_estimate)
      |> Decimal.abs()

    if Localize.Utils.Decimal.compare(diff, old_estimate) == :lt ||
         Localize.Utils.Decimal.compare(diff, old_estimate) == :eq do
      estimate
    else
      new_estimate =
        Decimal.add(
          Decimal.div(estimate, @two),
          Decimal.div(number, Decimal.mult(@two, estimate))
        )

      do_sqrt(number, new_estimate, estimate, precision)
    end
  end

  @doc """
  Calculates the nth root of a number.

  ### Arguments

  * `number` is an integer or a Decimal.

  * `nth` is a positive integer.

  ### Returns

  * The nth root of the number.

  ### Examples

      iex> Localize.Utils.Math.root(Decimal.new(8), 3)
      Decimal.new("2.0")

      iex> Localize.Utils.Math.root(Decimal.new(27), 3)
      Decimal.new("3.0")

  """
  def root(%Decimal{} = number, nth) when is_integer(nth) and nth > 0 do
    guess =
      number
      |> to_float()
      |> :math.pow(1 / nth)
      |> Decimal.from_float()

    do_root(number, Decimal.new(nth), guess)
  end

  def root(number, nth) when is_number(number) and is_integer(nth) and nth > 0 do
    guess = :math.pow(number, 1 / nth)
    do_root(number, nth, guess)
  end

  @root_precision 0.0001
  defp do_root(number, nth, root) when is_number(number) do
    delta = 1 / nth * (number / :math.pow(root, nth - 1)) - root

    if delta > @root_precision do
      do_root(number, nth, root + delta)
    else
      root
    end
  end

  @decimal_root_precision Decimal.from_float(@root_precision)
  defp do_root(%Decimal{} = number, %Decimal{} = nth, %Decimal{} = root) do
    d1 = Decimal.div(@one, nth)
    d2 = Decimal.div(number, power(root, Decimal.sub(nth, @one)))
    d3 = Decimal.sub(d2, root)
    delta = Decimal.mult(d1, d3)

    if Localize.Utils.Decimal.compare(delta, @decimal_root_precision) == :gt do
      do_root(number, nth, Decimal.add(root, delta))
    else
      root
    end
  end

  @rounding_modes [:down, :up, :ceiling, :floor, :half_even, :half_up, :half_down]

  @doc """
  Returns the list of valid rounding modes.

  ### Returns

  * A list of rounding mode atoms.

  """
  def rounding_modes do
    @rounding_modes
  end

  @doc """
  Rounds a number to an arbitrary precision using one of several
  rounding algorithms.

  Rounding algorithms are based on the definitions given in IEEE 754,
  but also include two additional options.

  ### Arguments

  * `number` is a float, integer, or Decimal.

  * `places` is an integer number of decimal places to round to.
    Default is `0`.

  * `mode` is the rounding mode to be applied. Default is `:half_even`.

  ### Rounding modes

  Directed roundings:

  * `:down` - Round towards 0 (truncate).

  * `:up` - Round away from 0.

  * `:ceiling` - Round toward positive infinity.

  * `:floor` - Round toward negative infinity.

  Round to nearest:

  * `:half_even` - Round to nearest value; tiebreak rounds towards
    the nearest even value. This is the default for IEEE binary
    floating-point.

  * `:half_up` - Round to nearest value; tiebreak rounds away from 0.

  * `:half_down` - Round to nearest value; tiebreak rounds towards 0.

  ### Returns

  * The rounded number.

  ### Examples

      iex> Localize.Utils.Math.round(1.5, 0, :half_even)
      2.0

  """
  def round(number, places \\ 0, mode \\ :half_even)

  def round(%Decimal{} = number, places, mode) do
    Decimal.round(number, places, mode)
  end

  def round(number, places, mode) when is_integer(number) do
    number
    |> Decimal.new()
    |> Decimal.round(places, mode)
    |> Decimal.to_integer()
  end

  def round(number, places, mode) when is_float(number) do
    number
    |> Digits.to_digits()
    |> round_digits(%{decimals: places, rounding: mode})
    |> Digits.to_number(number)
  end

  @doc false
  def round_scientific(number, places, mode) when is_float(number) do
    number
    |> Digits.to_digits()
    |> round_digits(%{scientific: places, rounding: mode})
    |> Digits.to_number(number)
  end

  # The next function heads operate on decomposed numbers returned
  # by Digits.to_digits.

  # scientific/decimal rounding are the same, we are just varying which
  # digit we start counting from to find our rounding point
  defp round_digits(digits_t, options)

  # Passing true for decimal places avoids rounding and uses whatever is necessary
  defp round_digits(digits_t, %{scientific: true}), do: digits_t
  defp round_digits(digits_t, %{decimals: true}), do: digits_t

  defp round_digits({_, place, _}, %{decimals: dp}) when dp + place <= 0 and place < 0 do
    {[0], 1, 1}
  end

  defp round_digits({_, place, _} = digits_t, %{decimals: dp} = options) when dp + place <= 0 do
    {digits, place, sign} = do_round(digits_t, dp, options)
    {List.flatten(digits), place, sign}
  end

  defp round_digits(digits_t = {_, place, _}, options = %{decimals: dp}) do
    {digits, place, sign} = do_round(digits_t, dp + place - 1, options)
    {List.flatten(digits), place, sign}
  end

  defp round_digits(digits_t, options = %{scientific: dp}) do
    {digits, place, sign} = do_round(digits_t, dp, options)
    {List.flatten(digits), place, sign}
  end

  defp do_round({digits, place, sign}, round_at, %{rounding: rounding}) do
    case Enum.split(digits, round_at) do
      {l, [least_sig | [tie | rest]]} ->
        case do_incr(l, least_sig, increment?(sign == 1, least_sig, tie, rest, rounding)) do
          [:rollover | digits] -> {digits, place + 1, sign}
          digits -> {digits, place, sign}
        end

      {[] = l, [least_sig | []]} ->
        case do_incr(l, least_sig, increment?(sign == 1, least_sig, 0, [], rounding)) do
          [:rollover | digits] -> {digits, place + 1, sign}
          digits -> {digits, place, sign}
        end

      {l, [least_sig | []]} ->
        {[l, least_sig], place, sign}

      {l, []} ->
        {l, place, sign}
    end
  end

  @doc """
  Converts a float to a rational number `{numerator, denominator}`.

  ### Arguments

  * `x` is any float.

  * `options` is a keyword list of options.

  ### Options

  * `:max_iterations` - Maximum number of continued fraction terms
    (default: 20).

  * `:epsilon` - Tolerance for float comparisons (default: 1.0e-10).

  * `:max_denominator` - Maximum allowed denominator (default: nil,
    meaning no limit).

  ### Returns

  * A tuple `{numerator, denominator}`.

  ### Examples

      iex> Localize.Utils.Math.float_to_ratio(0.75)
      {3, 4}

      iex> Localize.Utils.Math.float_to_ratio(3.14159, max_iterations: 5)
      {9208, 2931}

      iex> Localize.Utils.Math.float_to_ratio(3.14159, max_denominator: 10)
      {22, 7}

  """
  def float_to_ratio(x, options \\ []) do
    max_iterations = Keyword.get(options, :max_iterations, 20)
    epsilon = Keyword.get(options, :epsilon, 1.0e-10)
    max_denominator = Keyword.get(options, :max_denominator)

    continued_fraction = continued_fraction(x, max_iterations, epsilon)

    if max_denominator do
      convergents_with_limit(continued_fraction, max_denominator)
    else
      convergents(continued_fraction)
    end
    |> Enum.min_by(&approximation_error(x, &1))
  end

  # Generates convergents, stopping when denominator exceeds the limit.
  # Also includes semi-convergents (intermediate fractions) for better approximations.
  defp convergents_with_limit([], _max_denom), do: []
  defp convergents_with_limit([a0], _max_denom), do: [{a0, 1}]

  defp convergents_with_limit([a0 | rest], max_denom) do
    do_convergents_with_limit(rest, {a0, 1}, {1, 0}, max_denom, [{a0, 1}])
  end

  defp do_convergents_with_limit([], _curr, _prev, _max_denom, acc), do: acc

  defp do_convergents_with_limit(
         [a | rest],
         {p_curr, q_curr},
         {p_prev, q_prev},
         max_denom,
         acc
       ) do
    p_next = a * p_curr + p_prev
    q_next = a * q_curr + q_prev

    if q_next > max_denom do
      # If next convergent exceeds limit, try semi-convergents
      semi_convergents =
        generate_semi_convergents(
          {p_prev, q_prev},
          {p_curr, q_curr},
          a,
          max_denom
        )

      Enum.reverse(semi_convergents) ++ acc
    else
      # Next convergent is within limit, continue
      new_acc = [{p_next, q_next} | acc]

      do_convergents_with_limit(
        rest,
        {p_next, q_next},
        {p_curr, q_curr},
        max_denom,
        new_acc
      )
    end
  end

  # Generates semi-convergents between two consecutive convergents.
  defp generate_semi_convergents({p_prev, q_prev}, {p_curr, q_curr}, a, max_denom) do
    # Maximum k such that k * q_curr + q_prev <= max_denom
    max_k = Kernel.div(max_denom - q_prev, q_curr)

    # Generate all semi-convergents from k=1 to min(max_k, a-1)
    1..min(max_k, a - 1)//1
    |> Enum.map(fn k ->
      {k * p_curr + p_prev, k * q_curr + q_prev}
    end)
    |> Enum.filter(fn {_n, d} -> d <= max_denom end)
  end

  # Generates the continued fraction representation of a number.
  defp continued_fraction(x, max_iterations, epsilon) do
    do_continued_fraction(x, max_iterations, epsilon, [])
  end

  defp do_continued_fraction(_x, 0, _epsilon, acc), do: Enum.reverse(acc)

  defp do_continued_fraction(x, _n, epsilon, acc) when abs(x) < epsilon do
    Enum.reverse(acc)
  end

  defp do_continued_fraction(x, n, epsilon, acc) do
    a = floor(x)
    frac = x - a

    if abs(frac) < epsilon do
      Enum.reverse([a | acc])
    else
      do_continued_fraction(1.0 / frac, n - 1, epsilon, [a | acc])
    end
  end

  @doc """
  Calculates convergents (rational approximations) from continued
  fraction coefficients.

  ### Arguments

  * `coefficients` is a list of continued fraction coefficients.

  ### Returns

  * A list of `{numerator, denominator}` tuples.

  ### Examples

      iex> Localize.Utils.Math.convergents([3, 7, 15, 1])
      [{333, 106}, {355, 113}, {22, 7}, {333, 106}, {3, 1}, {22, 7}]

  """
  def convergents([]), do: []
  def convergents([a0]), do: [{a0, 1}]

  def convergents([a0, a1 | rest]) do
    initial = [{a0, 1}, {a0 * a1 + 1, a1}]

    rest
    |> Enum.with_index(2)
    |> Enum.reduce(initial, fn {a, _idx}, [prev, curr | _] = acc ->
      {p_prev, q_prev} = prev
      {p_curr, q_curr} = curr

      p_next = a * p_curr + p_prev
      q_next = a * q_curr + q_prev

      [{p_curr, q_curr}, {p_next, q_next} | acc]
    end)
  end

  @doc """
  Calculates the error between a float and a rational approximation.

  ### Arguments

  * `original` is the original float.

  * `{numerator, denominator}` is the approximate ratio.

  ### Returns

  * The absolute error as a float.

  ### Examples

      iex> Localize.Utils.Math.approximation_error(0.75, {3, 4})
      0.0

  """
  def approximation_error(original, {numerator, denominator}) do
    abs(original - numerator / denominator)
  end

  #
  # Helper functions for round/2-3
  #
  defp do_incr(l, least_sig, false), do: [l, least_sig]
  defp do_incr(l, least_sig, true) when least_sig < 9, do: [l, least_sig + 1]
  # else need to cascade the increment
  defp do_incr(l, 9, true) do
    l
    |> Enum.reverse()
    |> cascade_incr
    |> Enum.reverse([0])
  end

  # cascade an increment of decimal digits which could be rolling over 9 -> 0
  defp cascade_incr([9 | rest]), do: [0 | cascade_incr(rest)]
  defp cascade_incr([d | rest]), do: [d + 1 | rest]
  defp cascade_incr([]), do: [1, :rollover]

  @spec increment?(boolean, non_neg_integer | nil, non_neg_integer | nil, list(), atom()) ::
          boolean
  defp increment?(positive, least_sig, tie, rest, round)

  # Directed rounding towards 0 (truncate)
  defp increment?(_, _ls, _tie, _, :down), do: false
  # Directed rounding away from 0 (non IEEE option)
  defp increment?(_, _ls, nil, _, :up), do: false
  defp increment?(_, _ls, _tie, _, :up), do: true

  # Directed rounding towards +infinity (rounding up / ceiling)
  defp increment?(true, _ls, tie, _, :ceiling) when tie != nil, do: true
  defp increment?(_, _ls, _tie, _, :ceiling), do: false

  # Directed rounding towards -infinity (rounding down / floor)
  defp increment?(false, _ls, tie, _, :floor) when tie != nil, do: true
  defp increment?(_, _ls, _tie, _, :floor), do: false

  # Round to nearest - tiebreaks by rounding to even
  defp increment?(_, ls, 5, [], :half_even) when Integer.is_even(ls), do: false
  defp increment?(_, _ls, tie, _rest, :half_even) when tie >= 5, do: true
  defp increment?(_, _ls, _tie, _rest, :half_even), do: false

  # Round to nearest - tiebreaks by rounding away from zero
  defp increment?(_, _ls, tie, _rest, :half_up) when tie >= 5, do: true
  defp increment?(_, _ls, _tie, _rest, :half_up), do: false

  # Round to nearest - tiebreaks by rounding towards zero
  defp increment?(_, _ls, 5, [], :half_down), do: false
  defp increment?(_, _ls, tie, _rest, :half_down) when tie >= 5, do: true
  defp increment?(_, _ls, _tie, _rest, :half_down), do: false
end
