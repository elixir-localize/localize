defmodule Localize.Number.PluralRule.Transformer do
  @moduledoc false

  # Transforms the parse tree returned from parsing plural rules
  # into an AST representing a `cond` statement that implements
  # the rule.

  @doc """
  Converts a map representing a set of plural rules into a
  `cond` statement AST.

  `rules` is a keyword list of `{category, definition}` pairs
  where the definition is the parsed AST of the CLDR plural
  rule for that category.

  """
  def rules_to_condition_statement(rules, module) do
    branches =
      Enum.map(rules, fn {category, definition} ->
        {new_ast, _} = set_operand_module(definition[:rule], module)
        rule_to_cond_branch(new_ast, category)
      end)

    {:cond, [], [[do: in_semantic_order(branches)]]}
  end

  # TR35 evaluates plural rules "in semantic order: first `zero`, then
  # `one`, `two`, `few`, and `many`", because two rules may both hold for a
  # number and the earlier category must win; `other` takes what is left.
  # The order is set here rather than taken from the data, and the `true`
  # branch goes last because it always matches.
  @semantic_order [:zero, :one, :two, :few, :many, :other]

  defp in_semantic_order(branches) do
    Enum.sort_by(branches, fn {:->, [], [[ast], category]} ->
      {ast == true,
       Enum.find_index(@semantic_order, &(&1 == category)) || length(@semantic_order)}
    end)
  end

  # Walk the AST and replace the variable context to that of the calling
  # module. Also set the correct import context for `mod` and `within`
  # functions which are provided by `Localize.Utils.Math`.
  defp set_operand_module(ast, _module) do
    Macro.prewalk(ast, [], fn expr, acc ->
      new_expr =
        case expr do
          {var, [], Elixir} ->
            {var, [], nil}

          {:mod, _context, [operand, value]} ->
            {:mod, [context: Elixir, import: Elixir.Localize.Utils.Math], [operand, value]}

          {:within, _context, [operand, range]} ->
            {:within, [context: Elixir, import: Elixir.Localize.Utils.Math], [operand, range]}

          _ ->
            expr
        end

      {new_expr, acc}
    end)
  end

  # Transform the rule AST into a branch of a `cond` statement.
  defp rule_to_cond_branch(nil, category) do
    {:->, [], [[true], category]}
  end

  defp rule_to_cond_branch(rule_ast, category) do
    {:->, [], [[rule_ast], category]}
  end
end
