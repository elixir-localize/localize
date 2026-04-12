defmodule Localize.CurrencyNoDisplayNameError do
  @moduledoc """
  Exception raised when a currency has no display name
  available for the requested locale.

  """

  defexception [:currency, :locale]

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{currency: currency, locale: locale}) do
    Gettext.dpgettext(
      Localize.Gettext,
      "localize",
      "currency",
      "The currency {$currency} has no display name in locale {$locale}.",
      currency: inspect(currency),
      locale: inspect(locale)
    )
  end
end
