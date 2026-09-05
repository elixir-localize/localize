defmodule Localize.JapaneseErasTest do
  @moduledoc """
  Guards the Japanese era set against silent loss.

  CLDR 49 dropped era data for everything before Meiji — 232 of the 237
  entries. Localize keeps the full range: the use cases that need it
  (academic publishing, genealogy, museum cataloguing, calendar
  conversion) are exactly the ones CLDR is stepping back from.

  `priv/localize/supplemental_data/calendars.etf` has no generator — it is
  curated data, committed by hand — so nothing in the pipeline would fail
  if the pre-Meiji entries went missing. These assertions are the guard.
  See `plans/japanese_eras.md`.
  """

  use ExUnit.Case, async: true

  @snapshot Path.join([
              __DIR__,
              "..",
              "..",
              "priv",
              "localize",
              "supplemental_data",
              "japanese_eras_snapshot_cldr48.etf"
            ])

  defp eras do
    Localize.SupplementalData.calendars()
    |> get_in([:japanese, :eras])
  end

  describe "era set completeness" do
    test "all 237 eras are present" do
      assert length(eras()) == 237
    end

    # The boundaries are what a truncation to CLDR 49's set would move:
    # index 0 disappears entirely and index 232 becomes the first entry.
    test "the set spans 大化 (645) through 令和 (2019)" do
      indexed = Map.new(eras(), fn [index, era] -> {index, era} end)

      assert %{start: [645, 6, 19]} = Map.get(indexed, 0)
      assert %{code: :meiji, start: [1868, 10, 23]} = Map.get(indexed, 232)
      assert %{code: :reiwa, start: [2019, 5, 1]} = Map.get(indexed, 236)
    end

    # CLDR 49 keeps only 232-236. If the era set ever equals just those,
    # the pre-Meiji range has been taken from upstream wholesale.
    test "the pre-Meiji range has not been truncated to CLDR 49's set" do
      indices = Enum.map(eras(), fn [index, _era] -> index end)

      assert Enum.min(indices) == 0
      assert length(Enum.filter(indices, &(&1 < 232))) == 232
    end

    test "era indices are contiguous and each carries a start date" do
      indices = eras() |> Enum.map(fn [index, _era] -> index end) |> Enum.sort()

      assert indices == Enum.to_list(0..236)

      assert Enum.all?(eras(), fn [_index, era] ->
               match?([y, m, d] when is_integer(y) and is_integer(m) and is_integer(d), era.start)
             end)
    end
  end

  describe "the frozen CLDR 48 snapshot" do
    # The snapshot is the last upstream-sourced copy, kept for diffing as
    # the per-era validation pass lands corrections in the active data.
    test "matches the active era set" do
      snapshot = @snapshot |> File.read!() |> :erlang.binary_to_term()

      assert snapshot.era_count == 237
      assert snapshot.source == "CLDR 48.2"
      assert snapshot.eras == eras()
    end
  end
end
