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
    {:error, Localize.UnitNoValueError.exception(operation: :negate)}
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
    {:error, Localize.UnitNoValueError.exception(operation: :add)}
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
    {:error, Localize.UnitNoValueError.exception(operation: :subtract)}
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
    {:error, Localize.UnitNoValueError.exception(operation: :invert)}
  end

  @doc """
  Multiplies a unit by a scalar number or another unit.

  When the second argument is a number, the unit's value is scaled.
  When it is a unit, the values are multiplied and a new compound
  unit is produced by combining the dimensions. For example,
  `meter * second` produces `meter-second`.

  When both operands share the same base dimension (e.g. both are
  lengths), the second operand is first converted to the first
  operand's unit, then the result is consolidated into a squared
  (or higher-power) form. So `millimeter * meter` produces
  `square-millimeter`, not `millimeter-meter`.

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
          {:ok, Unit.t() | number() | Decimal.t()} | {:error, Exception.t() | String.t()}
  def mult(unit, multiplier)

  def mult(%Unit{value: value} = unit, number)
      when not is_nil(value) and (is_number(number) or is_struct(number, Decimal)) do
    {:ok, %{unit | value: mult_values(value, number)}}
  end

  def mult(
        %Unit{value: value_1, parsed: {:unit, kw_1}} = unit_1,
        %Unit{value: value_2} = unit_2
      )
      when not is_nil(value_1) and not is_nil(value_2) do
    with {:ok, aligned_unit_2} <- maybe_align_units(unit_2, unit_1) do
      {:unit, kw_2} = aligned_unit_2.parsed
      # (a/b) * (c/d) = (a*c) / (b*d)
      new_num = Keyword.get(kw_1, :numerator, []) ++ Keyword.get(kw_2, :numerator, [])
      new_den = Keyword.get(kw_1, :denominator, []) ++ Keyword.get(kw_2, :denominator, [])
      result_value = mult_values(value_1, aligned_unit_2.value)

      build_compound_result(result_value, new_num, new_den)
    end
  end

  @doc """
  Divides a unit by a scalar number or another unit.

  When the second argument is a number, the unit's value is divided
  by that number. When it is a unit, the values are divided and a
  new compound unit is produced by combining the dimensions. For
  example, `meter / second` produces `meter-per-second`.

  When both operands share the same base dimension, the second
  operand is first converted to the first operand's unit, then the
  dimensions cancel and the result is returned as a bare
  dimensionless scalar. So `kilometer / meter` yields a number, not
  a compound unit.

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
          {:ok, Unit.t() | number() | Decimal.t()} | {:error, Exception.t() | String.t()}
  def div(unit, divisor)

  def div(%Unit{value: value} = unit, number)
      when not is_nil(value) and (is_number(number) or is_struct(number, Decimal)) do
    {:ok, %{unit | value: div_values(value, number)}}
  end

  def div(
        %Unit{value: value_1, parsed: {:unit, kw_1}} = unit_1,
        %Unit{value: value_2} = unit_2
      )
      when not is_nil(value_1) and not is_nil(value_2) do
    with {:ok, aligned_unit_2} <- maybe_align_units(unit_2, unit_1) do
      {:unit, kw_2} = aligned_unit_2.parsed
      # (a/b) / (c/d) = (a*d) / (b*c)
      new_num = Keyword.get(kw_1, :numerator, []) ++ Keyword.get(kw_2, :denominator, [])
      new_den = Keyword.get(kw_1, :denominator, []) ++ Keyword.get(kw_2, :numerator, [])
      result_value = div_values(value_1, aligned_unit_2.value)

      build_compound_result(result_value, new_num, new_den)
    end
  end

  # Build the result of a compound unit operation. When all dimensions
  # cancel (dimensionless), returns the bare scalar value. Otherwise
  # constructs a Unit directly from the canonical AST without re-parsing.
  # When two operands share the same base dimension, align the second
  # operand's unit to the first's before combining. This lets the
  # canonical consolidation/cancellation correctly merge same-dimension
  # units (e.g. mm * m -> square-millimeter, mm / m -> dimensionless).
  # Operands with different base dimensions pass through unchanged.
  defp maybe_align_units(unit_2, unit_1) do
    if Localize.Unit.Conversion.convertible?(unit_1.parsed, unit_2.parsed) do
      Unit.convert(unit_2, unit_1.name)
    else
      {:ok, unit_2}
    end
  end

  defp build_compound_result(value, numerator, denominator) do
    case Canonical.from_components(numerator, denominator) do
      {:dimensionless, nil} ->
        {:ok, value}

      {canonical_name, canonical_ast} ->
        {:ok, Unit.from_ast(value, canonical_name, canonical_ast)}
    end
  end

  # ── Value-preserving functions ───────────────────────────────────────
  #
  # These apply a scalar function to the unit's value while keeping
  # the unit type unchanged.

  @doc """
  Returns the absolute value of a unit.

  ### Arguments

  * `unit` is a `%Localize.Unit{}` struct with a value.

  ### Returns

  * `{:ok, unit}` with the absolute value.

  ### Examples

      iex> {:ok, u} = Localize.Unit.new(-5, "meter")
      iex> {:ok, result} = Localize.Unit.Math.abs(u)
      iex> result.value
      5

  """
  @spec abs(Unit.t()) :: {:ok, Unit.t()} | {:error, Exception.t()}

  def abs(%Unit{value: value} = unit) when not is_nil(value) do
    {:ok, %{unit | value: abs_value(value)}}
  end

  def abs(%Unit{value: nil}) do
    {:error, no_value_error("abs")}
  end

  @doc """
  Rounds the value of a unit to the nearest integer or to the
  specified number of decimal places using the given rounding mode.

  Float inputs are routed through `Decimal` so every mode produces
  consistent results; the return value preserves the input value's
  numeric type (float in / float out, Decimal in / Decimal out,
  integer in / integer out).

  ### Arguments

  * `unit` is a `%Localize.Unit{}` struct with a value.

  * `places` is the number of decimal places to round to. Defaults to 0.

  * `mode` is the rounding mode. One of `:half_up` (default),
    `:half_even`, `:half_down`, `:up`, `:down`, `:ceiling`, or `:floor`.

  ### Returns

  * `{:ok, unit}` with the rounded value.

  ### Examples

      iex> {:ok, u} = Localize.Unit.new(3.7, "kilogram")
      iex> {:ok, result} = Localize.Unit.Math.round(u)
      iex> result.value
      4.0

      iex> {:ok, u} = Localize.Unit.new(2.5, "kilogram")
      iex> {:ok, result} = Localize.Unit.Math.round(u, 0, :half_even)
      iex> result.value
      2.0

  """
  @spec round(Unit.t(), non_neg_integer(), atom()) :: {:ok, Unit.t()} | {:error, Exception.t()}

  def round(unit, places \\ 0, mode \\ :half_up)

  def round(%Unit{value: value} = unit, places, mode) when not is_nil(value) do
    {:ok, %{unit | value: round_value(value, places, mode)}}
  end

  def round(%Unit{value: nil}, _places, _mode) do
    {:error, no_value_error("round")}
  end

  @doc """
  Rounds the value of a unit up to the nearest integer.

  ### Arguments

  * `unit` is a `%Localize.Unit{}` struct with a value.

  ### Returns

  * `{:ok, unit}` with the ceiling value.

  ### Examples

      iex> {:ok, u} = Localize.Unit.new(3.2, "meter")
      iex> {:ok, result} = Localize.Unit.Math.ceil(u)
      iex> result.value
      4

  """
  @spec ceil(Unit.t()) :: {:ok, Unit.t()} | {:error, Exception.t()}

  def ceil(%Unit{value: value} = unit) when not is_nil(value) do
    {:ok, %{unit | value: ceil_value(value)}}
  end

  def ceil(%Unit{value: nil}) do
    {:error, no_value_error("ceil")}
  end

  @doc """
  Rounds the value of a unit down to the nearest integer.

  ### Arguments

  * `unit` is a `%Localize.Unit{}` struct with a value.

  ### Returns

  * `{:ok, unit}` with the floor value.

  ### Examples

      iex> {:ok, u} = Localize.Unit.new(3.7, "meter")
      iex> {:ok, result} = Localize.Unit.Math.floor(u)
      iex> result.value
      3

  """
  @spec floor(Unit.t()) :: {:ok, Unit.t()} | {:error, Exception.t()}

  def floor(%Unit{value: value} = unit) when not is_nil(value) do
    {:ok, %{unit | value: floor_value(value)}}
  end

  def floor(%Unit{value: nil}) do
    {:error, no_value_error("floor")}
  end

  @doc """
  Truncates the value of a unit toward zero.

  ### Arguments

  * `unit` is a `%Localize.Unit{}` struct with a value.

  ### Returns

  * `{:ok, unit}` with the truncated value.

  ### Examples

      iex> {:ok, u} = Localize.Unit.new(3.7, "meter")
      iex> {:ok, result} = Localize.Unit.Math.trunc(u)
      iex> result.value
      3

      iex> {:ok, u} = Localize.Unit.new(-3.7, "meter")
      iex> {:ok, result} = Localize.Unit.Math.trunc(u)
      iex> result.value
      -3

  """
  @spec trunc(Unit.t()) :: {:ok, Unit.t()} | {:error, Exception.t()}

  def trunc(%Unit{value: value} = unit) when not is_nil(value) do
    {:ok, %{unit | value: trunc_value(value)}}
  end

  def trunc(%Unit{value: nil}) do
    {:error, no_value_error("trunc")}
  end

  # ── Root functions ─────────────────────────────────────────────────
  #
  # sqrt and cbrt reduce the powers of each dimension component.
  # For example sqrt(square-meter) → meter, sqrt(meter^4) → meter^2.
  # All powers must be evenly divisible by the root degree.

  @doc """
  Computes the square root of a unit.

  The unit must have even powers on all dimension components.
  For example, `sqrt(9 square-meter)` produces `3 meter`, but
  `sqrt(9 cubic-meter)` returns an error.

  ### Arguments

  * `unit` is a `%Localize.Unit{}` struct with a value.

  ### Returns

  * `{:ok, unit}` with the square root of the value and halved unit
    powers, or

  * `{:error, reason}` if any dimension has an odd power.

  ### Examples

      iex> {:ok, u} = Localize.Unit.new(9, "square-meter")
      iex> {:ok, result} = Localize.Unit.Math.sqrt(u)
      iex> result.value
      3.0
      iex> result.name
      "meter"

  """
  @spec sqrt(Unit.t()) :: {:ok, Unit.t() | number()} | {:error, String.t()}

  def sqrt(%Unit{value: value, parsed: {:unit, kw}} = _unit) when not is_nil(value) do
    root_unit(value, kw, 2, "square root")
  end

  def sqrt(%Unit{value: nil}) do
    {:error, no_value_error("sqrt")}
  end

  @doc """
  Computes the cube root of a unit.

  The unit must have powers divisible by 3 on all dimension components.
  For example, `cbrt(27 cubic-meter)` produces `3 meter`.

  ### Arguments

  * `unit` is a `%Localize.Unit{}` struct with a value.

  ### Returns

  * `{:ok, unit}` with the cube root of the value and divided unit
    powers, or

  * `{:error, reason}` if any dimension has a power not divisible by 3.

  ### Examples

      iex> {:ok, u} = Localize.Unit.new(27, "cubic-meter")
      iex> {:ok, result} = Localize.Unit.Math.cbrt(u)
      iex> result.value
      3.0
      iex> result.name
      "meter"

  """
  @spec cbrt(Unit.t()) :: {:ok, Unit.t() | number()} | {:error, String.t()}

  def cbrt(%Unit{value: value, parsed: {:unit, kw}} = _unit) when not is_nil(value) do
    root_unit(value, kw, 3, "cube root")
  end

  def cbrt(%Unit{value: nil}) do
    {:error, no_value_error("cbrt")}
  end

  # ── Dimensionless functions ────────────────────────────────────────
  #
  # Trig and logarithmic functions require a dimensionless (bare number)
  # or a unit whose dimensions have all cancelled. They return a bare
  # number, not a unit.

  @dimensionless_fns ~w(sin cos tan asin acos atan exp sinh cosh tanh asinh acosh atanh)a
  @log_fns ~w(ln log log2)a
  @all_dimensionless_fns @dimensionless_fns ++ @log_fns

  # Dimensionless base units — a unit is considered dimensionless for
  # transcendental functions if it converts to one of these base units.
  @dimensionless_bases ~w(revolution part)

  # ── Public dimensionless function wrappers ──

  @doc """
  Computes the sine of a dimensionless unit value (angle or ratio).

  ### Arguments

  * `unit` is a `%Localize.Unit{}` struct with a value.

  ### Returns

  * `{:ok, number}` with the sine of the value.

  * `{:error, reason}` if the unit is not dimensionless or has no value.

  ### Examples

      iex> {:ok, u} = Localize.Unit.new(0, "radian")
      iex> {:ok, result} = Localize.Unit.Math.sin(u)
      iex> result
      0.0

  """
  @spec sin(Unit.t()) :: {:ok, number()} | {:error, String.t()}
  def sin(unit), do: apply_dimensionless(:sin, unit)

  @doc """
  Computes the cosine of a dimensionless unit value.

  ### Arguments

  * `unit` is a `%Localize.Unit{}` struct with a value.

  ### Returns

  * `{:ok, number}` with the cosine of the value.

  * `{:error, reason}` if the unit is not dimensionless or has no value.

  ### Examples

      iex> {:ok, u} = Localize.Unit.new(0, "radian")
      iex> Localize.Unit.Math.cos(u)
      {:ok, 1.0}

  """
  @spec cos(Unit.t()) :: {:ok, number()} | {:error, String.t()}
  def cos(unit), do: apply_dimensionless(:cos, unit)

  @doc """
  Computes the tangent of a dimensionless unit value.

  ### Arguments

  * `unit` is a `%Localize.Unit{}` struct with a value.

  ### Returns

  * `{:ok, number}` with the tangent of the value.

  * `{:error, reason}` if the unit is not dimensionless or has no value.

  ### Examples

      iex> {:ok, u} = Localize.Unit.new(0, "radian")
      iex> Localize.Unit.Math.tan(u)
      {:ok, 0.0}

  """
  @spec tan(Unit.t()) :: {:ok, number()} | {:error, String.t()}
  def tan(unit), do: apply_dimensionless(:tan, unit)

  @doc """
  Computes the arc sine of a dimensionless unit value.

  ### Arguments

  * `unit` is a `%Localize.Unit{}` struct with a value.

  ### Returns

  * `{:ok, number}` with the arc sine of the value.

  * `{:error, reason}` if the unit is not dimensionless or has no value.

  ### Examples

      iex> {:ok, u} = Localize.Unit.new(0, "radian")
      iex> Localize.Unit.Math.asin(u)
      {:ok, 0.0}

  """
  @spec asin(Unit.t()) :: {:ok, number()} | {:error, String.t()}
  def asin(unit), do: apply_dimensionless(:asin, unit)

  @doc """
  Computes the arc cosine of a dimensionless unit value.

  ### Arguments

  * `unit` is a `%Localize.Unit{}` struct with a value.

  ### Returns

  * `{:ok, number}` with the arc cosine of the value.

  * `{:error, reason}` if the unit is not dimensionless or has no value.

  ### Examples

      iex> {:ok, u} = Localize.Unit.new(1, "radian")
      iex> Localize.Unit.Math.acos(u)
      {:ok, 0.0}

  """
  @spec acos(Unit.t()) :: {:ok, number()} | {:error, String.t()}
  def acos(unit), do: apply_dimensionless(:acos, unit)

  @doc """
  Computes the arc tangent of a dimensionless unit value.

  ### Arguments

  * `unit` is a `%Localize.Unit{}` struct with a value.

  ### Returns

  * `{:ok, number}` with the arc tangent of the value.

  * `{:error, reason}` if the unit is not dimensionless or has no value.

  ### Examples

      iex> {:ok, u} = Localize.Unit.new(0, "radian")
      iex> Localize.Unit.Math.atan(u)
      {:ok, 0.0}

  """
  @spec atan(Unit.t()) :: {:ok, number()} | {:error, String.t()}
  def atan(unit), do: apply_dimensionless(:atan, unit)

  @doc """
  Computes the hyperbolic sine of a dimensionless unit value.

  ### Arguments

  * `unit` is a `%Localize.Unit{}` struct with a value.

  ### Returns

  * `{:ok, number}` with the hyperbolic sine of the value.

  * `{:error, reason}` if the unit is not dimensionless or has no value.

  ### Examples

      iex> {:ok, u} = Localize.Unit.new(0, "radian")
      iex> Localize.Unit.Math.sinh(u)
      {:ok, 0.0}

  """
  @spec sinh(Unit.t()) :: {:ok, number()} | {:error, String.t()}
  def sinh(unit), do: apply_dimensionless(:sinh, unit)

  @doc """
  Computes the hyperbolic cosine of a dimensionless unit value.

  ### Arguments

  * `unit` is a `%Localize.Unit{}` struct with a value.

  ### Returns

  * `{:ok, number}` with the hyperbolic cosine of the value.

  * `{:error, reason}` if the unit is not dimensionless or has no value.

  ### Examples

      iex> {:ok, u} = Localize.Unit.new(0, "radian")
      iex> Localize.Unit.Math.cosh(u)
      {:ok, 1.0}

  """
  @spec cosh(Unit.t()) :: {:ok, number()} | {:error, String.t()}
  def cosh(unit), do: apply_dimensionless(:cosh, unit)

  @doc """
  Computes the hyperbolic tangent of a dimensionless unit value.

  ### Arguments

  * `unit` is a `%Localize.Unit{}` struct with a value.

  ### Returns

  * `{:ok, number}` with the hyperbolic tangent of the value.

  * `{:error, reason}` if the unit is not dimensionless or has no value.

  ### Examples

      iex> {:ok, u} = Localize.Unit.new(0, "radian")
      iex> Localize.Unit.Math.tanh(u)
      {:ok, 0.0}

  """
  @spec tanh(Unit.t()) :: {:ok, number()} | {:error, String.t()}
  def tanh(unit), do: apply_dimensionless(:tanh, unit)

  @doc """
  Computes the inverse hyperbolic sine of a dimensionless unit value.

  ### Arguments

  * `unit` is a `%Localize.Unit{}` struct with a value.

  ### Returns

  * `{:ok, number}` with the inverse hyperbolic sine of the value.

  * `{:error, reason}` if the unit is not dimensionless or has no value.

  ### Examples

      iex> {:ok, u} = Localize.Unit.new(0, "radian")
      iex> Localize.Unit.Math.asinh(u)
      {:ok, 0.0}

  """
  @spec asinh(Unit.t()) :: {:ok, number()} | {:error, String.t()}
  def asinh(unit), do: apply_dimensionless(:asinh, unit)

  @doc """
  Computes the inverse hyperbolic cosine of a dimensionless unit value.

  ### Arguments

  * `unit` is a `%Localize.Unit{}` struct with a value.

  ### Returns

  * `{:ok, number}` with the inverse hyperbolic cosine of the value.

  * `{:error, reason}` if the unit is not dimensionless or has no value.

  ### Examples

      iex> {:ok, u} = Localize.Unit.new(1, "radian")
      iex> Localize.Unit.Math.acosh(u)
      {:ok, 0.0}

  """
  @spec acosh(Unit.t()) :: {:ok, number()} | {:error, String.t()}
  def acosh(unit), do: apply_dimensionless(:acosh, unit)

  @doc """
  Computes the inverse hyperbolic tangent of a dimensionless unit value.

  ### Arguments

  * `unit` is a `%Localize.Unit{}` struct with a value.

  ### Returns

  * `{:ok, number}` with the inverse hyperbolic tangent of the value.

  * `{:error, reason}` if the unit is not dimensionless or has no value.

  ### Examples

      iex> {:ok, u} = Localize.Unit.new(0, "radian")
      iex> Localize.Unit.Math.atanh(u)
      {:ok, 0.0}

  """
  @spec atanh(Unit.t()) :: {:ok, number()} | {:error, String.t()}
  def atanh(unit), do: apply_dimensionless(:atanh, unit)

  @doc """
  Computes e^x for a dimensionless unit value.

  ### Arguments

  * `unit` is a `%Localize.Unit{}` struct with a value.

  ### Returns

  * `{:ok, number}` with e raised to the value.

  * `{:error, reason}` if the unit is not dimensionless or has no value.

  ### Examples

      iex> {:ok, u} = Localize.Unit.new(0, "radian")
      iex> Localize.Unit.Math.exp(u)
      {:ok, 1.0}

  """
  @spec exp(Unit.t()) :: {:ok, number()} | {:error, String.t()}
  def exp(unit), do: apply_dimensionless(:exp, unit)

  @doc """
  Computes the natural logarithm of a dimensionless unit value.

  ### Arguments

  * `unit` is a `%Localize.Unit{}` struct with a value.

  ### Returns

  * `{:ok, number}` with the natural logarithm of the value.

  * `{:error, reason}` if the unit is not dimensionless or has no value.

  ### Examples

      iex> {:ok, u} = Localize.Unit.new(1, "radian")
      iex> Localize.Unit.Math.ln(u)
      {:ok, 0.0}

  """
  @spec ln(Unit.t()) :: {:ok, number()} | {:error, String.t()}
  def ln(unit), do: apply_dimensionless(:ln, unit)

  @doc """
  Computes the base-10 logarithm of a dimensionless unit value.

  ### Arguments

  * `unit` is a `%Localize.Unit{}` struct with a value.

  ### Returns

  * `{:ok, number}` with the base-10 logarithm of the value.

  * `{:error, reason}` if the unit is not dimensionless or has no value.

  ### Examples

      iex> {:ok, u} = Localize.Unit.new(100, "radian")
      iex> Localize.Unit.Math.log(u)
      {:ok, 2.0}

  """
  @spec log(Unit.t()) :: {:ok, number()} | {:error, String.t()}
  def log(unit), do: apply_dimensionless(:log, unit)

  @doc """
  Computes the base-2 logarithm of a dimensionless unit value.

  ### Arguments

  * `unit` is a `%Localize.Unit{}` struct with a value.

  ### Returns

  * `{:ok, number}` with the base-2 logarithm of the value.

  * `{:error, reason}` if the unit is not dimensionless or has no value.

  ### Examples

      iex> {:ok, u} = Localize.Unit.new(8, "radian")
      iex> Localize.Unit.Math.log2(u)
      {:ok, 3.0}

  """
  @spec log2(Unit.t()) :: {:ok, number()} | {:error, String.t()}
  def log2(unit), do: apply_dimensionless(:log2, unit)

  # ── apply_dimensionless/2 ──

  @doc """
  Applies a trigonometric, hyperbolic, or transcendental function to
  a dimensionless unit value.

  The unit must be dimensionless — its base unit must reduce to an
  angle (`revolution`) or a ratio (`part`). Units with physical
  dimensions (length, mass, etc.) are rejected.

  Supported function names: #{Enum.map_join(@all_dimensionless_fns, ", ", &"`:#{&1}`")}.

  ### Arguments

  * `name` is an atom naming the function.

  * `unit` is a `%Localize.Unit{}` struct with a value.

  ### Returns

  * `{:ok, number}` with the function result.

  * `{:error, reason}` if the unit is not dimensionless or has no value.

  ### Examples

      iex> {:ok, u} = Localize.Unit.new(0, "radian")
      iex> {:ok, result} = Localize.Unit.Math.apply_dimensionless(:sin, u)
      iex> result
      0.0

  """
  @spec apply_dimensionless(atom(), Unit.t()) :: {:ok, number()} | {:error, String.t()}

  def apply_dimensionless(name, %Unit{value: value, parsed: parsed} = _unit)
      when name in @dimensionless_fns and not is_nil(value) do
    with :ok <- check_dimensionless(name, parsed) do
      {:ok, apply_math_fn(name, to_float(value))}
    end
  end

  def apply_dimensionless(name, %Unit{value: value, parsed: parsed} = _unit)
      when name in @log_fns and not is_nil(value) do
    with :ok <- check_dimensionless(name, parsed) do
      {:ok, apply_math_fn(name, to_float(value))}
    end
  end

  def apply_dimensionless(_name, %Unit{value: nil}) do
    {:error, "function requires a unit with a value"}
  end

  def apply_dimensionless(name, _unit) do
    {:error, "unknown dimensionless function: #{name}"}
  end

  defp apply_math_fn(:sin, x), do: :math.sin(x)
  defp apply_math_fn(:cos, x), do: :math.cos(x)
  defp apply_math_fn(:tan, x), do: :math.tan(x)
  defp apply_math_fn(:asin, x), do: :math.asin(x)
  defp apply_math_fn(:acos, x), do: :math.acos(x)
  defp apply_math_fn(:atan, x), do: :math.atan(x)
  defp apply_math_fn(:exp, x), do: :math.exp(x)
  defp apply_math_fn(:sinh, x), do: :math.sinh(x)
  defp apply_math_fn(:cosh, x), do: :math.cosh(x)
  defp apply_math_fn(:tanh, x), do: :math.tanh(x)
  defp apply_math_fn(:asinh, x), do: :math.asinh(x)
  defp apply_math_fn(:acosh, x), do: :math.acosh(x)
  defp apply_math_fn(:atanh, x), do: :math.atanh(x)
  defp apply_math_fn(:ln, x), do: :math.log(x)
  defp apply_math_fn(:log, x), do: :math.log10(x)
  defp apply_math_fn(:log2, x), do: :math.log2(x)

  defp check_dimensionless(name, parsed) do
    case Localize.Unit.BaseUnit.base_unit(parsed) do
      {:ok, base} when base in @dimensionless_bases ->
        :ok

      {:ok, base} ->
        {:error, "#{name} requires a dimensionless value, got unit with base: #{base}"}

      {:error, _} ->
        # If base unit resolution fails, allow it (might be a bare number)
        :ok
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

  defp abs_value(%Decimal{} = value), do: Decimal.abs(value)
  defp abs_value(value), do: Kernel.abs(value)

  # Decimal supports every rounding mode natively. Floats are routed
  # through Decimal so we get consistent semantics for `:half_even`,
  # `:ceiling`, `:floor`, and `:down` — Erlang/Elixir's built-in float
  # round only handles `:half_up`.
  defp round_value(%Decimal{} = value, places, mode), do: Decimal.round(value, places, mode)

  defp round_value(value, _places, _mode) when is_integer(value), do: value

  defp round_value(value, places, mode) when is_float(value) do
    value
    |> Decimal.from_float()
    |> Decimal.round(places, mode)
    |> Decimal.to_float()
  end

  defp ceil_value(%Decimal{} = value),
    do: Decimal.round(value, 0, :ceiling) |> Decimal.to_integer()

  defp ceil_value(value) when is_float(value), do: Kernel.ceil(value)
  defp ceil_value(value) when is_integer(value), do: value

  defp floor_value(%Decimal{} = value),
    do: Decimal.round(value, 0, :floor) |> Decimal.to_integer()

  defp floor_value(value) when is_float(value), do: Kernel.floor(value)
  defp floor_value(value) when is_integer(value), do: value

  defp trunc_value(%Decimal{} = value),
    do: Decimal.round(value, 0, :down) |> Decimal.to_integer()

  defp trunc_value(value) when is_float(value), do: Kernel.trunc(value)
  defp trunc_value(value) when is_integer(value), do: value

  defp to_float(%Decimal{} = d), do: Decimal.to_float(d)
  defp to_float(value) when is_integer(value), do: value / 1
  defp to_float(value) when is_float(value), do: value

  defp to_decimal(%Decimal{} = d), do: d
  defp to_decimal(value) when is_float(value), do: Decimal.from_float(value)
  defp to_decimal(value) when is_integer(value), do: Decimal.new(value)

  # ── Root helpers ───────────────────────────────────────────────────

  # Takes the nth root of a unit by dividing all dimension powers by n.
  # Returns {:ok, result} where result is a Unit or bare number (if
  # all dimensions cancel), or {:error, reason}.
  defp root_unit(value, kw, degree, label) do
    numerator = Keyword.get(kw, :numerator, [])
    denominator = Keyword.get(kw, :denominator, [])

    with {:ok, rooted_num} <- root_components(numerator, degree, label),
         {:ok, rooted_den} <- root_components(denominator, degree, label) do
      rooted_value = :math.pow(to_float(value), 1.0 / degree)
      build_compound_result(rooted_value, rooted_num, rooted_den)
    end
  end

  defp root_components(components, degree, label) do
    Enum.reduce_while(components, {:ok, []}, fn {:single_unit, opts}, {:ok, acc} ->
      power = power_to_integer(Keyword.get(opts, :power))

      if rem(power, degree) == 0 do
        new_power = Kernel.div(power, degree)
        new_opts = Keyword.put(opts, :power, integer_to_power(new_power))
        {:cont, {:ok, acc ++ [{:single_unit, new_opts}]}}
      else
        base = Keyword.get(opts, :base, "unknown")
        {:halt, {:error, "cannot take #{label} of #{base} with power #{power}"}}
      end
    end)
  end

  defp power_to_integer(nil), do: 1
  defp power_to_integer(:square), do: 2
  defp power_to_integer(:cubic), do: 3
  defp power_to_integer({:pow, n}), do: n

  defp integer_to_power(1), do: nil
  defp integer_to_power(2), do: :square
  defp integer_to_power(3), do: :cubic
  defp integer_to_power(n), do: {:pow, n}

  defp no_value_error(operation) do
    Localize.UnitNoValueError.exception(operation: operation)
  end
end
