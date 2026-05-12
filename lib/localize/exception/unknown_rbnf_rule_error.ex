defmodule Localize.UnknownRbnfRuleError do
  @moduledoc """
  Exception raised when an RBNF rule name cannot be resolved for
  a given locale.

  """

  defexception [:rule_name, :locale, :available]

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{rule_name: rule_name, locale: locale}) do
    Localize.Exception.safe_message(
      "number",
      "The RBNF rule {$rule_name} is not known for locale {$locale}.",
      rule_name: inspect(rule_name),
      locale: inspect(locale)
    )
  end
end
