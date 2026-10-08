defmodule Localize.InvalidLocaleError do
  @moduledoc """
  Exception raised when a locale identifier cannot be parsed
  into a valid language tag.

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
      "The locale {$locale_id} is not valid.",
      locale_id: Localize.Exception.locale_name(locale_id)
    )
  end
end
