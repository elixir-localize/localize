defmodule Localize.JapaneseErasTest do
  @moduledoc """
  Guards the curated Japanese era set.

  CLDR 49 dropped era data for everything before Meiji — 232 of the 237
  entries — and what it did ship for the pre-Meiji range recorded the
  *lunisolar* proclamation date in a field the rest of the file reads as
  proleptic Gregorian. Localize publishes the full range, converted, from
  `priv/localize/curated/japanese_eras.json`.

  Nothing downstream asserts on historical era dates, so a regression here
  would otherwise be silent. See `plans/japanese_eras.md`.
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

  @curated Path.join([__DIR__, "..", "..", "priv", "localize", "curated", "japanese_eras.json"])

  @research Path.join([__DIR__, "..", "..", "plans", "japanese_eras_research.json"])

  defp eras do
    Localize.SupplementalData.calendars()
    |> get_in([:japanese, :eras])
  end

  defp indexed, do: Map.new(eras(), fn [index, era] -> {index, era} end)

  defp curated do
    @curated |> File.read!() |> :json.decode() |> Map.fetch!("eras")
  end

  describe "era set completeness" do
    test "all 237 eras are present" do
      assert length(eras()) == 237
    end

    test "era indices are contiguous from 大化 to 令和" do
      indices = eras() |> Enum.map(fn [index, _era] -> index end) |> Enum.sort()

      assert indices == Enum.to_list(0..236)
    end

    # CLDR 49 keeps only 232-236. If the set ever equals just those, the
    # pre-Meiji range has been taken from upstream wholesale.
    test "the pre-Meiji range has not been truncated to CLDR 49's set" do
      indices = Enum.map(eras(), fn [index, _era] -> index end)

      assert Enum.min(indices) == 0
      assert length(Enum.filter(indices, &(&1 < 232))) == 232
    end

    test "every era carries a start date" do
      assert Enum.all?(eras(), fn [_index, era] ->
               match?([y, m, d] when is_integer(y) and is_integer(m) and is_integer(d), era.start)
             end)
    end
  end

  describe "proleptic Gregorian conversion" do
    # 大化 was proclaimed 皇極天皇4年6月19日. CLDR recorded `[645, 6, 19]` —
    # the lunisolar date — where the proleptic Gregorian equivalent is
    # 645-07-20.
    test "pre-Meiji dates are the researched conversions, not CLDR's lunisolar values" do
      assert %{start: [645, 7, 20]} = Map.get(indexed(), 0)
      assert %{start: [650, 3, 25]} = Map.get(indexed(), 1)
    end

    # The modern eras were already proleptic Gregorian upstream, so the
    # curated set and CLDR 49 agree on them exactly.
    test "modern eras match what CLDR 49 ships" do
      assert %{code: :meiji, start: [1868, 10, 23]} = Map.get(indexed(), 232)
      assert %{code: :taisho, start: [1912, 7, 30]} = Map.get(indexed(), 233)
      assert %{code: :showa, start: [1926, 12, 25]} = Map.get(indexed(), 234)
      assert %{code: :heisei, start: [1989, 1, 8]} = Map.get(indexed(), 235)
      assert %{code: :reiwa, start: [2019, 5, 1]} = Map.get(indexed(), 236)
    end

    # Every pre-Meiji entry moved: CLDR's values were lunisolar throughout.
    test "every pre-Meiji entry differs from the frozen CLDR 48 value" do
      snapshot = @snapshot |> File.read!() |> :erlang.binary_to_term()
      frozen = Map.new(snapshot.eras, fn [index, era] -> {index, era.start} end)
      active = indexed()

      unchanged =
        Enum.filter(0..231, fn index -> Map.get(frozen, index) == Map.get(active, index).start end)

      assert unchanged == []
    end
  end

  describe "provenance flags" do
    # 白鳳 is a 私年号 — a folk era, never proclaimed by the imperial court.
    test "the private era is flagged" do
      assert %{private_era: true} = Map.get(indexed(), 2)

      private = Enum.filter(eras(), fn [_index, era] -> Map.get(era, :private_era) end)
      assert length(private) == 1
    end

    # Four entries lack primary-source attestation. They stay published —
    # dropping them would break the index space — but carry a flag.
    test "unattested entries are flagged rather than dropped" do
      unverified =
        eras()
        |> Enum.filter(fn [_index, era] -> Map.get(era, :unverified) end)
        |> Enum.map(fn [index, _era] -> index end)

      assert unverified == [2, 25, 167, 187]
    end
  end

  describe "the frozen CLDR 48 snapshot" do
    # The snapshot is the last upstream-sourced copy, kept for diffing. It
    # is deliberately *not* equal to the active set any more — that
    # difference is the correction.
    test "still holds the untouched CLDR 48 set" do
      snapshot = @snapshot |> File.read!() |> :erlang.binary_to_term()

      assert snapshot.era_count == 237
      assert snapshot.source == "CLDR 48.2"
      assert [[0, %{start: [645, 6, 19]}] | _rest] = snapshot.eras
    end
  end

  describe "the curated source" do
    test "carries one entry per CLDR era index" do
      assert length(curated()) == 237

      indices = curated() |> Enum.map(&Map.fetch!(&1, "idx")) |> Enum.sort()
      assert indices == Enum.to_list(0..236)
    end

    # The research dataset is the citation record; the curated file is the
    # build input distilled from it. This fails if they drift apart.
    test "agrees with the research dataset it is distilled from" do
      research =
        @research
        |> File.read!()
        |> :json.decode()
        |> Map.fetch!("eras")
        |> Map.new(&{Map.fetch!(&1, "idx"), &1})

      drifted =
        Enum.filter(curated(), fn entry ->
          researched = Map.fetch!(research, Map.fetch!(entry, "idx"))
          best = Map.get(researched, "best_pg")

          # Index 167 has no researched date; its start is derived from the
          # entry it duplicates and is documented in the curated file.
          # `:json.decode/1` renders a JSON null as the atom `:null`.
          best not in [nil, :null] and best != Map.fetch!(entry, "start")
        end)

      assert drifted == []
      assert Enum.find(curated(), &(Map.fetch!(&1, "idx") == 167))["note"] =~ "no era name"
    end
  end
end
