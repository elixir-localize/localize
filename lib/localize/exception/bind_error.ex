defmodule Localize.BindError do
  @moduledoc """
  Exception raised when interpreting a message and one or more
  variable bindings are missing.

  """

  defexception [:unbound]

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{unbound: unbound}) do
    Gettext.dpgettext(
      Localize.Gettext,
      "localize",
      "message",
      "No binding was found for %{unbound}",
      unbound: inspect(unbound)
    )
  end
end
