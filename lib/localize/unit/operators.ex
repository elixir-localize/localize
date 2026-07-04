defmodule Localize.Unit.Operators do
  @moduledoc """
  Overloaded arithmetic operators for `Localize.Unit.t()` values.

  When `use Localize.Unit.Operators` is added to a module, the `+`,
  `-`, `*`, and `/` operators are overridden so that they dispatch to
  `Localize.Unit.Math` when one or both operands is a
  `%Localize.Unit{}` struct. For all other types, the standard
  Elixir/Erlang operators are used.

  The operators raise on error (they use the bang convention
  internally) so they can be used in natural arithmetic
  expressions.

  ## Usage

      defmodule MyApp.Physics do
        use Localize.Unit.Operators

        def kinetic_energy(mass, velocity) do
          # mass and velocity are Localize.Unit structs
          half = Localize.Unit.Math.mult(mass, 0.5) |> elem(1)
          half * velocity * velocity
        end
      end

  ## Supported operations

  | Expression | Delegates to | Notes |
  |---|---|---|
  | `unit + unit` | `Localize.Unit.Math.add/2` | Units must be convertible. |
  | `unit - unit` | `Localize.Unit.Math.sub/2` | Units must be convertible. |
  | `unit * number` | `Localize.Unit.Math.mult/2` | Scalar multiplication. |
  | `number * unit` | `Localize.Unit.Math.mult/2` | Commutative. |
  | `unit * unit` | `Localize.Unit.Math.mult/2` | Produces compound unit. |
  | `unit / number` | `Localize.Unit.Math.div/2` | Scalar division. |
  | `unit / unit` | `Localize.Unit.Math.div/2` | Produces compound unit. |
  | any other types | `Kernel.+/2`, `Kernel.-/2`, `Kernel.*/2`, `Kernel.//2` | Standard Elixir. |

  > #### Scope {: .info}
  >
  > The operator overrides apply only within the module that calls
  > `use Localize.Unit.Operators`. They do not affect other modules
  > or global operator behaviour.

  """

  alias Localize.Unit

  @doc """
  Imports the overloaded `+`, `-`, `*`, and `/` operators into the
  calling module, excluding the corresponding `Kernel` operators
  from the default import so the overrides take effect.

  """
  defmacro __using__(_options) do
    quote do
      import Kernel, except: [+: 2, -: 2, *: 2, /: 2]
      import Localize.Unit.Operators
    end
  end

  # ── Addition ─────────────────────────────────────────────────

  @doc """
  Adds two values. When both are `%Localize.Unit{}` structs,
  delegates to `Localize.Unit.Math.add/2`. Otherwise falls
  through to `Kernel.+/2`.

  """
  def unquote(:+)(%Unit{} = left, %Unit{} = right) do
    unwrap!(Unit.Math.add(left, right))
  end

  def unquote(:+)(left, right) do
    Kernel.+(left, right)
  end

  # ── Subtraction ──────────────────────────────────────────────

  @doc """
  Subtracts two values. When both are `%Localize.Unit{}` structs,
  delegates to `Localize.Unit.Math.sub/2`. Otherwise falls
  through to `Kernel.-/2`.

  """
  def unquote(:-)(%Unit{} = left, %Unit{} = right) do
    unwrap!(Unit.Math.sub(left, right))
  end

  def unquote(:-)(left, right) do
    Kernel.-(left, right)
  end

  # ── Multiplication ───────────────────────────────────────────

  @doc """
  Multiplies two values. When either operand is a
  `%Localize.Unit{}` struct, delegates to
  `Localize.Unit.Math.mult/2`. Otherwise falls through to
  `Kernel.*/2`.

  """
  def unquote(:*)(%Unit{} = left, %Unit{} = right) do
    unwrap!(Unit.Math.mult(left, right))
  end

  def unquote(:*)(%Unit{} = left, right)
      when is_number(right) or is_struct(right, Decimal) do
    unwrap!(Unit.Math.mult(left, right))
  end

  def unquote(:*)(left, %Unit{} = right)
      when is_number(left) or is_struct(left, Decimal) do
    unwrap!(Unit.Math.mult(right, left))
  end

  def unquote(:*)(left, right) do
    Kernel.*(left, right)
  end

  # ── Division ─────────────────────────────────────────────────

  @doc """
  Divides two values. When the left operand is a
  `%Localize.Unit{}` struct, delegates to
  `Localize.Unit.Math.div/2`. Otherwise falls through to
  `Kernel.//2`.

  """
  def unquote(:/)(%Unit{} = left, %Unit{} = right) do
    unwrap!(Unit.Math.div(left, right))
  end

  def unquote(:/)(%Unit{} = left, right)
      when is_number(right) or is_struct(right, Decimal) do
    unwrap!(Unit.Math.div(left, right))
  end

  def unquote(:/)(left, right) do
    Kernel./(left, right)
  end

  # ── Helpers ──────────────────────────────────────────────────

  defp unwrap!({:ok, result}), do: result
  defp unwrap!({:error, exception}) when is_exception(exception), do: raise(exception)
  defp unwrap!({:error, reason}), do: raise(ArgumentError, to_string(reason))
end
