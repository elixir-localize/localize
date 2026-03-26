defmodule Localize.Data.Normalize.Layout do
  @moduledoc false

  alias Localize.Utils.Map, as: LMap

  def normalize(content, _locale) do
    layout =
      content
      |> get_in(["layout", "orientation"])
      |> LMap.deep_map(fn
        {"character_order", "right-to-left"} -> {"character_order", "rtl"}
        {"character_order", "left-to-right"} -> {"character_order", "ltr"}
        {"line_order", "top-to-bottom"} -> {"line_order", "ttb"}
        {"line_order", "bottom-to-top"} -> {"line_order", "btt"}
        other -> other
      end)
      |> Map.new()
      |> LMap.atomize_values()
      |> LMap.atomize_keys()

    Map.put(content, "layout", layout)
  end
end
