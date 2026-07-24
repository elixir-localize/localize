defmodule Localize.Inflection.Quantify.Finnish do
  @moduledoc false

  # Finnish quantification, ported from `FiCommonConceptFactory`:
  # counted nouns above one take the partitive (3 taloa), unless
  # the concept carries a non-nominative case; plural is used when
  # the caller asked for it or the head word is a plurale tantum
  # (sakset, häät — words with no singular forms).

  alias Localize.Inflection.{Concept, Dictionary, Quantify, SpeakableString}

  import Bitwise

  def quantify_formatted(formatted_number, category, state) do
    concept = state.concept
    case_value = Quantify.feature_print(concept, "case")
    use_plural? = use_plural?(concept)

    constraints =
      [{"number", if(use_plural?, do: "plural", else: "singular")}] ++
        if case_value in ["", "nominative"] and not use_plural? and category != :one do
          [{"case", "partitive"}]
        else
          []
        end

    noun =
      Quantify.constrained_render(concept, constraints) ||
        Concept.to_speakable_string(concept)

    formatted_number |> SpeakableString.concat(" ") |> SpeakableString.concat(noun)
  end

  # Plural when explicitly constrained plural, or when the bare
  # head word is a plurale tantum or dictionary-marked plural.
  defp use_plural?(concept) do
    case Map.get(concept.constraints, "number") do
      "plural" ->
        true

      _other ->
        head_word = concept |> bare() |> Concept.to_speakable_string() |> SpeakableString.print()
        head_word != "" and (plurale_tantum?(head_word) or marked_plural?(head_word))
    end
  end

  defp bare(concept) do
    %{concept | constraints: %{}}
  end

  # A plurale tantum has at least one inflection pattern with no
  # singular forms at all.
  defp plurale_tantum?(word) do
    singular = Dictionary.binary_properties(:fi, ["singular"]) || 0

    case Dictionary.patterns_for_word(:fi, word) do
      [] ->
        false

      patterns ->
        Enum.any?(patterns, fn pattern ->
          Enum.all?(pattern.inflections, fn {grammemes, _suffix} ->
            (grammemes &&& singular) == 0
          end)
        end)
    end
  end

  defp marked_plural?(word) do
    plural = Dictionary.binary_properties(:fi, ["plural"]) || 0
    singular = Dictionary.binary_properties(:fi, ["singular"]) || 0

    case Dictionary.combined_grammemes(:fi, word) do
      nil -> false
      grammemes -> (grammemes &&& plural) != 0 and (grammemes &&& singular) == 0
    end
  end
end
