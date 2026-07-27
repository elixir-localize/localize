defmodule Localize.Inflection.LexiconTest do
  # An encoding bug here returns a wrong inflection rather than
  # crashing, so the checks are exhaustive where they can afford to be.
  # Synthetic cases pack a known map and assert every key reads back.
  # Shipped artifacts arrive already packed, with no map to compare
  # against, so they are checked by playing the two independent read
  # paths against each other — sequential front-coded decode versus
  # block-index binary search — plus a re-pack round trip.
  use ExUnit.Case, async: true

  import Bitwise

  alias Localize.Inflection.{DataDir, Lexicon}

  # Small enough to verify every key quickly; between them they cover
  # Latin, Turkish dotted/dotless i, and a Slavic locale.
  @exhaustive_locales [:tr, :fi, :pl]

  # Large and structurally diverse (deep dedup in de/ru, almost none
  # in ar), sampled to keep the suite fast.
  @sampled_locales [:de, :ru, :ar]
  @sample_size 2_000

  # Generated artifacts ship the lexicon already packed. The map and
  # list shapes are earlier artifact revisions that `Data` still
  # accepts, so handle them here too rather than assuming the current
  # format.
  defp packed_lexicon(locale) do
    raw = DataDir.path("#{locale}.etf") |> File.read!() |> :erlang.binary_to_term()

    case raw.lexicon do
      %Lexicon{} = lexicon ->
        lexicon

      lexicon when is_map(lexicon) ->
        Lexicon.pack(lexicon)

      lexicon when is_list(lexicon) ->
        Lexicon.pack(Map.new(lexicon, fn {w, m, p} -> {w, {m, p}} end))
    end
  end

  defp assert_equivalent(map, packed, keys) do
    mismatches =
      Enum.reduce(keys, [], fn key, acc ->
        expected = Map.get(map, key)
        actual = Lexicon.lookup(packed, key)
        if actual == expected, do: acc, else: [{key, expected, actual} | acc]
      end)

    assert mismatches == [], "packed lookup diverged: #{inspect(Enum.take(mismatches, 5))}"
  end

  describe "pack/1 and lookup/2" do
    test "an empty lexicon returns nil for any word" do
      packed = Lexicon.pack(%{})
      assert Lexicon.size(packed) == 0
      assert Lexicon.lookup(packed, "anything") == nil
      assert Lexicon.lookup(packed, "") == nil
    end

    test "a single entry round-trips and misses cleanly" do
      packed = Lexicon.pack(%{"cat" => {1, [0]}})
      assert Lexicon.lookup(packed, "cat") == {1, [0]}

      for miss <- ["ca", "cats", "", "dog", "car"] do
        assert Lexicon.lookup(packed, miss) == nil, "expected miss for #{inspect(miss)}"
      end
    end

    test "keys that are prefixes of one another stay distinct" do
      map = %{"ca" => {3, []}, "cat" => {1, [0]}, "cats" => {2, [1]}, "cattle" => {4, [2, 3]}}
      packed = Lexicon.pack(map)

      assert_equivalent(map, packed, Map.keys(map))
      assert Lexicon.lookup(packed, "c") == nil
      assert Lexicon.lookup(packed, "catt") == nil
    end

    test "empty and multi-element pattern index lists round-trip in order" do
      map = %{"none" => {7, []}, "many" => {8, [4, 0, 9, 2, 2]}}
      packed = Lexicon.pack(map)

      assert Lexicon.lookup(packed, "none") == {7, []}
      assert Lexicon.lookup(packed, "many") == {8, [4, 0, 9, 2, 2]}
    end

    test "a mask wider than a machine word round-trips" do
      wide = (1 <<< 55) - 1
      packed = Lexicon.pack(%{"w" => {wide, [1000]}})

      assert Lexicon.lookup(packed, "w") == {wide, [1000]}
    end

    test "non-ASCII keys round-trip" do
      map = %{"дом" => {5, [2]}, "домом" => {6, [3]}, "كتاب" => {7, [4]}, "日本語" => {8, [5]}}
      packed = Lexicon.pack(map)

      assert_equivalent(map, packed, Map.keys(map))
      assert Lexicon.lookup(packed, "до") == nil
    end

    test "entries spanning many blocks are all reachable" do
      # Well past the 32-key block size, so block boundaries, the block
      # index, and the binary search all get exercised.
      map =
        for index <- 1..500,
            into: %{},
            do: {"word#{String.pad_leading(to_string(index), 4, "0")}", {index, [index]}}

      packed = Lexicon.pack(map)

      assert Lexicon.size(packed) == 500
      assert_equivalent(map, packed, Map.keys(map))
      assert Lexicon.lookup(packed, "word0000") == nil
      assert Lexicon.lookup(packed, "word9999") == nil
    end

    test "duplicate values are interned without changing lookups" do
      # Every entry shares one value, so the value table holds one
      # record while all 100 keys still resolve to it.
      map = for index <- 1..100, into: %{}, do: {"k#{index}", {42, [7]}}
      packed = Lexicon.pack(map)

      assert packed.value_count == 1
      assert_equivalent(map, packed, Map.keys(map))
    end
  end

  describe "shipped artifacts" do
    # `to_list/1` decodes the front-coded keys sequentially while
    # `lookup/2` reaches them through the block index and a binary
    # search. Playing the two paths against each other catches an
    # encoding or search bug that a single path would return
    # consistently — and silently — wrong.
    for locale <- @exhaustive_locales do
      test "#{locale}: every entry agrees between sequential decode and lookup" do
        packed = packed_lexicon(unquote(locale))
        entries = Lexicon.to_list(packed)
        map = Map.new(entries)

        assert length(entries) == Lexicon.size(packed)
        assert map_size(map) == Lexicon.size(packed), "duplicate keys decoded"
        assert entries == Enum.sort_by(entries, &elem(&1, 0)), "keys are not in sorted order"

        assert_equivalent(map, packed, Map.keys(map))
        assert Lexicon.lookup(packed, "zzz_not_a_word_zzz") == nil
      end
    end

    for locale <- @sampled_locales do
      test "#{locale}: a sample of entries agrees between sequential decode and lookup" do
        packed = packed_lexicon(unquote(locale))
        entries = Lexicon.to_list(packed)
        map = Map.new(entries)

        assert length(entries) == Lexicon.size(packed)
        assert map_size(map) == Lexicon.size(packed), "duplicate keys decoded"

        keys = map |> Map.keys() |> Enum.take_random(@sample_size)
        assert_equivalent(map, packed, keys)
        assert Lexicon.lookup(packed, "zzz_not_a_word_zzz") == nil
      end
    end

    test "re-packing a decoded artifact reproduces it byte for byte" do
      # Guards the generator contract: what ships must be exactly what
      # `pack/1` produces for the same content, so CI's manifest check
      # cannot drift from the runtime's expectations.
      packed = packed_lexicon(:pl)
      repacked = packed |> Lexicon.to_list() |> Map.new() |> Lexicon.pack()

      assert repacked == packed
    end

    test "packing an already-packed lexicon is a no-op" do
      packed = packed_lexicon(:tr)

      assert Lexicon.pack(packed) == packed
    end
  end
end
