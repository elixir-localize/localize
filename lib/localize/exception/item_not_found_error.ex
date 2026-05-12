defmodule Localize.ItemNotFoundError do
  @moduledoc """
  Exception raised when a key path cannot be resolved in
  locale data.

  """

  defexception [:locale, :keys]

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{locale: locale, keys: keys}) do
    Localize.Exception.safe_message(
      "locale",
      "The key path {$keys} was not found in locale {$locale}.",
      keys: inspect(keys),
      locale: inspect(locale)
    )
  end
end
