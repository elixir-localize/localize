defmodule Localize.Number.Rbnf do
  @moduledoc """
  Rules-Based Number Formatting (RBNF) for algorithmic number
  systems and spellout forms.

  RBNF provides formatting for number systems that don't have
  simple digit-to-digit mappings, such as Roman numerals, Hebrew
  numerals, Chinese numerals, and spellout forms like "one hundred
  twenty-three".

  RBNF rules are loaded from locale data at runtime and interpreted
  by `Localize.Number.Rbnf.Processor`. Parsed rule ASTs are cached
  in `:persistent_term` for performance.

  """

  alias Localize.Number.Rbnf.Processor
  alias Localize.Utils.Helpers

  @doc """
  Formats a number using RBNF rules.

  ### Arguments

  * `number` is an integer or float.

  * `rule_name` is the rule set name atom or string
    (e.g., `:spellout_cardinal`, `"roman-upper"`).

  * `options` is a keyword list of options.

  ### Options

  * `:locale` is a locale identifier. The default is `:en`.

  ### Returns

  * `{:ok, formatted_string}` on success.

  * `{:error, exception}` if the rules are not available.

  ### Examples

      iex> Localize.Number.Rbnf.to_string(123, :spellout_cardinal, locale: :en)
      {:ok, "one hundred twenty-three"}

  """
  @spec to_string(number(), atom() | String.t(), Keyword.t()) ::
          {:ok, String.t()} | {:error, Exception.t()}
  def to_string(number, rule_name, options \\ []) do
    locale = Keyword.get(options, :locale, Localize.get_locale())
    locale_id = to_locale_id(locale)
    rule_name_str = normalize_rule_name(rule_name)

    with {:ok, rbnf_data} <- load_rbnf_data(locale_id),
         {:ok, all_rule_sets} <- extract_rule_sets(rbnf_data),
         {:ok, rule_set} <- find_rule_set(all_rule_sets, rule_name_str) do
      Processor.process(number, rule_name_str, rule_set.rules, all_rule_sets)
    end
  end

  @doc """
  Returns the available RBNF rule names for a locale.

  ### Arguments

  * `locale` is a locale identifier atom or string.

  ### Returns

  * `{:ok, rule_names}` where `rule_names` is a list of
    strings.

  * `{:error, exception}` if RBNF data is not available.

  """
  @spec rule_names_for_locale(atom() | String.t()) ::
          {:ok, [String.t()]} | {:error, Exception.t()}
  def rule_names_for_locale(locale) do
    locale_id = to_locale_id(locale)

    with {:ok, rbnf_data} <- load_rbnf_data(locale_id),
         {:ok, all_rule_sets} <- extract_rule_sets(rbnf_data) do
      names =
        all_rule_sets
        |> Map.keys()
        |> Enum.map(&to_string_key/1)
        |> Enum.filter(fn name ->
          rule_set = all_rule_sets[name] || all_rule_sets[String.to_atom(name)]
          rule_set && Map.get(rule_set, :access, :public) == :public
        end)

      {:ok, names}
    end
  end

  # ── Private helpers ──────────────────────────────────────────

  defp load_rbnf_data(locale_id) do
    Localize.Locale.get(locale_id, [:rbnf])
  end

  defp extract_rule_sets(rbnf_data) when is_map(rbnf_data) do
    # RBNF data is organized by rule group type:
    # %{SpelloutRules: %{spellout_cardinal: %{access: "public", rules: [...]}}}
    # Flatten into a single map of rule_name => rule_set
    all_sets =
      Enum.reduce(rbnf_data, %{}, fn {_group_type, rule_sets}, acc ->
        if is_map(rule_sets) do
          Map.merge(acc, rule_sets)
        else
          acc
        end
      end)

    {:ok, all_sets}
  end

  defp extract_rule_sets(_), do: {:error, "No RBNF data available"}

  defp find_rule_set(all_rule_sets, rule_name_str) do
    # Try various key forms: string, atom, hyphenated, underscored
    rule_set =
      Map.get(all_rule_sets, rule_name_str) ||
        Map.get(all_rule_sets, safe_to_atom(rule_name_str)) ||
        Map.get(all_rule_sets, String.replace(rule_name_str, "_", "-")) ||
        Map.get(all_rule_sets, safe_to_atom(String.replace(rule_name_str, "_", "-"))) ||
        Map.get(all_rule_sets, String.replace(rule_name_str, "-", "_")) ||
        Map.get(all_rule_sets, safe_to_atom(String.replace(rule_name_str, "-", "_")))

    if rule_set do
      {:ok, %{rules: extract_rules(rule_set), access: Map.get(rule_set, :access, :public)}}
    else
      {:error,
       Localize.InvalidValueError.exception(
         value: rule_name_str,
         expected: "a known RBNF rule set",
         context: "Available: #{inspect(Map.keys(all_rule_sets))}"
       )}
    end
  end

  defp extract_rules(%{rules: rules}) when is_list(rules), do: rules
  defp extract_rules(%{"rules" => rules}) when is_list(rules), do: rules
  defp extract_rules(rule_set) when is_map(rule_set), do: Map.get(rule_set, :rules, [])

  defp normalize_rule_name(name) when is_atom(name), do: Atom.to_string(name)
  defp normalize_rule_name(name) when is_binary(name), do: name

  defp to_locale_id(locale), do: Localize.Locale.to_locale_id(locale)

  defp to_string_key(key) when is_atom(key), do: Atom.to_string(key)
  defp to_string_key(key) when is_binary(key), do: key

  defp safe_to_atom(string), do: Helpers.existing_atom(string)
end
