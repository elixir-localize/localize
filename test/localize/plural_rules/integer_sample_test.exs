defmodule Localize.Number.PluralRule.IntegerSampleTest do
  use ExUnit.Case, async: true

  @moduletag :slow
  @sample_types [:integer]
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
        Enum.each(from..to, fn int ->
          test "#{inspect(module)}: integer #{inspect(int)} in range #{inspect(from)}..#{inspect(to)} is #{inspect(category)} for #{inspect(locale_name)}" do
            assert unquote(module).plural_rule(
                     unquote(int),
                     unquote(Macro.escape(locale_name))
                   ) == unquote(category)
          end
        end)

      int ->
        test "#{inspect(module)}: integer #{inspect(int)} is #{inspect(category)} for #{inspect(locale_name)}" do
          assert unquote(module).plural_rule(
                   unquote(int),
                   unquote(Macro.escape(locale_name))
                 ) == unquote(category)
        end
    end
  end
end
