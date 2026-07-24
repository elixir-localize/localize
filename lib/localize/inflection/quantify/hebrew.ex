defmodule Localize.Inflection.Quantify.Hebrew do
  @moduledoc false

  # Hebrew quantification, ported from `HeCommonConceptFactory`:
  # the base number-constraint behavior with a Hebrew join — the
  # noun comes first for one (מכונית אחת), a few inherently
  # quantified time words are never joined with a number at all,
  # and gender/definiteness-specific numeral spellout is the
  # caller's number-formatting responsibility.

  alias Localize.Inflection.SpeakableString
  alias Localize.Inflection.Quantify.Base

  # Inherently quantified words: month, two-months, two-days. The
  # noun stands alone; the number is dropped.
  @dont_quantify ["חודש", "חודשיים", "יומיים"]

  def quantify_formatted(formatted_number, category, state) do
    if state.single_category? do
      Base.quantify_type(formatted_number, :other, true, state, &join/4)
    else
      Base.quantify_type(formatted_number, category, false, state, &join/4)
    end
  end

  defp join(formatted_number, noun, _measure_word, category) do
    cond do
      SpeakableString.print(noun) in @dont_quantify ->
        noun

      category == :one ->
        noun |> SpeakableString.concat(" ") |> SpeakableString.concat(formatted_number)

      true ->
        formatted_number |> SpeakableString.concat(" ") |> SpeakableString.concat(noun)
    end
  end
end
