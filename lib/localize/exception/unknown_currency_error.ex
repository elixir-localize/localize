defmodule Localize.UnknownCurrencyError do
  @moduledoc """
  Exception raised when a currency code is not a known
  ISO 4217 or registered custom currency.

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
      "The currency %{currency} is not known.",
      currency: inspect(currency)
    )
  end
end
