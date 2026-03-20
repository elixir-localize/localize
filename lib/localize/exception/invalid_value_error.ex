defmodule Localize.InvalidValueError do
  @moduledoc """
  Exception raised when a value does not meet the expected type
  or constraints for an operation.

  """

  defexception [:value, :expected, :context]

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{value: value, expected: expected, context: nil}) do
    Gettext.dpgettext(
      Localize.Gettext,
      "localize",
      "unit",
      "Expected %{expected}, got: %{value}",
      expected: expected,
      value: inspect(value)
    )
  end

  def message(%__MODULE__{value: value, expected: expected, context: context}) do
    Gettext.dpgettext(
      Localize.Gettext,
      "localize",
      "unit",
      "Expected %{expected} for %{context}, got: %{value}",
      expected: expected,
      context: context,
      value: inspect(value)
    )
  end
end
