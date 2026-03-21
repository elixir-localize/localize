defmodule Localize.Utils.Code do
  @moduledoc false

  # Provides a backwards compatible version of
  # the deprecated `Code.ensure_compiled?/1`

  @doc false
  def ensure_compiled?(module) do
    case Code.ensure_compiled(module) do
      {:module, _} -> true
      {:error, _} -> false
    end
  end
end
