defmodule Localize.Data.Normalize.UnitsTest do
  @moduledoc """
  Covers unit data normalization, in particular order-independent
  merging of compound unit grammatical-case patterns.

  """

  use ExUnit.Case, async: true

  alias Localize.Data.Normalize.Units

  # Entries shaped like compound_unit/2 output for the Russian power2
  # source keys (gender → count → case), where the shallow-merge bug
  # dropped case entries depending on arrival order.
  @compound_entries [
    {:nominative, "кв. {0}"},
    {"one", "квадратный {0}"},
    {"one", {"accusative", "квадратный {0}"}},
    {"one", {"dative", "квадратному {0}"}},
    {"feminine", {"one", "квадратная {0}"}},
    {"feminine", {"one", {"accusative", "квадратную {0}"}}},
    {"feminine", {"one", {"dative", "квадратной {0}"}}},
    {"feminine", {"other", {"locative", "квадратной {0}"}}}
  ]

  describe "map_nested_compounds/2" do
    test "keeps every case entry in gender-nested compounds" do
      result = Units.map_nested_compounds(@compound_entries)

      assert %{
               "accusative" => ["квадратную ", 0],
               "dative" => ["квадратной ", 0],
               nominative: ["квадратная ", 0]
             } = get_in(result, ["feminine", "one"])

      assert get_in(result, ["feminine", "other", "locative"]) == ["квадратной ", 0]
      assert get_in(result, ["one", "accusative"]) == ["квадратный ", 0]
      assert get_in(result, ["one", "dative"]) == ["квадратному ", 0]
      assert result[:nominative] == ["кв. ", 0]
    end

    test "does not depend on the order entries arrive in" do
      # Regression: the previous shallow merge kept only the last case
      # entry per gender and count, so results differed with map
      # iteration order (and therefore across OTP releases).
      reference = Units.map_nested_compounds(@compound_entries)

      rotations =
        for rotation <- 1..(length(@compound_entries) - 1) do
          {head, tail} = Enum.split(@compound_entries, rotation)
          tail ++ head
        end

      for entries <- [Enum.reverse(@compound_entries) | rotations] do
        assert Units.map_nested_compounds(entries) == reference
      end
    end
  end

  describe "normalize/2" do
    test "russian power2 compounds keep the full case coverage of the source" do
      %{"units" => units} = Units.normalize(%{}, "ru")
      power2 = get_in(units, [:long, :compound, :power2, :compound_unit_pattern])

      for gender <- [:feminine, :masculine], count <- [:one, :few, :many] do
        cases = power2[gender][count]

        assert is_map(cases), "expected a case map at #{gender}/#{count}"

        for grammatical_case <- [:accusative, :dative, :genitive, :instrumental] do
          assert Map.has_key?(cases, grammatical_case),
                 "missing #{grammatical_case} at #{gender}/#{count}"
        end
      end
    end
  end
end
