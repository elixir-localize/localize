defmodule Localize.Data.PluralRules do
  @moduledoc """
  Generates plural rule ETF files from raw CLDR JSON source data.

  Reads cardinal rules from `plurals.json` and ordinal rules from
  `ordinals.json`, parses each rule string through the plural rule
  compiler, and returns maps of locale atoms to sorted rule keyword
  lists.

  """

  @doc """
  Generates cardinal plural rules from `plurals.json`.

  Returns a map of locale atoms to keyword lists of
  `{category_atom, parsed_ast}` tuples, sorted by plural
  category order.

  """
  def generate_plural_rules_cardinal do
    Localize.Data.read_json("plurals.json")
    |> get_in(["supplemental", "plurals-type-cardinal"])
    |> normalize_plural_rules()
    |> Map.new()
  end

  @doc """
  Generates ordinal plural rules from `ordinals.json`.

  Returns a map of locale atoms to keyword lists of
  `{category_atom, parsed_ast}` tuples, sorted by plural
  category order.

  """
  def generate_plural_rules_ordinal do
    Localize.Data.read_json("ordinals.json")
    |> get_in(["supplemental", "plurals-type-ordinal"])
    |> normalize_plural_rules()
    |> Map.new()
  end

  defp normalize_plural_rules(rules) do
    Enum.map(rules, &normalize_rules_for_locale/1)
  end

  defp normalize_rules_for_locale({locale, rules}) do
    sorted_rules =
      Enum.map(rules, fn {"pluralRule-count-" <> category, rule} ->
        {:ok, definition} = Localize.Number.PluralRule.Compiler.parse(rule)
        {String.to_atom(category), definition}
      end)
      |> Enum.sort(&plural_sorter/2)

    {String.to_atom(locale), sorted_rules}
  end

  defp plural_sorter({:zero, _}, _), do: true
  defp plural_sorter({:one, _}, {other, _}) when other in [:two, :few, :many, :other], do: true
  defp plural_sorter({:two, _}, {other, _}) when other in [:few, :many, :other], do: true
  defp plural_sorter({:few, _}, {other, _}) when other in [:many, :other], do: true
  defp plural_sorter({:many, _}, {other, _}) when other in [:other], do: true
  defp plural_sorter(_, _), do: false
end
