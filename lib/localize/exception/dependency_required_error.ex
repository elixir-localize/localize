defmodule Localize.DependencyRequiredError do
  @moduledoc """
  Exception returned when an operation needs a companion package that is
  not among the application's dependencies.

  Localize delegates a few operations to sibling packages that depend on
  Localize in turn, so it cannot depend on them back. Those operations
  resolve the module at runtime and return this exception when it is
  absent, naming the package to add.

  """

  defexception [:package, :operation]

  @typedoc """
  The package that is required, and the operation that needs it.

  """
  @type t :: %__MODULE__{package: String.t(), operation: String.t()}

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{package: package, operation: operation}) do
    Localize.Exception.safe_message(
      "datetime",
      "{$operation} requires the {$package} package, which is not among your dependencies.",
      operation: operation,
      package: package
    )
  end
end
