defmodule Localize.Data.Normalize.NumberSystem do
  @moduledoc false

  alias Localize.Utils.Map, as: LMap

  def normalize(content, _locale) do
    numbers = content["numbers"]

    number_systems =
      %{"default" => numbers["default_numbering_system"]}
      |> Map.merge(numbers["other_numbering_systems"])
      |> Map.new()
      |> LMap.atomize_keys()
      |> LMap.atomize_values()

    Map.put(content, "number_systems", number_systems)
  end
end
