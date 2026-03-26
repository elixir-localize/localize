defmodule Localize.Data.Normalize.LenientParse do
  @moduledoc false

  def normalize(content, _locale) do
    date = get_in(content, ["characters", "lenient_scope_date"])
    general = get_in(content, ["characters", "lenient_scope_general"])
    number = get_in(content, ["characters", "lenient_scope_number"])

    lenient_parse = %{
      date: date,
      general: general,
      number: number
    }

    Map.put(content, "lenient_parse", lenient_parse)
  end
end
