defmodule Localize.CurrencyNotLocalizedError do
  @moduledoc """
  Exception raised when a known currency code has no localized
  data in the requested locale.

  Distinct from `Localize.UnknownCurrencyError`, which signals
  that the currency code itself is not a recognised ISO 4217 or
  registered custom currency. This error means the code is valid
  but the locale's CLDR currency map has no entry for it.

  Pass `fallback: true` to `Localize.Currency.currency_for_code/2`
  to walk the CLDR locale fallback chain (and the application
  default locale) before failing with this error.

  """

  defexception [:currency, :locale]

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{currency: currency, locale: locale}) do
    Localize.Exception.safe_message(
      "currency",
      "The currency {$currency} has no localized data in locale {$locale}.",
      currency: inspect(currency),
      locale: inspect(locale)
    )
  end
end
