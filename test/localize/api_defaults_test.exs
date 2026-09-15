defmodule Localize.ApiDefaultsTest do
  @moduledoc """
  The public formatting and parsing functions called without options, and
  their bang variants on invalid input.

  Called without options each function uses the process locale, `:en` in the
  test suite, so the expected strings are CLDR's `en` formats: the medium time
  "h:mm:ss a" (with a narrow no-break space before the day period), the medium
  date "MMM d, y", and the number range pattern "{0}–{1}". A bang variant
  raises the exception its non-bang variant returns.

  """

  use ExUnit.Case, async: true

  defp joined({:ok, parts}), do: {:ok, Enum.map_join(parts, & &1.value)}
  defp joined(other), do: other

  # CLDR's `en` interval formats put thin spaces around the en dash.
  describe "without options" do
    test "time and date parts use the process locale's medium formats" do
      assert joined(Localize.Time.to_parts(~T[14:30:00])) == {:ok, "2:30:00 PM"}
      assert joined(Localize.Date.to_parts(~D[2024-07-06])) == {:ok, "Jul 6, 2024"}

      assert Enum.map_join(Localize.Time.to_parts!(~T[14:30:00]), & &1.value) ==
               "2:30:00 PM"

      assert Enum.map_join(Localize.Date.to_parts!(~D[2024-07-06]), & &1.value) == "Jul 6, 2024"
    end

    test "parsing reads the process locale's formats" do
      assert Localize.Date.parse("Jul 6, 2024") == {:ok, ~D[2024-07-06]}
      assert Localize.Time.parse("2:30:00 PM") == {:ok, ~T[14:30:00]}
      assert Localize.DateTime.parse("Jul 6, 2024, 2:30:00 PM") == {:ok, ~N[2024-07-06 14:30:00]}
    end

    test "interval, number and relative time parts" do
      assert Localize.Interval.to_parts!(~D[2022-04-22], ~D[2022-04-25])
             |> Enum.map_join(& &1.value) == "Apr 22 – 25, 2022"

      assert Localize.Number.to_parts!(1234) == [
               %{type: :integer, value: "1"},
               %{type: :group, value: ","},
               %{type: :integer, value: "234"}
             ]

      assert joined(Localize.Number.to_range_parts(1, 5)) == {:ok, "1–5"}
      assert Enum.map_join(Localize.Number.to_range_parts!(1, 5), & &1.value) == "1–5"

      assert Localize.DateTime.Relative.to_string(-60) == {:ok, "1 minute ago"}
      assert joined(Localize.DateTime.Relative.to_parts(-60)) == {:ok, "1 minute ago"}
    end
  end

  describe "bang variants on invalid input" do
    test "raise the error the non-bang variant returns" do
      cases = [
        {fn -> Localize.Time.to_string(:bogus) end, fn -> Localize.Time.to_string!(:bogus) end},
        {fn -> Localize.Time.to_parts(:bogus) end, fn -> Localize.Time.to_parts!(:bogus) end},
        {fn -> Localize.Date.to_parts(:bogus) end, fn -> Localize.Date.to_parts!(:bogus) end},
        {fn -> Localize.Interval.to_parts(~D[2024-01-01], nil) end,
         fn -> Localize.Interval.to_parts!(~D[2024-01-01], nil) end},
        {fn -> Localize.Number.to_range_parts(:a, :b) end,
         fn -> Localize.Number.to_range_parts!(:a, :b) end}
      ]

      for {plain, bang} <- cases do
        assert {:error, %{__exception__: true, __struct__: module}} = plain.()
        assert_raise module, bang
      end
    end
  end
end
