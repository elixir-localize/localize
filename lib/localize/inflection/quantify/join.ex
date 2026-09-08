defmodule Localize.Inflection.Quantify.Join do
  @moduledoc false

  # Languages whose quantify differs from the base only in how the
  # number, noun and measure word are joined: Italian (no space
  # after the indefinite article for one), Malayalam (noun first
  # for one), Japanese/Mandarin/Cantonese (number + classifier +
  # noun, no separators), Korean (spacing decided by the noun's
  # first character, classifier after the noun), and Thai (noun +
  # number + classifier).

  alias Localize.Inflection.Quantify.Base
  alias Localize.Inflection.SpeakableString

  def quantify_formatted(formatted_number, category, state) do
    join = join_function(state.config.join)

    if state.single_category? do
      Base.quantify_type(formatted_number, :other, true, state, join)
    else
      Base.quantify_type(formatted_number, category, false, state, join)
    end
  end

  defp join_function(:no_space_for_one) do
    fn formatted, noun, _measure, category ->
      # The Italian indefinite article carries its own separator
      # ("un ", "un’"), so one joins without a space.
      case category do
        :one -> SpeakableString.concat(formatted, noun)
        _other -> Base.join(formatted, noun, "", category)
      end
    end
  end

  defp join_function(:noun_first_for_one) do
    fn formatted, noun, _measure, category ->
      case category do
        :one -> noun |> SpeakableString.concat(" ") |> SpeakableString.concat(formatted)
        _other -> Base.join(formatted, noun, "", category)
      end
    end
  end

  defp join_function(:number_measure_noun) do
    fn formatted, noun, measure, _category ->
      formatted |> SpeakableString.concat(measure) |> SpeakableString.concat(noun)
    end
  end

  defp join_function(:noun_number_measure) do
    fn formatted, noun, measure, _category ->
      quantified = noun |> SpeakableString.concat(" ") |> SpeakableString.concat(formatted)

      if measure == "" do
        quantified
      else
        quantified |> SpeakableString.concat(" ") |> SpeakableString.concat(measure)
      end
    end
  end

  defp join_function(:korean) do
    fn formatted, noun, measure, _category ->
      # A noun starting with a Hangul/CJK character joins without
      # spaces; the classifier follows the noun either way.
      spaces? = not no_whitespace?(SpeakableString.print(noun))
      space = if spaces?, do: " ", else: ""

      quantified =
        formatted |> SpeakableString.concat(space) |> SpeakableString.concat(noun)

      if measure == "" do
        quantified
      else
        quantified |> SpeakableString.concat(space) |> SpeakableString.concat(measure)
      end
    end
  end

  defp no_whitespace?(<<codepoint::utf8, _rest::binary>>) do
    <<codepoint::utf8>> =~ ~r/[\p{Hangul}\p{Han}\p{Hiragana}\p{Katakana}]/u
  end

  defp no_whitespace?(_other), do: false
end
