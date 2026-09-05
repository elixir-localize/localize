defmodule Localize.Data.Normalize.Rbnf do
  @moduledoc false

  @default_radix 10

  def normalize(content, locale) do
    case rbnf_for_locale(locale) do
      {:error, _} -> Map.put(content, "rbnf", %{})
      {:ok, rules} -> Map.put(content, "rbnf", structure_rbnf(rules))
    end
  end

  defp rbnf_for_locale(locale) do
    path = rbnf_locale_path(locale)

    if File.exists?(path) do
      rules =
        path
        |> File.read!()
        |> :json.decode()
        |> Map.get("rbnf")
        |> Map.get("rbnf")
        |> resolve_rule_files(Path.dirname(path))
        |> rules_from_rule_sets()

      {:ok, rules}
    else
      {:error, :not_found}
    end
  end

  defp rbnf_locale_path(locale) do
    Path.join([Localize.Data.locales_source_dir(), locale, "rbnf.json"])
  end

  # Until CLDR 48 each rule group in `rbnf.json` carried its rulesets inline.
  # CLDR 49 externalised them: a group is now `%{"_rbnfRulesFile" => "en-
  # SpelloutRules.txt"}` naming an ICU-syntax file beside the JSON. Both shapes
  # are handled — a group with a pointer is read from the file, and one with
  # rules already present is passed through, so the normalizer works against
  # either vintage of source data.
  defp resolve_rule_files(groups, directory) do
    Map.new(groups, fn
      {group, %{"_rbnfRulesFile" => file}} when is_binary(file) ->
        {group, read_rule_file(Path.join(directory, file))}

      {group, sets} ->
        {group, sets}
    end)
  end

  defp read_rule_file(path) do
    if File.exists?(path) do
      path
      |> File.read!()
      |> parse_rule_file()
    else
      %{}
    end
  end

  # The file is a flat sequence of ruleset headers (`%spellout-cardinal:`, or
  # `%%` for a private one) each followed by its rules, one per line, as
  # `name: definition;`. Across all 147 files CLDR 49 ships there is nothing
  # else — no comments, no blank lines, no rule spanning two lines — and no
  # rule name contains a colon, so the first one separates name from
  # definition. The output matches the shape the JSON used to provide:
  # `%{ruleset_name => [[rule_name, definition], ...]}`.
  defp parse_rule_file(contents) do
    contents
    |> String.split("\n", trim: true)
    |> Enum.reduce({nil, %{}}, fn line, {current, sets} ->
      case parse_rule_line(line) do
        {:ruleset, name} ->
          {name, Map.put_new(sets, name, [])}

        {:rule, rule} when is_binary(current) ->
          {current, Map.update!(sets, current, &[rule | &1])}

        _rule_before_any_ruleset ->
          {current, sets}
      end
    end)
    |> elem(1)
    |> Map.new(fn {name, rules} -> {name, Enum.reverse(rules)} end)
  end

  defp parse_rule_line(line) do
    trimmed = String.trim_trailing(line)

    cond do
      String.starts_with?(trimmed, "%") and String.ends_with?(trimmed, ":") ->
        {:ruleset, String.trim_trailing(trimmed, ":")}

      true ->
        case String.split(trimmed, ":", parts: 2) do
          [name, definition] -> {:rule, [name, String.trim_leading(definition)]}
          _not_a_rule -> :skip
        end
    end
  end

  defp structure_rbnf(rules) do
    rules
    |> Enum.map(fn {group, sets} ->
      {group, structure_sets(sets)}
    end)
    |> Map.new()
  end

  defp structure_sets(sets) do
    sets
    |> Enum.map(fn {name, set} ->
      {Localize.Utils.Map.underscore(name), Map.put(set, :rules, set[:rules])}
    end)
    |> Map.new()
  end

  defp rules_from_rule_sets(rule_sets) do
    Enum.map(rule_sets, fn {group, sets} ->
      {String.to_atom(group), rules_from_one_group(sets)}
    end)
    |> Enum.reject(&is_nil/1)
    |> Map.new()
  end

  defp rules_from_one_group(sets) do
    sets
    |> Enum.reject(fn {_set, rules} -> is_binary(rules) end)
    |> Enum.map(fn {set, rules} ->
      access = access_from_set(set)
      {function_name_from(set), %{access: access, rules: rules_from(rules)}}
    end)
    |> Enum.reject(&is_nil/1)
    |> Map.new()
  end

  defp access_from_set(<<"%%", _rest::binary>>), do: :private
  defp access_from_set(_), do: :public

  defp rules_from(rules) do
    Enum.map(rules, fn [name, rule] ->
      {base_value, radix} = radix_from_name(name)
      %{base_value: base_value, radix: radix, definition: remove_trailing_semicolon(rule)}
    end)
    |> sort_rules()
    |> set_range()
    |> set_divisor()
  end

  defp sort_rules(rules) do
    Enum.sort(rules, fn a, b ->
      cond do
        is_binary(a.base_value) -> true
        is_binary(b.base_value) -> false
        a.base_value < b.base_value -> true
        true -> false
      end
    end)
  end

  defp radix_from_name(name) do
    case String.split(name, "/") do
      [base_value, radix] ->
        {to_integer(base_value), to_integer(radix)}

      [base_value] ->
        {to_integer(base_value), @default_radix}
    end
  end

  defp to_integer(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> value
    end
  end

  defp remove_trailing_semicolon(text) do
    String.replace_suffix(text, ";", "")
  end

  defp set_range([rule | [next_rule | rest]]) do
    [Map.put(rule, :range, range_from_next_rule(rule.base_value, next_rule.base_value))] ++
      set_range([next_rule] ++ rest)
  end

  defp set_range([rule | []]) do
    [Map.put(rule, :range, "undefined")]
  end

  defp range_from_next_rule(rule, next_rule) when is_number(rule) and is_number(next_rule) do
    next_rule
  end

  defp range_from_next_rule(_rule, _next_rule), do: "undefined"

  defp set_divisor([rule]) do
    [Map.put(rule, :divisor, divisor(rule.base_value, rule.radix))]
  end

  defp set_divisor([rule | rest]) do
    [Map.put(rule, :divisor, divisor(rule.base_value, rule.radix)) | set_divisor(rest)]
  end

  defp divisor(base_value, radix) when is_integer(base_value) and is_integer(radix) do
    exponent =
      if base_value > 0 do
        Float.ceil(:math.log(base_value) / :math.log(radix)) |> trunc()
      else
        1
      end

    divisor =
      if exponent > 0 do
        trunc(:math.pow(radix, exponent))
      else
        1
      end

    if divisor > base_value do
      trunc(:math.pow(radix, exponent - 1))
    else
      divisor
    end
  end

  defp divisor(_base_value, _radix), do: nil

  defp function_name_from(set) do
    set
    |> String.trim_leading("%")
    |> Localize.Utils.String.to_underscore()
    |> String.to_atom()
  end
end
