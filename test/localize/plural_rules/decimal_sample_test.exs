defmodule Localize.Number.PluralRule.DecimalSampleTest do
  use ExUnit.Case, async: true

  @moduletag :slow
  @sample_types [:decimal]
  @modules [
    {Localize.Number.PluralRule.Cardinal, :cardinal},
    {Localize.Number.PluralRule.Ordinal, :ordinal}
  ]

  for {module, _type} <- @modules,
      locale_name <- module.available_locale_names(),
      {category, rule} <- module.plural_rules_for(locale_name) || [],
      sample_type <- @sample_types,
      one_rule <- rule[sample_type] || [] do
    case one_rule do
      :ellipsis ->
        true

      {:.., _context, [from, to]} ->
        test "#{inspect(module)}: decimal range #{inspect(from)}..#{inspect(to)} is #{inspect(category)} for #{inspect(locale_name)}" do
          assert unquote(module).plural_rule(
                   unquote(Macro.escape(from)),
                   unquote(Macro.escape(locale_name))
                 ) == unquote(category)

          assert unquote(module).plural_rule(
                   unquote(Macro.escape(to)),
                   unquote(Macro.escape(locale_name))
                 ) == unquote(category)
        end

      dec ->
        test "#{inspect(module)}: decimal #{inspect(dec)} is #{inspect(category)} for #{inspect(locale_name)}" do
          assert unquote(module).plural_rule(
                   unquote(Macro.escape(dec)),
                   unquote(Macro.escape(locale_name))
                 ) == unquote(category)
        end
    end
  end
end
