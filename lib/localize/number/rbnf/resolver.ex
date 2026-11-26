defmodule Localize.Number.Rbnf.Resolver do
  @moduledoc false

  # Chooses the rule set a request names in one locale's public rule sets.
  #
  # A family request — `:ordinal`, `:spellout`, or a family's own name
  # such as `:spellout_ordinal` — is resolved by the grammatical features
  # each rule-set name marks (`Localize.Number.Rbnf.RuleSetName`), never by
  # the alphabetical order of the names:
  #
  # 1. With no grammatical options and an unmarked rule set in the family
  #    (`digits-ordinal`), that rule set, as CLDR intends.
  #
  # 2. Otherwise the request is filled with the defaults of the features
  #    the family varies on — nominative, singular, indefinite — and a
  #    feature the family does not vary on is ignored.
  #
  # 3. The rule sets that agree with every requested feature are kept. An
  #    unmarked gender agrees with any gender, since that form does not
  #    vary by it, and a requested `:inanimate` agrees with `:masculine`,
  #    the unmarked masculine.
  #
  # 4. The one that marks the most of the requested features wins, then
  #    the gender earliest in `@gender_order`, then the one with the
  #    fewest features.
  #
  # Any other name is that rule set exactly, and grammatical options with
  # it are an error rather than silently ignored.

  alias Localize.Number.Rbnf.RuleSetName

  @families %{
    "ordinal" => [:digits_ordinal, :spellout_ordinal],
    "spellout" => [:spellout_numbering, :spellout_cardinal],
    "digits_ordinal" => [:digits_ordinal],
    "spellout_ordinal" => [:spellout_ordinal],
    "spellout_cardinal" => [:spellout_cardinal],
    "spellout_numbering" => [:spellout_numbering]
  }

  # The gender chosen when the caller asks for none and the family has no
  # unmarked rule set. An ungendered form comes first; then masculine, as
  # 12 of CLDR's 15 locales with gendered digit ordinals point their
  # unmarked rule set at it.
  @gender_order [nil, :masculine, :inanimate, :common, :neuter, :feminine, :animate, :personal]

  @defaults %{
    grammatical_case: :nominative,
    grammatical_number: :singular,
    grammatical_definiteness: :indefinite
  }

  @type grammar :: %{optional(Localize.GrammaticalFeature.feature()) => atom()}

  # The rule-set name to format with, `:not_found` when the locale has
  # nothing for the request (so its parent is looked in), or an error
  # when it has the family but no rule set agreeing with the request.
  # `public_names` are the locale's public rule-set names, hyphenated.
  @spec resolve(atom() | String.t(), grammar(), [String.t()], atom()) ::
          {:ok, String.t()} | :not_found | {:error, Exception.t()}
  def resolve(rule_name, grammar, public_names, locale_id) do
    key = family_key(rule_name)

    case Map.fetch(@families, key) do
      {:ok, families} -> resolve_family(families, rule_name, grammar, public_names, locale_id)
      :error -> exact(rule_name, grammar)
    end
  end

  defp family_key(rule_name) when is_atom(rule_name) do
    rule_name
    |> Atom.to_string()
    |> family_key()
  end

  defp family_key(rule_name) when is_binary(rule_name) do
    String.replace(rule_name, "-", "_")
  end

  defp exact(rule_name, grammar) when map_size(grammar) == 0 do
    {:ok, name_string(rule_name)}
  end

  defp exact(rule_name, grammar) do
    {:error,
     Localize.InvalidValueError.exception(
       value: grammar,
       expected:
         "no grammatical options with the rule set #{inspect(name_string(rule_name))}, " <>
           "which names one rule set; give a family such as :ordinal or :spellout_cardinal",
       context: "Localize.Number.Rbnf.to_string/3"
     )}
  end

  defp name_string(rule_name) when is_atom(rule_name), do: Atom.to_string(rule_name)
  defp name_string(rule_name) when is_binary(rule_name), do: rule_name

  defp resolve_family([], _rule_name, _grammar, _public_names, _locale_id) do
    :not_found
  end

  defp resolve_family([family | rest], rule_name, grammar, public_names, locale_id) do
    case candidates(family, public_names) do
      [] -> resolve_family(rest, rule_name, grammar, public_names, locale_id)
      candidates -> choose(candidates, rule_name, grammar, locale_id)
    end
  end

  defp candidates(family, public_names) do
    for name <- public_names,
        {:ok, ^family, features} <- [RuleSetName.parse(name)],
        do: {name, features}
  end

  defp choose(candidates, rule_name, grammar, locale_id) do
    unmarked = unmarked(candidates)

    if map_size(grammar) == 0 and not is_nil(unmarked) do
      {:ok, unmarked}
    else
      request = request(candidates, grammar)

      candidates
      |> Enum.filter(fn {_name, features} -> agrees?(features, request) end)
      |> best(grammar)
      |> chosen(candidates, rule_name, grammar, locale_id)
    end
  end

  defp unmarked(candidates) do
    Enum.find_value(candidates, fn
      {name, features} when map_size(features) == 0 -> name
      _marked -> nil
    end)
  end

  # The caller's features and the defaults, for the features the family
  # varies on.
  defp request(candidates, grammar) do
    candidates
    |> Enum.flat_map(fn {_name, features} -> Map.keys(features) end)
    |> Enum.uniq()
    |> Enum.flat_map(&requested(&1, grammar))
    |> Map.new()
  end

  defp requested(feature, grammar) do
    case Map.get(grammar, feature, Map.get(@defaults, feature)) do
      nil -> []
      value -> [{feature, value}]
    end
  end

  defp agrees?(features, request) do
    Enum.all?(request, fn {feature, value} ->
      agrees_on?(feature, Map.get(features, feature), value)
    end)
  end

  defp agrees_on?(_feature, value, value), do: true
  defp agrees_on?(:grammatical_gender, nil, _value), do: true
  defp agrees_on?(:grammatical_gender, :masculine, :inanimate), do: true
  defp agrees_on?(feature, nil, value), do: Map.get(@defaults, feature) == value
  defp agrees_on?(_feature, _marked, _value), do: false

  defp best([], _grammar) do
    nil
  end

  defp best(agreeing, grammar) do
    {name, _features} = Enum.min_by(agreeing, &score(&1, grammar))
    name
  end

  # Most of the caller's features marked, then the gender order, then the
  # fewest features, then the name, so the choice never depends on the
  # order the names came in.
  defp score({name, features}, grammar) do
    marked = Enum.count(grammar, fn {feature, _value} -> Map.has_key?(features, feature) end)
    gender = Enum.find_index(@gender_order, &(&1 == Map.get(features, :grammatical_gender)))

    {-marked, gender, map_size(features), name}
  end

  defp chosen(nil, candidates, rule_name, grammar, locale_id) do
    {:error, no_agreement(candidates, rule_name, grammar, locale_id)}
  end

  defp chosen(name, _candidates, _rule_name, _grammar, _locale_id) do
    {:ok, name}
  end

  # Name the first feature no rule set in the family has the value for,
  # with the values it does have; failing that, the family's rule sets.
  defp no_agreement(candidates, rule_name, grammar, locale_id) do
    Enum.find_value(grammar, fn {feature, value} ->
      unavailable(candidates, feature, value)
    end) ||
      Localize.UnknownRbnfRuleError.exception(
        rule_name: rule_name,
        locale: locale_id,
        available: Enum.map(candidates, &elem(&1, 0))
      )
  end

  defp unavailable(candidates, feature, value) do
    if Enum.any?(candidates, fn {_name, features} ->
         agrees_on?(feature, Map.get(features, feature), value)
       end) do
      nil
    else
      Localize.InvalidValueError.exception(
        value: value,
        expected: feature,
        allowed_values: available_values(candidates, feature),
        context: "Localize.Number.Rbnf.to_string/3"
      )
    end
  end

  defp available_values(candidates, feature) do
    marked =
      for {_name, features} <- candidates,
          value = Map.get(features, feature),
          not is_nil(value),
          uniq: true,
          do: value

    default = Map.get(@defaults, feature)

    [default | marked]
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort()
  end
end
