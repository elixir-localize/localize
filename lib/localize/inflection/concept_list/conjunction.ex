defmodule Localize.Inflection.ConceptList.Conjunction do
  @moduledoc false

  # Behaviour for dynamic list conjunctions: the before-last
  # separator chosen per render from the neighboring formatted
  # items, as the upstream custom SemanticConceptList subclasses
  # do by overriding getBeforeLast.

  alias Localize.Inflection.SpeakableString

  @callback before_last(
              kind :: :and | :or,
              formatted_second_to_last :: SpeakableString.t(),
              formatted_last :: SpeakableString.t()
            ) :: SpeakableString.t()

  @doc """
  Scans `string` for phonetic set membership, as the upstream
  isStartsWithUnicodeSets: codepoints outside the important class
  (letters and digits, excluding the silent h/H) are skipped; the
  first important codepoint must belong to `first_set`, and each
  set in `remaining_sets` must match the following important
  codepoints in order.

  """
  def starts_with_sets?(string, first_set, remaining_sets) do
    codepoints = string |> String.to_charlist() |> Enum.filter(&important?/1)

    case codepoints do
      [first | rest] ->
        member?(first, first_set) and match_remaining?(rest, remaining_sets)

      [] ->
        false
    end
  end

  defp match_remaining?(_codepoints, []), do: true

  defp match_remaining?([codepoint | rest], [set | sets]) do
    member?(codepoint, set) and match_remaining?(rest, sets)
  end

  defp match_remaining?([], _sets), do: false

  # A set is a codepoint list, or {:not, list} for its complement
  # within the important class (the Spanish non-vowel test).
  defp member?(codepoint, {:not, set}), do: codepoint not in set
  defp member?(codepoint, set), do: codepoint in set

  defp important?(codepoint) when codepoint in [?h, ?H], do: false

  defp important?(codepoint) do
    <<codepoint::utf8>> =~ ~r/[[:alpha:][:digit:]]/u
  end
end
