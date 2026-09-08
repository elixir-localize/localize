defmodule Localize.NoPluralCategoryError do
  @moduledoc """
  Exception returned when quantification is requested without a
  plural category and without a numeric value to derive one from.

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
      "Quantifying for locale {$locale} needs a :plural category or a :number to derive one from.",
      locale: inspect(locale)
    )
  end
end
