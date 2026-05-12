defmodule Localize.LocaleDisplayError do
  @moduledoc """
  Exception raised when locale display name data is not
  available for a requested locale.

  """

  defexception [:locale]

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{locale: locale}) do
    Localize.Exception.safe_message(
      "locale",
      "No locale display data for {$locale}.",
      locale: inspect(locale)
    )
  end
end
