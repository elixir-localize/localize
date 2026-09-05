defmodule Localize.NoMinimalPairError do
  @moduledoc """
  Exception returned when a locale has no minimal pair for the
  grammatical category a value selects.

  Minimal pairs are illustrative data rather than formatting data, so CLDR
  does not ship one for every category in every locale. A locale may have
  cardinals and no ordinals, or carry pairs for some plural categories and
  not others.

  """

  defexception [:locale, :category, :plural_category]

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{
        locale: locale,
        category: category,
        plural_category: plural_category
      }) do
    Localize.Exception.safe_message(
      "no_minimal_pair",
      "No {$category} minimal pair for the {$plural} category in {$locale}.",
      category: inspect(category),
      plural: inspect(plural_category),
      locale: inspect(locale)
    )
  end
end
