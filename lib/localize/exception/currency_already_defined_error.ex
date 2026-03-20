defmodule Localize.CurrencyAlreadyDefinedError do
  @moduledoc """
  Exception raised when attempting to define a custom currency
  with a code that is already in use.

  """

  defexception [:currency]

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{currency: currency}) do
    Gettext.dpgettext(
      Localize.Gettext,
      "localize",
      "currency",
      "The currency %{currency} is already defined.",
      currency: inspect(currency)
    )
  end
end
