defmodule Localize.Inflection.ConceptList.Hebrew do
  @moduledoc false

  # Hebrew and-lists: the vav prefixes a Hebrew word directly
  # (שלוש וארבע) but takes a hyphen before Latin or digit items
  # (3 ו-4). The test is whether the item contains any
  # Hebrew-script codepoint.

  @behaviour Localize.Inflection.ConceptList.Conjunction

  alias Localize.Inflection.SpeakableString

  @impl true
  def before_last(:and, _formatted_second_to_last, formatted_last) do
    if SpeakableString.print(formatted_last) =~ ~r/\p{Hebrew}/u do
      " ו"
    else
      " ו-"
    end
  end
end
