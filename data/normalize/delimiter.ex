defmodule Localize.Data.Normalize.Delimiter do
  @moduledoc false

  alias Localize.Data.Normalize.Helpers
  alias Localize.Utils.Map, as: LMap

  def normalize(content, _locale) do
    delimiters =
      content
      |> Map.fetch!("delimiters")
      |> LMap.rename_keys("alternate_quotation_start", "quotation_start_alt_variant")
      |> LMap.rename_keys("alternate_quotation_end", "quotation_end_alt_variant")
      |> Helpers.group_by_alt("quotation_start")
      |> Helpers.group_by_alt("quotation_end")
      |> LMap.atomize_keys()

    Map.put(content, "delimiters", delimiters)
  end
end
