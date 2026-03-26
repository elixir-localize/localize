defmodule Localize.Data.Normalize.LanguageNames do
  @moduledoc false

  alias Localize.Utils.Map, as: LMap
  alias Localize.Data.Normalize.Helpers

  def normalize(content, _locale) do
    languages =
      content
      |> get_in(["locale_display_names", "languages"])
      |> Helpers.default([])
      |> Helpers.group_alt_content(&canonical_locale_name/1)
      |> LMap.rename_keys("default", "standard")

    Map.put(content, "languages", languages)
  end

  defp canonical_locale_name(name) do
    name
    |> Localize.LanguageTag.parse!()
    |> Localize.LanguageTag.to_string()
  end
end
