defmodule Localize.Number.PluralRule.Loader do
  @moduledoc false

  # Compile-time data loader for plural rules.
  #
  # Lives in a leaf module (depends only on `SupplementalData`) so that
  # `Localize.Number.PluralRule.Cardinal` and `Ordinal` can compile-time
  # depend on it without inheriting `Localize.Number.PluralRule`'s
  # runtime back-edges into the broader compile-connected cycle.

  @doc false
  def load_plural_rules(type) when type in [:cardinal, :ordinal] do
    Localize.SupplementalData.plural_rules(type)
  end

  @doc false
  def load_plural_ranges do
    Localize.SupplementalData.plural_ranges()
  end
end
