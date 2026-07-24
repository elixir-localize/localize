defmodule Localize.UnknownPronounError do
  @moduledoc """
  Exception returned when an initial pronoun is not found in the
  locale's pronoun table.

  """

  defexception [:pronoun, :locale]

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{pronoun: pronoun, locale: locale}) do
    Localize.Exception.safe_message(
      "inflection",
      "The pronoun {$pronoun} is not in the pronoun table for locale {$locale}.",
      pronoun: inspect(pronoun),
      locale: inspect(locale)
    )
  end
end
