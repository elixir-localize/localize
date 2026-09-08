defmodule Localize.Inflection.ConceptList.Italian do
  @moduledoc false

  # Italian and-lists: e becomes ed when the last item starts
  # (h-blind) with an e-sound: aereo ed elicottero.

  @behaviour Localize.Inflection.ConceptList.Conjunction

  alias Localize.Inflection.ConceptList.Conjunction
  alias Localize.Inflection.SpeakableString

  @e_sound ~c"eèéEÈÉ"

  @impl true
  def before_last(:and, _formatted_second_to_last, formatted_last) do
    print = SpeakableString.print(formatted_last)

    if Conjunction.starts_with_sets?(print, @e_sound, []) do
      " ed "
    else
      " e "
    end
  end
end
