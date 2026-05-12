defmodule Localize.UnknownLocaleError do
  @moduledoc """
  Exception raised when a locale identifier does not correspond
  to any known CLDR locale.

  """

  defexception [:locale_id]

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{locale_id: locale_id}) do
    Localize.Exception.safe_message(
      "locale",
      "The locale {$locale_id} is not known.",
      locale_id: inspect(locale_id)
    )
  end
end
