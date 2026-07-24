defmodule Localize.Inflection.PhraseDisplay do
  @moduledoc false

  # Port of the upstream `PhraseDisplayFunction`, the generic
  # dictionary-driven display function shared by Urdu, Gujarati,
  # Kannada, Marathi, Punjabi and Telugu. There is no heuristic
  # guessing: with guessing enabled a failed inflection keeps the
  # original string.

  alias Localize.Inflection.{Dictionary, DisplayValue, Inflector, Tokenizer}

  @doc """
  Applies case/number/gender constraints to the display value via
  dictionary inflection.

  ### Options

  * `:priorities` is the grammeme priority table list.

  """
  def display_value(locale, display_data, constraints, options) do
    with %DisplayValue{} = display_value <- List.first(display_data),
         display_string when display_string != "" <- display_value.display_string do
      value_constraints = Map.merge(display_value.constraints, constraints)

      wants_inflection? =
        Enum.any?(["case", "number", "gender"], &(Map.get(constraints, &1) not in [nil, ""]))

      result =
        if wants_inflection? do
          case Dictionary.combined_grammemes(locale, display_string) do
            nil ->
              {:ok, inflect_compound(locale, display_string, constraints, options)}

            grammemes ->
              case inflect_word(locale, display_string, grammemes, constraints, options) do
                {:ok, inflected} -> {:ok, inflected}
                :error -> :error
              end
          end
        else
          {:ok, display_string}
        end

      case result do
        {:ok, inflected} ->
          %DisplayValue{display_string: inflected, constraints: value_constraints}

        :error ->
          %DisplayValue{display_string: display_string, constraints: value_constraints}
      end
    else
      _other -> nil
    end
  end

  defp inflect_word(locale, word, grammemes, constraints, options) do
    constraint_values =
      for feature <- ["case", "number", "gender"],
          value = Map.get(constraints, feature),
          value not in [nil, ""],
          do: value

    disambiguation = for value <- [Map.get(constraints, "pos")], value not in [nil, ""], do: value

    Inflector.inflect(locale, word, grammemes, constraint_values,
      disambiguation: disambiguation,
      priorities: Keyword.get(options, :priorities, [])
    )
  end

  defp inflect_compound(locale, display_string, constraints, options) do
    tokens = Tokenizer.word_tokens(locale, display_string)

    {output, position} =
      Enum.reduce(tokens, {"", 0}, fn token, {output, position} ->
        separator = binary_part(display_string, position, token.start - position)
        grammemes = Dictionary.combined_grammemes(locale, token.value) || 0

        inflected =
          case inflect_word(locale, token.value, grammemes, constraints, options) do
            {:ok, value} -> value
            :error -> token.value
          end

        {output <> separator <> inflected, token.stop}
      end)

    output <> binary_part(display_string, position, byte_size(display_string) - position)
  end
end
