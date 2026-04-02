defmodule Localize.Data.Normalize.NestedBrackets do
  @moduledoc false

  def normalize(content, _locale) do
    nested_bracket_replacement =
      content
      |> get_in(["characters", "nested_bracket_replacement"])
      |> case do
        nil -> %{}
        map when is_map(map) -> map
      end

    Map.put(content, "nested_bracket_replacement", nested_bracket_replacement)
  end
end
