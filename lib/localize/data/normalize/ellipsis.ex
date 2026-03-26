defmodule Localize.Data.Normalize.Ellipsis do
  @moduledoc false

  alias Localize.Utils.Map, as: LMap

  def normalize(content, _locale) do
    ellipsis =
      content
      |> get_in(["characters", "ellipsis"])
      |> Enum.map(fn {type, data} -> {type, Localize.Substitution.parse(data)} end)
      |> Map.new()
      |> LMap.atomize_keys()

    Map.put(content, "ellipsis", ellipsis)
  end
end
