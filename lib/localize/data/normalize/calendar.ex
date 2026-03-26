defmodule Localize.Data.Normalize.Calendar do
  @moduledoc false

  alias Localize.Utils.Map, as: LMap

  @calendar_location ["dates", "calendars"]

  def normalize(content, _locale) do
    updated_content = normalize_calendar(content)
    put_in(content, @calendar_location, updated_content)
  end

  def normalize_calendar(content) do
    content
    |> get_in(@calendar_location)
    |> rename_day_name_keys()
    |> rename_era_keys()
    |> rename_variants()
  end

  defp rename_day_name_keys(content) do
    content
    |> LMap.rename_keys("mon", 1)
    |> LMap.rename_keys("tue", 2)
    |> LMap.rename_keys("wed", 3)
    |> LMap.rename_keys("thu", 4)
    |> LMap.rename_keys("fri", 5)
    |> LMap.rename_keys("sat", 6)
    |> LMap.rename_keys("sun", 7)
  end

  defp rename_era_keys(content) do
    content
    |> LMap.rename_keys("era_abbr", "abbreviated")
    |> LMap.rename_keys("era_narrow", "narrow")
    |> LMap.rename_keys("era_names", "wide")
  end

  defp rename_variants(content) do
    content
    |> LMap.rename_keys("0_alt_variant", -1)
    |> LMap.rename_keys("1_alt_variant", -2)
  end
end
