defmodule Localize.OptionalDependency do
  @moduledoc false

  # Some operations belong to a sibling package in the Localize family rather
  # than to Localize itself — parsing a localized date is `calendrical`'s job,
  # and `calendrical` depends on Localize, so Localize cannot depend on it in
  # return without a cycle.
  #
  # The target module is therefore built with `Module.concat/1` and called
  # through a variable rather than named literally. The compiler records no
  # dependency and emits no undefined-module warning, and the call resolves at
  # runtime against whatever the consuming application actually has.

  @doc false
  @spec call(String.t(), atom(), [term()], keyword()) :: term() | {:error, Exception.t()}
  def call(module_name, function, args, context) do
    module = Module.concat([module_name])

    # `Code.ensure_loaded?/1` first: `function_exported?/3` answers false for a
    # module that is compiled but not yet loaded, which would report the
    # package missing on the first call after boot.
    if Code.ensure_loaded?(module) and function_exported?(module, function, length(args)) do
      Kernel.apply(module, function, args)
    else
      {:error,
       Localize.DependencyRequiredError.exception(
         package: Keyword.fetch!(context, :package),
         operation: Keyword.fetch!(context, :operation)
       )}
    end
  end
end
