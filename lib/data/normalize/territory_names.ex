defmodule Localize.Data.Normalize.TerritoryNames do
  @moduledoc false

  alias Localize.Utils.Map, as: LMap
  alias Localize.Data.Normalize.Helpers

  def normalize(content, _locale) do
    territories =
      content
      |> get_in(["locale_display_names", "territories"])
      |> Helpers.group_alt_content(&String.upcase/1)
      |> LMap.rename_keys("default", "standard")
      |> LMap.atomize_keys()

    Map.put(content, "territories", territories)
  end
end
