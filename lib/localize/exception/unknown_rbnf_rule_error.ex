defmodule Localize.UnknownRbnfRuleError do
  @moduledoc """
  Exception raised when an RBNF rule name cannot be resolved for
  a given locale.

  ### Fields

  * `:rule_name` — the rule set name that was asked for.

  * `:locale` — the locale it was asked for.

  * `:available` — the sorted names of the rule sets the locale
    does have.

  * `:rules_in` — the nearest parent whose RBNF rules the locale
    takes, when that parent is not a supported locale and so was
    not read: `:no` for `nb`, `:en` for `en-GB`. Otherwise `nil`.

  """

  defexception [:rule_name, :locale, :available, :rules_in]

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, Localize.Exception.normalize_locale_bindings(bindings))
  end

  @impl true
  def message(%__MODULE__{rule_name: rule_name, locale: locale, rules_in: nil}) do
    Localize.Exception.safe_message(
      "number",
      "The RBNF rule {$rule_name} is not known for locale {$locale}.",
      rule_name: inspect(rule_name),
      locale: Localize.Exception.locale_name(locale)
    )
  end

  def message(%__MODULE__{rule_name: rule_name, locale: locale, rules_in: rules_in}) do
    Localize.Exception.safe_message(
      "number",
      "The RBNF rule {$rule_name} is not known for locale {$locale}, whose rules are those of {$rules_in}, which is not a supported locale.",
      rule_name: inspect(rule_name),
      locale: Localize.Exception.locale_name(locale),
      rules_in: Localize.Exception.locale_name(rules_in)
    )
  end
end
