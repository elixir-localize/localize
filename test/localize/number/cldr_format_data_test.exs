defmodule Localize.Number.CldrFormatDataTest do
  @moduledoc """
  Tests adapted from ex_cldr_numbers test data.
  Dynamically generates tests from the test data tuples.
  """

  use ExUnit.Case, async: true

  Code.require_file("../../support/number_format_test_data.exs", __DIR__)

  Enum.each(Localize.Test.Number.FormatData.test_data(), fn {value, result, args} ->
    test "formatted #{inspect(value)} == #{inspect(result)} with args: #{inspect(args)}" do
      assert {:ok, unquote(result)} =
               Localize.Number.to_string(unquote(value), unquote(Macro.escape(args)))
    end
  end)
end
