defmodule Localize.Unit.Math do
  @moduledoc """
  Arithmetic operations on `Localize.Unit` structs.

  All functions operate on unit structs that have a value.

  `add` and `sub` require convertible units (same dimensional base unit)
  and return a result in the first argument's unit type.

  `mult` and `div` with two units produce a new compound unit by
  combining their dimensions. For example, `meter * second` produces
  `meter-second`, and `meter / second` produces `meter-per-second`.

  """

  alias Localize.Unit
  alias Localize.Unit.Canonical
  alias Localize.Unit.Conversion

  @doc """
  Negates the value of a unit.

  ### Arguments

  * `unit` is a `%Localize.Unit{}` struct with a value.

  ### Returns

  * `{:ok, unit}` with the negated value.

  ### Examples

      iex> {:ok, u} = Localize.Unit.new(5, "meter")
      iex> {:ok, neg} = Localize.Unit.Math.negate(u)
      iex> neg.value
      -5

  """
  @spec negate(Unit.t()) :: {:ok, Unit.t()} | {:error, Exception.t()}

  def negate(%Unit{value: value} = unit) when not is_nil(value) do
    {:ok, %{unit | value: negate_value(value)}}
  end

  def negate(%Unit{value: nil}) do
    {:error,
     Localize.UnitConversionError.exception(
       from: nil,
       to: nil,
       reason: "Cannot negate a unit without a value"
     )}
  end

  @doc """
  Adds two convertible units together.

  The value of `unit_2` is converted to the unit type of `unit_1`
  before addition. The result has the same unit type as `unit_1`.

  ### Arguments

  * `unit_1` is a `%Localize.Unit{}` struct with a value.

  * `unit_2` is a `%Localize.Unit{}` struct with a value, convertible with `unit_1`.

  ### Returns

  * `{:ok, unit}` with the summed value in `unit_1`'s unit type, or

  * `{:error, reason}` if the units are not convertible.

  ### Examples

      iex> {:ok, a} = Localize.Unit.new(1, "kilometer")
      iex> {:ok, b} = Localize.Unit.new(500, "meter")
      iex> {:ok, result} = Localize.Unit.Math.add(a, b)
      iex> result.value
      1.5
      iex> result.name
      "kilometer"

  """
  @spec add(Unit.t(), Unit.t()) :: {:ok, Unit.t()} | {:error, Exception.t() | String.t()}

  def add(%Unit{value: value_1} = unit_1, %Unit{value: value_2} = unit_2)
      when not is_nil(value_1) and not is_nil(value_2) do
    with {:ok, converted} <- Conversion.convert(value_2, unit_2.name, unit_1.name) do
      {:ok, %{unit_1 | value: add_values(value_1, converted)}}
    end
  end

  def add(%Unit{}, %Unit{}) do
    {:error,
     Localize.UnitConversionError.exception(
       from: nil,
       to: nil,
       reason: "Both units must have values for addition"
     )}
  end

  @doc """
  Subtracts `unit_2` from `unit_1`.

  The value of `unit_2` is converted to the unit type of `unit_1`
  before subtraction. The result has the same unit type as `unit_1`.

  ### Arguments

  * `unit_1` is a `%Localize.Unit{}` struct with a value.

  * `unit_2` is a `%Localize.Unit{}` struct with a value, convertible with `unit_1`.

  ### Returns

  * `{:ok, unit}` with the difference in `unit_1`'s unit type, or

  * `{:error, reason}` if the units are not convertible.

  ### Examples

      iex> {:ok, a} = Localize.Unit.new(1, "kilometer")
      iex> {:ok, b} = Localize.Unit.new(200, "meter")
      iex> {:ok, result} = Localize.Unit.Math.sub(a, b)
      iex> result.value
      0.8
      iex> result.name
      "kilometer"

  """
  @spec sub(Unit.t(), Unit.t()) :: {:ok, Unit.t()} | {:error, Exception.t() | String.t()}

  def sub(%Unit{value: value_1} = unit_1, %Unit{value: value_2} = unit_2)
      when not is_nil(value_1) and not is_nil(value_2) do
    with {:ok, converted} <- Conversion.convert(value_2, unit_2.name, unit_1.name) do
      {:ok, %{unit_1 | value: sub_values(value_1, converted)}}
    end
  end

  def sub(%Unit{}, %Unit{}) do
    {:error,
     Localize.UnitConversionError.exception(
       from: nil,
       to: nil,
       reason: "Both units must have values for subtraction"
     )}
  end

  @doc """
  Inverts a unit.

  For a simple unit like `meter`, the result is `per-meter` with
  value `1 / original_value`. For a per-unit like `meter-per-second`,
  the numerator and denominator are swapped to produce
  `second-per-meter`.

  ### Arguments

  * `unit` is a `%Localize.Unit{}` struct with a value.

  ### Returns

  * `{:ok, unit}` with the inverted unit and value, or

  * `{:error, reason}` if the unit cannot be inverted.

  ### Examples

      iex> {:ok, u} = Localize.Unit.new(4, "meter-per-second")
      iex> {:ok, inv} = Localize.Unit.Math.invert(u)
      iex> inv.name
      "second-per-meter"
      iex> inv.value
      0.25

  """
  @spec invert(Unit.t()) :: {:ok, Unit.t()} | {:error, Exception.t()}

  def invert(%Unit{value: value, parsed: {:unit, keyword}} = _unit) when not is_nil(value) do
    numerator = Keyword.get(keyword, :numerator, [])
    denominator = Keyword.get(keyword, :denominator, [])
    inverted_value = invert_value(value)

    # Swap numerator and denominator; no consolidation or cancellation needed
    inverted_name = Canonical.format_name(denominator, numerator)
    inverted_ast = {:unit, type: nil, numerator: denominator, denominator: numerator}
    {:ok, Unit.from_ast(inverted_value, inverted_name, inverted_ast)}
  end

  def invert(%Unit{value: nil}) do
    {:error,
     Localize.UnitConversionError.exception(
       from: nil,
       to: nil,
       reason: "Cannot invert a unit without a value"
     )}
  end

  @doc """
  Multiplies a unit by a scalar number or another unit.

  When the second argument is a number, the unit's value is scaled.
  When it is a unit, the values are multiplied and a new compound
  unit is produced by combining the dimensions. For example,
  `meter * second` produces `meter-second`.

  ### Arguments

  * `unit` is a `%Localize.Unit{}` struct with a value.

  * `multiplier` is a numeric scalar (integer, float, or Decimal)
    or a `%Localize.Unit{}` struct.

  ### Returns

  * `{:ok, unit}` with the product value and combined unit type, or

  * `{:error, reason}` if the resulting unit name cannot be parsed.

  ### Examples

      iex> {:ok, u} = Localize.Unit.new(5, "meter")
      iex> {:ok, result} = Localize.Unit.Math.mult(u, 3)
      iex> result.value
      15

      iex> {:ok, a} = Localize.Unit.new(10, "meter")
      iex> {:ok, b} = Localize.Unit.new(5, "second")
      iex> {:ok, result} = Localize.Unit.Math.mult(a, b)
      iex> result.value
      50
      iex> result.name
      "meter-second"

  """
  @spec mult(Unit.t(), number() | Decimal.t() | Unit.t()) ::
          {:ok, Unit.t() | number() | Decimal.t()} | {:error, String.t()}
  def mult(unit, multiplier)

  def mult(%Unit{value: value} = unit, number)
      when not is_nil(value) and (is_number(number) or is_struct(number, Decimal)) do
    {:ok, %{unit | value: mult_values(value, number)}}
  end

  def mult(
        %Unit{value: value_1, parsed: {:unit, kw_1}} = _unit_1,
        %Unit{value: value_2, parsed: {:unit, kw_2}} = _unit_2
      )
      when not is_nil(value_1) and not is_nil(value_2) do
    # (a/b) * (c/d) = (a*c) / (b*d)
    new_num = Keyword.get(kw_1, :numerator, []) ++ Keyword.get(kw_2, :numerator, [])
    new_den = Keyword.get(kw_1, :denominator, []) ++ Keyword.get(kw_2, :denominator, [])
    result_value = mult_values(value_1, value_2)

    build_compound_result(result_value, new_num, new_den)
  end

  @doc """
  Divides a unit by a scalar number or another unit.

  When the second argument is a number, the unit's value is divided
  by that number. When it is a unit, the values are divided and a
  new compound unit is produced by combining the dimensions. For
  example, `meter / second` produces `meter-per-second`.

  ### Arguments

  * `unit` is a `%Localize.Unit{}` struct with a value.

  * `divisor` is a numeric scalar (integer, float, or Decimal)
    or a `%Localize.Unit{}` struct.

  ### Returns

  * `{:ok, unit}` with the quotient value and combined unit type, or

  * `{:error, reason}` if the resulting unit name cannot be parsed.

  ### Examples

      iex> {:ok, u} = Localize.Unit.new(10, "meter")
      iex> {:ok, result} = Localize.Unit.Math.div(u, 2)
      iex> result.value
      5.0

      iex> {:ok, a} = Localize.Unit.new(100, "meter")
      iex> {:ok, b} = Localize.Unit.new(10, "second")
      iex> {:ok, result} = Localize.Unit.Math.div(a, b)
      iex> result.value
      10.0
      iex> result.name
      "meter-per-second"

  """
  @spec div(Unit.t(), number() | Decimal.t() | Unit.t()) ::
          {:ok, Unit.t() | number() | Decimal.t()} | {:error, String.t()}
  def div(unit, divisor)

  def div(%Unit{value: value} = unit, number)
      when not is_nil(value) and (is_number(number) or is_struct(number, Decimal)) do
    {:ok, %{unit | value: div_values(value, number)}}
  end

  def div(
        %Unit{value: value_1, parsed: {:unit, kw_1}} = _unit_1,
        %Unit{value: value_2, parsed: {:unit, kw_2}} = _unit_2
      )
      when not is_nil(value_1) and not is_nil(value_2) do
    # (a/b) / (c/d) = (a*d) / (b*c)
    new_num = Keyword.get(kw_1, :numerator, []) ++ Keyword.get(kw_2, :denominator, [])
    new_den = Keyword.get(kw_1, :denominator, []) ++ Keyword.get(kw_2, :numerator, [])
    result_value = div_values(value_1, value_2)

    build_compound_result(result_value, new_num, new_den)
  end

  # Build the result of a compound unit operation. When all dimensions
  # cancel (dimensionless), returns the bare scalar value. Otherwise
  # constructs a Unit directly from the canonical AST without re-parsing.
  defp build_compound_result(value, numerator, denominator) do
    case Canonical.from_components(numerator, denominator) do
      {:dimensionless, nil} ->
        {:ok, value}

      {canonical_name, canonical_ast} ->
        {:ok, Unit.from_ast(value, canonical_name, canonical_ast)}
    end
  end

  # ── Private arithmetic ──────────────────────────────────────────────

  # All arithmetic helpers handle Decimal transparently: if either operand
  # is a Decimal the result is a Decimal, otherwise plain number arithmetic.

  defp negate_value(%Decimal{} = value), do: Decimal.negate(value)
  defp negate_value(value), do: -value

  @dialyzer {:nowarn_function, add_values: 2}
  defp add_values(%Decimal{} = a, b), do: Decimal.add(a, to_decimal(b))
  defp add_values(a, %Decimal{} = b), do: Decimal.add(to_decimal(a), b)
  defp add_values(a, b), do: a + b

  @dialyzer {:nowarn_function, sub_values: 2}
  defp sub_values(%Decimal{} = a, b), do: Decimal.sub(a, to_decimal(b))
  defp sub_values(a, %Decimal{} = b), do: Decimal.sub(to_decimal(a), b)
  defp sub_values(a, b), do: a - b

  defp mult_values(%Decimal{} = a, b), do: Decimal.mult(a, to_decimal(b))
  defp mult_values(a, %Decimal{} = b), do: Decimal.mult(to_decimal(a), b)
  defp mult_values(a, b), do: a * b

  defp div_values(%Decimal{} = a, b), do: Decimal.div(a, to_decimal(b))
  defp div_values(a, %Decimal{} = b), do: Decimal.div(to_decimal(a), b)
  defp div_values(a, b) when is_integer(a) and is_integer(b), do: a / b
  defp div_values(a, b), do: a / b

  defp invert_value(%Decimal{} = value), do: Decimal.div(Decimal.new(1), value)
  defp invert_value(value), do: 1.0 / value

  defp to_decimal(%Decimal{} = d), do: d
  defp to_decimal(value) when is_float(value), do: Decimal.from_float(value)
  defp to_decimal(value) when is_integer(value), do: Decimal.new(value)
end
