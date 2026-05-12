defmodule Localize.UnknownScriptError do
  @moduledoc """
  Exception raised when a script code is not a known
  ISO 15924 or CLDR script subtag.

  """

  defexception [:script]

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{script: script}) do
    Localize.Exception.safe_message(
      "locale",
      "The script {$script} is not known.",
      script: inspect(script)
    )
  end
end
