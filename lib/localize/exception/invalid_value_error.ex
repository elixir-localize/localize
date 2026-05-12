defmodule Localize.InvalidValueError do
  @moduledoc """
  Exception raised when a value does not meet the expected type
  or constraints for an operation.

  `:expected` is either an atom naming the expected category
  (for example `:rounding_mode`, `:time_unit`, `:usage`) or a
  short string label describing the expected shape. `:allowed_values`,
  when set, carries the closed list of acceptable values that the
  rendered message will include.

  """

  defexception [:value, :expected, :allowed_values, :context]

  @type t :: %__MODULE__{
          value: term(),
          expected: atom() | String.t() | nil,
          allowed_values: [term()] | nil,
          context: term() | nil
        }

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{
        value: value,
        expected: expected,
        allowed_values: allowed,
        context: context
      })
      when is_atom(expected) and not is_nil(expected) and is_list(allowed) do
    humanized = expected |> Atom.to_string() |> String.replace("_", " ")

    Localize.Exception.safe_message(
      "unit",
      "Expected a valid {$expected}{$context_part}, got: {$value} (allowed values: {$allowed})",
      expected: humanized,
      context_part: context_suffix(context),
      value: inspect(value),
      allowed: inspect(allowed)
    )
  end

  def message(%__MODULE__{
        value: value,
        expected: expected,
        context: context
      })
      when is_atom(expected) and not is_nil(expected) do
    humanized = expected |> Atom.to_string() |> String.replace("_", " ")

    Localize.Exception.safe_message(
      "unit",
      "Expected a valid {$expected}{$context_part}, got: {$value}",
      expected: humanized,
      context_part: context_suffix(context),
      value: inspect(value)
    )
  end

  def message(%__MODULE__{value: value, expected: expected, context: nil}) do
    Localize.Exception.safe_message(
      "unit",
      "Expected {$expected}, got: {$value}",
      expected: expected,
      value: inspect(value)
    )
  end

  def message(%__MODULE__{value: value, expected: expected, context: context}) do
    Localize.Exception.safe_message(
      "unit",
      "Expected {$expected} for {$context}, got: {$value}",
      expected: expected,
      context: context,
      value: inspect(value)
    )
  end

  defp context_suffix(nil), do: ""
  defp context_suffix(context), do: " for #{inspect(context)}"
end
