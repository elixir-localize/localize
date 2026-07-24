defmodule Localize.Inflection.Quantify.Arabic do
  @moduledoc false

  # Arabic quantification, ported from `ArCommonConceptFactory`:
  # the counted noun's number is dual for two and — perhaps
  # surprisingly — singular after 11-99 (the many category); its
  # case is governed by the count through the case map below; and
  # for one and two the number is dropped entirely (the noun form
  # alone carries the count: رسالتان "two messages").

  alias Localize.Inflection.{Concept, Quantify, SpeakableString}

  # CASE_MAP[base case of the concept][category]: the case the
  # counted noun takes. The base case is the explicit case
  # CONSTRAINT (nominative when absent or unrecognized).
  @case_map %{
    "nominative" => %{
      zero: "genitive",
      one: "nominative",
      two: "nominative",
      few: "genitive",
      many: "accusative",
      other: "genitive"
    },
    "genitive" => %{
      zero: "genitive",
      one: "genitive",
      two: "genitive",
      few: "genitive",
      many: "accusative",
      other: "genitive"
    },
    "accusative" => %{
      zero: "genitive",
      one: "accusative",
      two: "genitive",
      few: "genitive",
      many: "accusative",
      other: "genitive"
    }
  }

  def quantify_formatted(formatted_number, category, state) do
    concept = state.concept

    number_constraint =
      case category do
        :two -> "dual"
        :few -> "plural"
        _other -> "singular"
      end

    base_case =
      case Map.get(concept.constraints, "case") do
        "genitive" -> "genitive"
        "accusative" -> "accusative"
        _other -> "nominative"
      end

    case_constraint = @case_map |> Map.fetch!(base_case) |> Map.fetch!(category)

    noun =
      Quantify.constrained_render(concept, [
        {"number", number_constraint},
        {"case", case_constraint}
      ]) || Concept.to_speakable_string(concept)

    join(formatted_number, noun, category)
  end

  # For one and two the formatted number is dropped entirely.
  defp join(_formatted_number, noun, category) when category in [:one, :two], do: noun

  defp join(formatted_number, noun, _category) do
    formatted_number |> SpeakableString.concat(" ") |> SpeakableString.concat(noun)
  end
end
