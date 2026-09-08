defmodule Localize.Inflection.ConceptList.Korean do
  @moduledoc false

  # Korean and-lists: the particle 과/와 attaches to the
  # second-to-last item and follows its final sound — 와 after a
  # vowel-final syllable, 과 after a consonant-final one.

  @behaviour Localize.Inflection.ConceptList.Conjunction

  alias Localize.Inflection.{PhraseProperties, SpeakableString}

  @impl true
  def before_last(:and, formatted_second_to_last, _formatted_last) do
    print = SpeakableString.print(formatted_second_to_last)

    if PhraseProperties.ends_with_vowel?(:ko, print) do
      "와 "
    else
      "과 "
    end
  end
end
