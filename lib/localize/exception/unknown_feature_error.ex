defmodule Localize.UnknownFeatureError do
  @moduledoc """
  Exception returned when a grammatical feature name is not
  defined for a locale.

  """

  defexception [:feature, :locale]

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{feature: feature, locale: locale}) do
    Localize.Exception.safe_message(
      "inflection",
      "The grammatical feature {$feature} is not defined for locale {$locale}.",
      feature: inspect(feature),
      locale: inspect(locale)
    )
  end
end
