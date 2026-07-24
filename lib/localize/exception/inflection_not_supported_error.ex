defmodule Localize.InflectionNotSupportedError do
  @moduledoc """
  Exception returned when no language in a locale's fallback chain
  is supported by the Unicode inflection data.

  """

  defexception [:locale]

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{locale: locale}) do
    Localize.Exception.safe_message(
      "inflection",
      "The Unicode inflection data does not support locale {$locale}.",
      locale: inspect(locale)
    )
  end
end
