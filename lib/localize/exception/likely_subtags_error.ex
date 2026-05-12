defmodule Localize.LikelySubtagsError do
  @moduledoc """
  Exception raised when likely subtags data cannot be found
  for a given locale identifier.

  """

  defexception [:locale]

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{locale: locale}) do
    Localize.Exception.safe_message(
      "language_tag",
      "No likely subtags data found for {$locale}",
      locale: inspect(locale)
    )
  end
end
