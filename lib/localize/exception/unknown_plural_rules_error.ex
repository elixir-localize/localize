defmodule Localize.UnknownPluralRulesError do
  @moduledoc """
  Exception raised when no plural rules are available for
  a given locale.

  """

  defexception [:locale_id, :type]

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{locale_id: locale_id, type: type}) do
    type_name = if type, do: " #{type}", else: ""

    Localize.Exception.safe_message(
      "plural_rules",
      "No{$type} plural rules available for the locale {$locale_id}.",
      locale_id: inspect(locale_id),
      type: type_name
    )
  end
end
