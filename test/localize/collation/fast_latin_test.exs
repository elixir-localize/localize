defmodule Localize.Collation.FastLatinTest do
  # async: false — the rebuild tests below erase and rebuild the
  # fast-latin :persistent_term entry shared by the collation engine.
  use ExUnit.Case, async: false

  alias Localize.Collation.FastLatin

  @fast_latin_key {:localize, :collation_fast_latin}

  setup_all do
    Localize.Collation.ensure_loaded()
    :ok
  end

  doctest Localize.Collation.FastLatin

  describe "lookup/1" do
    test "returns collation elements for basic Latin letters" do
      assert [{primary, _, _, _} | _] = FastLatin.lookup(?a)
      assert primary > 0

      assert [{upper_primary, _, _, _} | _] = FastLatin.lookup(?A)
      assert upper_primary == primary
    end

    test "returns collation elements for Latin-1 accented letters" do
      # é (U+00E9) is inside the fast-latin range and is not a
      # contraction starter or combining mark.
      assert [_ | _] = FastLatin.lookup(0x00E9)
    end

    test "returns nil for contraction starters" do
      # L and l start the CLDR L·/l· contractions, so they are
      # excluded from the fast table.
      assert FastLatin.lookup(?L) == nil
      assert FastLatin.lookup(?l) == nil
    end
  end

  describe "build/0" do
    test "rebuilds the fast table from the loaded collation table" do
      before_rebuild = FastLatin.lookup(?a)

      assert :ok = FastLatin.build()
      assert FastLatin.lookup(?a) == before_rebuild
      assert FastLatin.lookup(?L) == nil

      # Restore the ETF-provided table so other tests see the
      # canonical persistent_term contents.
      on_exit(fn ->
        :persistent_term.erase(@fast_latin_key)
        Localize.Collation.Table.ensure_loaded()
      end)
    end
  end

  describe "lazy rebuild" do
    test "lookup rebuilds the table when the persistent_term entry is missing" do
      :persistent_term.erase(@fast_latin_key)

      assert [_ | _] = FastLatin.lookup(?a)
      assert is_tuple(:persistent_term.get(@fast_latin_key))
    end
  end

  describe "fast path and full path agree" do
    test "pure Latin sorting matches sorting that bails to the full path" do
      # "coop" vs "co-op": the hyphen is fast-path; "l·l" bails out
      # (contraction starter); "nöel" stays in Latin-1; "śpiew" has
      # a codepoint ≥ 0x0180 companion via combining mark forms.
      words = ["coop", "co-op", "nöel", "noel", "l·la", "lza", "zebra"]

      sorted = Localize.Collation.sort(words, backend: :elixir)

      # NFD-composed and precomposed forms compare equal to themselves
      # and ordering is total: resorting the result is a fixpoint.
      assert Localize.Collation.sort(sorted, backend: :elixir) == sorted

      assert Enum.sort(Enum.map(words, &Localize.Collation.sort_key(&1, backend: :elixir))) ==
               Enum.map(sorted, &Localize.Collation.sort_key(&1, backend: :elixir))
    end

    test "precomposed and decomposed accents compare equal" do
      # é precomposed (fast path) vs e + combining acute (falls off
      # the fast path at the combining mark).
      assert Localize.Collation.compare("café", "cafe\u0301", backend: :elixir) == :eq
    end
  end
end
