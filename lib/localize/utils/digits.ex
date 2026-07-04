defmodule Localize.Utils.Digits do
  # Abstract representation of number (integer, float, Decimal) in tuple form
  # and functions for transformations on number parts.
  #
  # Representing a number as a list of its digits, an integer representing
  # where the decimal point is placed, and an integer representing the sign
  # of the number allow more efficient transforms on the various parts of
  # the number as happens during the formatting of a number for string output.
  #
  # A number in integer, float or Decimal form can be converted
  # to digit form with `to_digits/1`.
  #
  # The digits can be converted back to normal form with
  # `Localize.Utils.Digits.to_integer/1`, `Localize.Utils.Digits.to_float/1`
  # and `Localize.Utils.Digits.to_decimal/1`.
  #
  @moduledoc false

  import Bitwise
  import Localize.Utils.Math, only: [power_of_10: 1]
  require Integer

  @typedoc """
  Defines a number in a tuple form of three parts:

  * A list of digits (0..9) representing the number.

  * A digit representing the place of the decimal point
  in the number.

  * A `1` or `-1` representing the sign of the number.

  """
  @type t :: {[0..9, ...], non_neg_integer, 1 | -1}

  @two52 bsl(1, 52)
  @two53 bsl(1, 53)
  @float_bias 1022
  @min_e -1074

  @doc """
  Returns the fractional part of an integer, float or Decimal as an integer.

  ### Arguments

  * `number` is a float, Decimal, integer, or a tuple of the form
    `{integer_list, fraction_list, sign}` as returned by `to_tuple/1`.

  ### Returns

  * An integer representing the fractional digits.

  ### Examples

      iex> Localize.Utils.Digits.fraction_as_integer(123.456)
      456

      iex> Localize.Utils.Digits.fraction_as_integer(Decimal.new("123.456"))
      456

      iex> Localize.Utils.Digits.fraction_as_integer(1999)
      0

  """
  @spec fraction_as_integer(number() | Decimal.t() | {list, list, 1 | -1}) :: integer
  def fraction_as_integer({_integer, [], _sign}) do
    0
  end

  def fraction_as_integer({_integer, fraction, _sign})
      when is_list(fraction) do
    Integer.undigits(fraction)
  end

  def fraction_as_integer(number) do
    number
    |> to_tuple()
    |> fraction_as_integer()
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
  Returns the number of decimal digits in a number
  (integer, float, Decimal).

  ### Arguments

  * `number` is an integer, float, `Decimal`,
    or a list (which is assumed to contain digits).

  ### Returns

  * An integer count of the total number of digits.

  ### Examples

      iex> Localize.Utils.Digits.number_of_digits(1234)
      4

      iex> Localize.Utils.Digits.number_of_digits(Decimal.new("123456789"))
      9

      iex> Localize.Utils.Digits.number_of_digits(1234.456)
      7

      iex> Localize.Utils.Digits.number_of_digits(1234.56789098765)
      15

      iex> Localize.Utils.Digits.number_of_digits(~c"12345")
      5

  """
  @spec number_of_digits(
          number()
          | Decimal.t()
          | list()
          | {[integer(), ...], integer | [integer(), ...], -1 | 1}
        ) :: integer

  def number_of_digits(%Decimal{} = number) do
    number
    |> to_digits()
    |> number_of_digits()
  end

  def number_of_digits(number) when is_number(number) do
    number
    |> to_digits()
    |> number_of_digits()
  end

  def number_of_digits(list) when is_list(list) do
    length(list)
  end

  def number_of_digits({integer, place, _sign})
      when is_list(integer) and is_integer(place) do
    length(integer)
  end

  @doc """
  Returns the number of decimal digits in the integer
  part of a number.

  ### Arguments

  * `number` is an integer, float, `Decimal`, or
    a list (which is assumed to contain digits).

  ### Returns

  * A non-negative integer count of integer digits.

  ### Examples

      iex> Localize.Utils.Digits.number_of_integer_digits(1234)
      4

      iex> Localize.Utils.Digits.number_of_integer_digits(Decimal.new("123456789"))
      9

      iex> Localize.Utils.Digits.number_of_integer_digits(1234.456)
      4

      iex> Localize.Utils.Digits.number_of_integer_digits(~c"12345")
      5

  """
  @spec number_of_integer_digits(
          number()
          | Decimal.t()
          | list()
          | {[integer(), ...], integer | [integer(), ...], -1 | 1}
        ) :: integer

  def number_of_integer_digits(%Decimal{} = number) do
    number
    |> to_digits()
    |> number_of_integer_digits()
  end

  def number_of_integer_digits(number) when is_number(number) do
    number
    |> to_digits()
    |> number_of_integer_digits()
  end

  # A decomposed integer might be charlist or a list of integers
  # since for certain transforms this is more efficient.  Note
  # that we are not checking if the list elements are actually
  # digits.
  def number_of_integer_digits(list) when is_list(list) do
    length(list)
  end

  # For a tuple returned by `to_digits/1`
  def number_of_integer_digits({integer, place, _sign})
      when is_list(integer) and is_integer(place) and place <= 0 do
    0
  end

  def number_of_integer_digits({integer, place, _sign})
      when is_list(integer) and is_integer(place) do
    place
  end

  # For a tuple returned by `to_tuple/1`
  def number_of_integer_digits({[], _fraction, _sign}) do
    0
  end

  def number_of_integer_digits({integer, fraction, _sign})
      when is_list(integer) and is_list(fraction) do
    number_of_integer_digits(integer)
  end

  @doc """
  Removes trailing zeros from the integer part of a number
  and returns the integer part without trailing zeros.

  ### Arguments

  * `number` is an integer, float, Decimal, or a list of digits.

  ### Returns

  * An integer with trailing zeros removed, or a list with
    trailing zeros removed.

  ### Examples

      iex> Localize.Utils.Digits.remove_trailing_zeros(1234000)
      1234

      iex> Localize.Utils.Digits.remove_trailing_zeros(0)
      0

  """
  @spec remove_trailing_zeros(number() | Decimal.t() | [integer(), ...]) ::
          number() | [integer()]
  def remove_trailing_zeros(0) do
    0
  end

  def remove_trailing_zeros(number) when is_number(number) do
    {integer_digits, _fraction_digits, sign} = to_tuple(number)
    removed = remove_trailing_zeros(integer_digits)
    to_integer({removed, length(removed), sign})
  end

  def remove_trailing_zeros(%Decimal{} = number) do
    {integer_digits, _fraction_digits, sign} = to_tuple(number)
    removed = remove_trailing_zeros(integer_digits)
    to_integer({removed, length(removed), sign})
  end

  # Filters either a charlist or a list of integers.
  def remove_trailing_zeros(number) when is_list(number) do
    Enum.take_while(number, fn c ->
      (c >= ?1 and c <= ?9) or c > 0
    end)
  end

  @doc """
  Returns the number of leading zeros in the fractional
  part of a number.

  ### Arguments

  * `number` is an integer, float, Decimal, or a list of digits.

  ### Returns

  * An integer count of leading zeros.

  ### Examples

      iex> Localize.Utils.Digits.number_of_leading_zeros(Decimal.new("0.0001"))
      3

  """
  @spec number_of_leading_zeros(number() | Decimal.t() | [integer(), ...]) :: integer
  def number_of_leading_zeros(%Decimal{} = number) do
    {_integer_digits, fraction_digits, _sign} = to_tuple(number)
    number_of_leading_zeros(fraction_digits)
  end

  def number_of_leading_zeros(number) when is_number(number) do
    {_integer_digits, fraction_digits, _sign} = to_tuple(number)
    number_of_leading_zeros(fraction_digits)
  end

  def number_of_leading_zeros(number) when is_list(number) do
    Enum.take_while(number, fn c -> c == ?0 or c == 0 end)
    |> length()
  end

  @doc """
  Returns the number of trailing zeros in an
  integer number.

  ### Arguments

  * `number` is an integer or a list of digits.

  ### Returns

  * An integer count of trailing zeros.

  ### Examples

      iex> Localize.Utils.Digits.number_of_trailing_zeros(123000)
      3

  """
  def number_of_trailing_zeros(number) when is_integer(number) do
    {integer_digits, _fraction_digits, _sign} = to_tuple(number)
    number_of_trailing_zeros(integer_digits)
  end

  def number_of_trailing_zeros(number) when is_list(number) do
    number
    |> Enum.reverse()
    |> Enum.take_while(fn c -> c == ?0 or c == 0 end)
    |> length()
  end

  @doc """
  Computes a list of the digits of the given IEEE 754 floating point number,
  together with the location of the decimal point as `{digits, place, sign}`.

  Given an IEEE 754 float, computes the shortest, correctly rounded list of
  digits that converts back to the same Double value when read back with
  `String.to_float/1`.  Implements the algorithm from "Printing Floating-Point
  Numbers Quickly and Accurately" in Proceedings of the SIGPLAN '96 Conference
  on Programming Language Design and Implementation.

  A "compact" representation is returned, so there may be fewer digits returned
  than the decimal point location.

  ### Arguments

  * `number` is a float, integer, or Decimal.

  ### Returns

  * A tuple `{digits, place, sign}` where `digits` is a list of integers
    0..9, `place` is the decimal point position, and `sign` is `1` or `-1`.

  ### Examples

      iex> Localize.Utils.Digits.to_digits(0.0)
      {[0], 1, 1}

      iex> Localize.Utils.Digits.to_digits(123)
      {[1, 2, 3], 3, 1}

  """

  # Code extracted from:
  # https://github.com/ewildgoose/elixir-float_pp/blob/master/lib/float_pp/digits.ex,
  # which is licensed under http://www.apache.org/licenses/LICENSE-2.0

  def to_digits(float_0) when float_0 == 0.0, do: {[0], 1, 1}
  def to_digits(0), do: {[0], 1, 1}

  def to_digits(float) when is_float(float) do
    # Find mantissa and exponent from IEEE-754 packed notation
    {frac, exp} = frexp(float)

    # Scale fraction to integer (and adjust mantissa to compensate)
    frac = trunc(abs(frac) * @two53)
    exp = exp - 53

    # Compute digits
    flonum(float, frac, exp)
  end

  def to_digits(%Decimal{} = number) do
    %Decimal{coef: coef, exp: exp, sign: sign} = Decimal.normalize(number)
    {digits, _place, _sign} = to_digits(coef)
    {digits, length(digits) + exp, sign}
  end

  def to_digits(integer) when is_integer(integer) and integer >= 0 do
    digits = Integer.digits(integer)
    {digits, length(digits), 1}
  end

  def to_digits(integer) when is_integer(integer) do
    digits = Integer.digits(abs(integer))
    {digits, length(digits), -1}
  end

  @doc """
  Converts given number to a list representation.

  Given an IEEE 754 float, computes the shortest, correctly rounded list of
  digits that converts back to the same Double value when read back with
  `String.to_float/1`.  Implements the algorithm from "Printing Floating-Point
  Numbers Quickly and Accurately" in Proceedings of the SIGPLAN '96 Conference
  on Programming Language Design and Implementation.

  Returns a tuple comprising a list for the integer part,
  a list for the fractional part, and an integer for the sign.

  ### Arguments

  * `number` is a float, integer, or Decimal.

  ### Returns

  * A tuple `{integer_digits, fraction_digits, sign}` where each digit
    list contains integers 0..9 and `sign` is `1` or `-1`.

  ### Examples

      iex> Localize.Utils.Digits.to_tuple(123.456)
      {[1, 2, 3], [4, 5, 6], 1}

  """
  @spec to_tuple(Decimal.t() | number) :: {list(), list(), integer}
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

  def to_tuple(number) do
    {mantissa, exp, sign} = to_digits(number)

    mantissa =
      cond do
        # Need to right fill with zeros
        exp > length(mantissa) ->
          mantissa ++ :lists.duplicate(exp - length(mantissa), 0)

        # Need to left fill with zeros
        exp < 0 ->
          :lists.duplicate(abs(exp), 0) ++ mantissa

        true ->
          mantissa
      end

    cond do
      # Its an integer
      exp == length(mantissa) ->
        {mantissa, [], sign}

      # It's a fraction with no integer part
      exp <= 0 ->
        {[], mantissa, sign}

      # It's a fraction
      exp > 0 and exp < length(mantissa) ->
        {integer, fraction} = :lists.split(exp, mantissa)
        {integer, fraction, sign}
    end
  end

  @doc """
  Takes a list of digits and converts them back to a number of the same
  type as `number`.

  ### Arguments

  * `digits` is a tuple `{digit_list, place, sign}` as returned by `to_digits/1`.

  * `number` is a number or atom indicating the desired return type.
    Supported values are an integer, float, `%Decimal{}`, or the atoms
    `:integer`, `:float`, `:decimal`.

  ### Returns

  * A number of the requested type.

  ### Examples

      iex> Localize.Utils.Digits.to_number({[1, 2, 3], 3, 1}, :integer)
      123

      iex> Localize.Utils.Digits.to_number({[1, 2, 3], 3, 1}, :float)
      123.0

  """
  def to_number(digits, number) when is_integer(number), do: to_integer(digits)
  def to_number(digits, number) when is_float(number), do: to_float(digits)
  def to_number(digits, %Decimal{}), do: to_decimal(digits)

  def to_number(digits, :integer), do: to_integer(digits)
  def to_number(digits, :float), do: to_float(digits)
  def to_number(digits, :decimal), do: to_decimal(digits)

  @doc """
  Converts a digit tuple to an integer.

  ### Arguments

  * `digits` is a tuple `{digit_list, place, sign}` as returned by `to_digits/1`.

  ### Returns

  * An integer.

  ### Examples

      iex> Localize.Utils.Digits.to_integer({[1, 2, 3, 4], 4, 1})
      1234

  """
  def to_integer({digits, place, sign}) do
    {int_digits, _fraction_digits} = Enum.split(digits, place)
    Integer.undigits(int_digits) * sign
  end

  @doc """
  Converts a digit tuple to a float.

  ### Arguments

  * `digits` is a tuple `{digit_list, place, sign}` as returned by `to_digits/1`.

  ### Returns

  * A float.

  ### Examples

      iex> Localize.Utils.Digits.to_float({[1, 2, 3, 4], 2, 1})
      12.34

  """
  def to_float({[0], _place, _sign}) do
    0.0
  end

  def to_float({digits, place, sign}) when length(digits) >= place do
    Integer.undigits(digits) / power_of_10(length(digits) - place) * sign
  end

  def to_float({digits, place, sign}) do
    Integer.undigits(digits) * power_of_10(place - length(digits)) * sign * 1.0
  end

  @doc """
  Converts a digit tuple to a Decimal.

  ### Arguments

  * `digits` is a tuple `{digit_list, place, sign}` as returned by `to_digits/1`.

  ### Returns

  * A `%Decimal{}` struct.

  ### Examples

      iex> Localize.Utils.Digits.to_decimal({[1, 2, 3], 2, 1})
      Decimal.new("12.3")

  """
  def to_decimal({digits, place, sign}) do
    %Decimal{coef: Integer.undigits(digits), exp: place - length(digits), sign: sign}
  end

  ############################################################################
  # The following functions are Elixir translations of the original paper:
  # "Printing Floating-Point Numbers Quickly and Accurately"
  # http://www.cs.tufts.edu/~nr/cs257/archive/florian-loitsch/printf.pdf
  # See the paper for further explanation

  # Set initial values {r, s, m+, m-}
  # based on table 1 from FP-Printing paper
  # Assumes frac is scaled to integer (and exponent scaled appropriately)

  defp flonum(float, frac, exp) do
    round = Integer.is_even(frac)

    if exp >= 0 do
      b_exp = bsl(1, exp)

      if frac !== @two52 do
        scale(frac * b_exp * 2, 2, b_exp, b_exp, round, round, float)
      else
        scale(frac * b_exp * 4, 4, b_exp * 2, b_exp, round, round, float)
      end
    else
      if exp === @min_e or frac !== @two52 do
        scale(frac * 2, bsl(1, 1 - exp), 1, 1, round, round, float)
      else
        scale(frac * 4, bsl(1, 2 - exp), 2, 1, round, round, float)
      end
    end
  end

  @log_0_approx -60

  @doc false
  def scale(r, s, m_plus, m_minus, low_ok, high_ok, float) do
    est =
      if float == 0 do
        @log_0_approx
      else
        trunc(Float.ceil(:math.log10(abs(float)) - 1.0e-10))
      end

    if est >= 0 do
      fixup(r, s * power_of_10(est), m_plus, m_minus, est, low_ok, high_ok, float)
    else
      scale = power_of_10(-est)
      fixup(r * scale, s, m_plus * scale, m_minus * scale, est, low_ok, high_ok, float)
    end
  end

  @doc false
  def fixup(r, s, m_plus, m_minus, k, low_ok, high_ok, float) do
    too_low = if high_ok, do: r + m_plus >= s, else: r + m_plus > s

    if too_low do
      {generate(r, s, m_plus, m_minus, low_ok, high_ok), k + 1, sign(float)}
    else
      {generate(r * 10, s, m_plus * 10, m_minus * 10, low_ok, high_ok), k, sign(float)}
    end
  end

  defp generate(r, s, m_plus, m_minus, low_ok, high_ok) do
    d = div(r, s)
    r = rem(r, s)

    tc1 = if low_ok, do: r <= m_minus, else: r < m_minus
    tc2 = if high_ok, do: r + m_plus >= s, else: r + m_plus > s

    generate_digits({tc1, tc2}, d, r, s, m_plus, m_minus, low_ok, high_ok)
  end

  # Emit the next digit (or terminate) based on the two boundary
  # conditions computed in `generate/6`: `tc1` (within the low
  # boundary) and `tc2` (within the high boundary), passed together
  # as a `{tc1, tc2}` tuple.
  defp generate_digits({true, true}, d, r, s, _m_plus, _m_minus, _low_ok, _high_ok) do
    if r * 2 < s do
      [d]
    else
      [d + 1]
    end
  end

  defp generate_digits({true, false}, d, _r, _s, _m_plus, _m_minus, _low_ok, _high_ok) do
    [d]
  end

  defp generate_digits({false, true}, d, _r, _s, _m_plus, _m_minus, _low_ok, _high_ok) do
    [d + 1]
  end

  defp generate_digits({false, false}, d, r, s, m_plus, m_minus, low_ok, high_ok) do
    [d | generate(r * 10, s, m_plus * 10, m_minus * 10, low_ok, high_ok)]
  end

  ############################################################################
  # Utility functions

  # The frexp() function is as per the clib function with the same name. It breaks
  # the floating-point number value into a normalized fraction and an integral
  # power of 2.
  #
  # Returns {frac, exp}, where the magnitude of frac is in the interval
  # [1/2, 1) or 0, and value = frac*(2^exp).

  @doc false
  def frexp(value) do
    <<sign::1, exp::11, frac::52>> = <<value::float>>
    frexp(sign, frac, exp)
  end

  @doc false
  def frexp(_sign, 0, 0) do
    {0.0, 0}
  end

  # Handle denormalised values
  @doc false
  def frexp(sign, frac, 0) do
    exp = bitwise_length(frac)
    <<f::float>> = <<sign::1, @float_bias::11, frac - 1::52>>
    {f, -@float_bias - 52 + exp}
  end

  # Handle normalised values
  @doc false
  def frexp(sign, frac, exp) do
    <<f::float>> = <<sign::1, @float_bias::11, frac::52>>
    {f, exp - @float_bias}
  end

  # Return the number of significant bits needed to store the given number
  defp bitwise_length(value) do
    bitwise_length(value, 0)
  end

  defp bitwise_length(0, n), do: n
  defp bitwise_length(value, n), do: bitwise_length(bsr(value, 1), n + 1)

  defp sign(float) when float < 0, do: -1
  defp sign(_float), do: 1
end
