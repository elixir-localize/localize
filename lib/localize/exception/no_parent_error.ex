defmodule Localize.NoParentError do
  @moduledoc """
  Exception raised when a parent locale is requested for the
  root locale (`und`) which has no parent.

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
      "The locale {$locale} has no parent locale",
      locale: inspect(locale)
    )
  end
end
