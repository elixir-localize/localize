defmodule Localize.Unit.PreferenceTest do
  use ExUnit.Case, async: true

  alias Localize.Test.PreferenceData

  describe "usage option hardening" do
    test "an unknown usage string falls back to default preferences" do
      unit = Localize.Unit.new!(100, "meter")

      assert Localize.Unit.Preference.preferred_units(unit, usage: "no-such-usage-exists") ==
               Localize.Unit.Preference.preferred_units(unit, usage: :default)
    end

    test "an unknown usage string does not create a new atom" do
      unit = Localize.Unit.new!(100, "meter")
      unique = "usage_atom_probe_#{System.unique_integer([:positive])}"

      {:ok, _units, _options} =
        Localize.Unit.Preference.preferred_units(unit, usage: unique)

      assert_raise ArgumentError, fn ->
        String.to_existing_atom(unique)
      end
    end
  end

  for t <- PreferenceData.preferences() do
    test_name =
      "##{t.line}: preference for #{inspect(t.input_unit)} with usage #{inspect(t.usage)} " <>
        "in region #{inspect(t.region)} for #{inspect(t.input_double)} " <>
        "is #{inspect(t.output_units)}"

    test test_name do
      assert {:ok, unquote(t.output_units), _skeleton} =
               Localize.Unit.Preference.preferred_units(
                 Localize.Unit.new!(unquote(t.input_double), unquote(t.input_unit)),
                 usage: unquote(t.usage),
                 territory: unquote(t.region)
               )
    end
  end
end
