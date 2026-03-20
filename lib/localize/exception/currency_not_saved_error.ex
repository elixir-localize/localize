defmodule Localize.CurrencyNotSavedError do
  @moduledoc """
  Exception raised when an attempt to save a custom currency
  fails, typically because the currency store is not running.

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
      "The currency %{currency} could not be saved. Ensure Localize.Currency.Store is started.",
      currency: inspect(currency)
    )
  end
end
