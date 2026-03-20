defmodule Localize.Utils.Digits do
  @moduledoc """
  Functions for working with the digit components of numbers.

  Provides utilities for extracting fractional parts, counting
  integer digits, and removing trailing zeros — operations
  required by the CLDR plural rules operand calculations.

  """

  import Localize.Utils.Math, only: [power_of_10: 1]

  @doc """
  Returns the fractional part of a number as an integer.

  ### Arguments

  * `number` is a float, integer, or Decimal.

  ### Returns

  * An integer representing the fractional digits.

  ### Examples

      iex> Localize.Utils.Digits.fraction_as_integer(123.456)
      456

      iex> Localize.Utils.Digits.fraction_as_integer(1999)
      0

  """
  @spec fraction_as_integer(number() | Decimal.t()) :: integer()
  def fraction_as_integer(number) when is_integer(number), do: 0

  def fraction_as_integer(number) when is_float(number) do
    number
    |> to_tuple()
    |> do_fraction_as_integer()
  end

  def fraction_as_integer(%Decimal{} = number) do
    number
    |> to_tuple()
    |> do_fraction_as_integer()
  end

  @doc """
  Returns the fractional part of a float as an integer,
  rounding to the specified number of digits first.

  ### Arguments

  * `number` is a float.

  * `rounding` is a positive integer specifying the number of
    fractional digits.

  ### Returns

  * An integer representing the fractional digits.

  ### Examples

      iex> Localize.Utils.Digits.fraction_as_integer(1.456, 3)
      456

  """
  @spec fraction_as_integer(float(), pos_integer()) :: integer()
  def fraction_as_integer(number, rounding) when is_float(number) do
    number = Float.round(number, rounding)
    fraction_as_integer(number)
  end

  @doc """
  Returns the number of integer digits in a number.

  ### Arguments

  * `number` is an integer, float, or Decimal.

  ### Returns

  * A non-negative integer count of integer digits.

  ### Examples

      iex> Localize.Utils.Digits.number_of_integer_digits(1234)
      4

      iex> Localize.Utils.Digits.number_of_integer_digits(0)
      1

  """
  @spec number_of_integer_digits(integer() | float() | Decimal.t()) :: non_neg_integer()
  def number_of_integer_digits(0), do: 1

  def number_of_integer_digits(number) when is_integer(number) and number > 0 do
    number |> Integer.digits() |> length()
  end

  def number_of_integer_digits(number) when is_integer(number) and number < 0 do
    number |> abs() |> Integer.digits() |> length()
  end

  def number_of_integer_digits(number) when is_float(number) do
    number |> trunc() |> abs() |> number_of_integer_digits()
  end

  def number_of_integer_digits(%Decimal{} = number) do
    number
    |> Decimal.abs()
    |> Decimal.round(0, :floor)
    |> Decimal.to_integer()
    |> number_of_integer_digits()
  end

  @doc """
  Removes trailing zeros from an integer and returns the
  result as an integer.

  ### Arguments

  * `number` is an integer.

  ### Returns

  * An integer with trailing zeros removed.

  ### Examples

      iex> Localize.Utils.Digits.remove_trailing_zeros(1234000)
      1234

      iex> Localize.Utils.Digits.remove_trailing_zeros(0)
      0

  """
  @spec remove_trailing_zeros(integer()) :: integer()
  def remove_trailing_zeros(0), do: 0

  def remove_trailing_zeros(number) when is_integer(number) do
    {integer_digits, _fraction_digits, sign} = to_tuple(number)
    removed = do_remove_trailing_zeros(integer_digits)
    digits_to_integer(removed, sign)
  end

  # ── Private helpers ─────────────────────────────────────────────

  defp do_fraction_as_integer({_integer, [], _sign}), do: 0

  defp do_fraction_as_integer({_integer, fraction, _sign}) when is_list(fraction) do
    Integer.undigits(fraction)
  end

  defp do_remove_trailing_zeros(digits) when is_list(digits) do
    digits
    |> Enum.reverse()
    |> Enum.drop_while(&(&1 == 0))
    |> Enum.reverse()
  end

  defp digits_to_integer([], _sign), do: 0

  defp digits_to_integer(digits, sign) do
    value = Integer.undigits(digits)
    if sign == -1, do: -value, else: value
  end

  @doc false
  # Decompose a number into {integer_digits, fraction_digits, sign}
  # where digits are lists of 0..9 integers.
  def to_tuple(number) when is_integer(number) do
    sign = if number < 0, do: -1, else: 1
    digits = number |> abs() |> Integer.digits()
    {digits, [], sign}
  end

  def to_tuple(number) when is_float(number) do
    sign = if number < 0, do: -1, else: 1
    abs_number = abs(number)
    int_part = trunc(abs_number)
    int_digits = Integer.digits(int_part)

    # Get the string representation to find fractional digits
    str = Float.to_string(abs_number)

    frac_digits =
      case String.split(str, ".") do
        [_int_str, frac_str] ->
          frac_str
          |> String.graphemes()
          |> Enum.map(&String.to_integer/1)

        [_int_str] ->
          []
      end

    {int_digits, frac_digits, sign}
  end

  def to_tuple(%Decimal{sign: sign, coef: coef, exp: exp}) do
    sign_val = if sign == 1, do: 1, else: -1
    all_digits = Integer.digits(coef)

    cond do
      exp == 0 ->
        {all_digits, [], sign_val}

      exp < 0 ->
        split_point = length(all_digits) + exp

        if split_point <= 0 do
          # All digits are fractional, need leading zeros
          padding = List.duplicate(0, abs(split_point))
          {[0], padding ++ all_digits, sign_val}
        else
          {int_digits, frac_digits} = Enum.split(all_digits, split_point)
          {int_digits, frac_digits, sign_val}
        end

      exp > 0 ->
        trailing = List.duplicate(0, exp)
        {all_digits ++ trailing, [], sign_val}
    end
  end
end
