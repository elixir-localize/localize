defmodule Localize.Inflection.ConceptList.Spanish do
  @moduledoc false

  # Spanish conjunctions: y becomes e before an i-sound unless the
  # i-sound opens a diphthong (Hierro, Yeso), and o becomes u
  # before an o-sound with no diphthong exception.

  @behaviour Localize.Inflection.ConceptList.Conjunction

  alias Localize.Inflection.ConceptList.Conjunction
  alias Localize.Inflection.SpeakableString

  @i_sound ~c"iyíIYÍ"
  @o_sound ~c"oóOÓ"
  @spanish_vowels ~c"aeiouAEIOU"

  @impl true
  def before_last(:and, _formatted_second_to_last, formatted_last) do
    print = SpeakableString.print(formatted_last)

    if Conjunction.starts_with_sets?(print, @i_sound, [{:not, @spanish_vowels}]) do
      " e "
    else
      " y "
    end
  end

  def before_last(:or, _formatted_second_to_last, formatted_last) do
    print = SpeakableString.print(formatted_last)

    if Conjunction.starts_with_sets?(print, @o_sound, []) do
      " u "
    else
      " o "
    end
  end
end
