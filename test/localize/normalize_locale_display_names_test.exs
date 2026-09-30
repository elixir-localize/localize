defmodule Localize.Data.Normalize.LocaleDisplayNamesTest do
  @moduledoc """
  Covers the split of CLDR's `scope="core"` type names, which the CLDR
  JSON nests under `_core` among each key's type names.

  """

  use ExUnit.Case, async: true

  alias Localize.Data.Normalize.LocaleDisplayNames

  defp content do
    %{
      "locale_display_names" => %{
        "types" => %{
          "calendar" => %{
            "buddhist" => "Buddhist Calendar",
            "gregorian" => "Gregorian Calendar",
            "_core" => %{"buddhist" => "Buddhist", "gregorian" => "Gregorian"}
          },
          "ms" => %{
            "metric" => "Metric System",
            "uksystem" => "Imperial Measurement System",
            "_core" => %{"metric" => "Metric", "uksystem" => "UK"}
          },
          "numbers" => %{"arab" => "Arabic-Indic Digits"}
        }
      }
    }
  end

  test "moves each key's core names out of its type names" do
    display_names = LocaleDisplayNames.normalize(content(), "en")["locale_display_names"]

    assert display_names.types.calendar == %{
             buddhist: "Buddhist Calendar",
             gregorian: "Gregorian Calendar"
           }

    assert display_names.core_types.calendar == %{buddhist: "Buddhist", gregorian: "Gregorian"}
  end

  test "a key without core names has none" do
    display_names = LocaleDisplayNames.normalize(content(), "en")["locale_display_names"]

    assert display_names.types.numbers == %{arab: "Arabic-Indic Digits"}
    refute Map.has_key?(display_names.core_types, :numbers)
  end

  test "renames uksystem to imperial in both" do
    display_names = LocaleDisplayNames.normalize(content(), "en")["locale_display_names"]

    assert display_names.types.ms.imperial == "Imperial Measurement System"
    assert display_names.core_types.ms == %{metric: "Metric", imperial: "UK"}
  end
end
