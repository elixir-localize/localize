defmodule Localize.Unit.PreferenceTest do
  use ExUnit.Case, async: true

  alias Localize.Test.PreferenceData

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
