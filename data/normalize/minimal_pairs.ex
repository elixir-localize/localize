defmodule Localize.Data.Normalize.MinimalPairs do
  @moduledoc false

  # CLDR's minimal pairs are short translated phrases showing a plural,
  # ordinal, case or gender form in context — `"{0} day"` against `"{0} days"`
  # for English cardinals. TR35 describes four categories, but the JSON
  # flattens all of them into one `minimalPairs` map: cardinals keep a
  # `pluralMinimalPairs-count-` prefix and everything else appears under a
  # bare key. Ordinals, cases and genders are told apart by the key itself,
  # which is unambiguous because the three vocabularies do not overlap.
  #
  # Keys reach this normalizer already underscored, so the cardinal prefix is
  # `plural_minimal_pairs_count_`.

  @plural_categories ~w(zero one two few many other)a

  @genders ~w(masculine feminine neuter common animate inanimate personal)a

  @cases ~w(
    ablative accusative causal comitative dative delative elative ergative
    essive genitive illative inessive instrumental locative nominative
    oblique partitive prepositional sociative sublative superessive
    terminative translative vocative
  )a

  def normalize(content, _locale) do
    pairs =
      content
      |> get_in(["numbers", "minimal_pairs"])
      |> classify()

    Map.put(content, "minimal_pairs", pairs)
  end

  defp classify(nil), do: %{}

  defp classify(pairs) when is_map(pairs) do
    Enum.reduce(pairs, %{}, fn {key, phrase}, acc ->
      case category(key) do
        nil ->
          acc

        {category, name} ->
          Map.update(acc, category, %{name => phrase}, &Map.put(&1, name, phrase))
      end
    end)
  end

  defp category("plural_minimal_pairs_count_" <> count) do
    with name when not is_nil(name) <- existing_atom(count), do: {:cardinal, name}
  end

  defp category(key) do
    case existing_atom(key) do
      nil -> nil
      name when name in @plural_categories -> {:ordinal, name}
      name when name in @genders -> {:gender, name}
      name when name in @cases -> {:case, name}
      _unknown_vocabulary -> nil
    end
  end

  # The keys come from CLDR data rather than user input, but they are still
  # file content, and a new grammatical term appearing upstream must not be
  # able to grow the atom table. An unrecognised key is dropped instead.
  defp existing_atom(string) do
    Localize.Utils.Helpers.existing_atom(string)
  end
end
