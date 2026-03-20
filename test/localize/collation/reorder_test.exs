defmodule Localize.Collation.ReorderTest do
  use ExUnit.Case

  setup_all do
    Localize.Collation.ensure_loaded()
    :ok
  end

  describe "Reorder.build_mapping/1" do
    test "returns nil for empty list" do
      assert Localize.Collation.Reorder.build_mapping([]) == nil
    end

    test "returns a function for valid script codes" do
      mapping = Localize.Collation.Reorder.build_mapping([:Grek])
      assert is_function(mapping, 1)
    end

    test "returns a function for multiple script codes" do
      mapping = Localize.Collation.Reorder.build_mapping([:Grek, :Cyrl])
      assert is_function(mapping, 1)
    end

    test "mapping preserves zero primary weight" do
      mapping = Localize.Collation.Reorder.build_mapping([:Grek])
      assert mapping.(0) == 0
    end
  end

  describe "Reorder.load_script_ranges/0" do
    test "returns a map with script ranges" do
      ranges = Localize.Collation.Reorder.load_script_ranges()
      assert is_map(ranges)
      assert Map.has_key?(ranges, "latn")
      assert Map.has_key?(ranges, "grek")
      assert Map.has_key?(ranges, "cyrl")
    end

    test "script ranges are {start, end} tuples" do
      ranges = Localize.Collation.Reorder.load_script_ranges()
      {start, finish} = Map.get(ranges, "latn")
      assert is_integer(start)
      assert is_integer(finish)
      assert start <= finish
    end

    test "does not include non-reorderable groups" do
      ranges = Localize.Collation.Reorder.load_script_ranges()
      refute Map.has_key?(ranges, "terminator")
      refute Map.has_key?(ranges, "compress")
      refute Map.has_key?(ranges, "implicit")
      refute Map.has_key?(ranges, "trailing")
      refute Map.has_key?(ranges, "special")
    end
  end

  describe "Reorder.load_primary_to_fractional_lead/0" do
    test "returns a map with primary weight mappings" do
      mapping = Localize.Collation.Reorder.load_primary_to_fractional_lead()
      assert is_map(mapping)
      assert map_size(mapping) > 0
    end

    test "maps Latin 'a' primary to a fractional lead byte" do
      mapping = Localize.Collation.Reorder.load_primary_to_fractional_lead()
      # Latin 'a' has primary 0x23EC in allkeys
      frac_lead = Map.get(mapping, 0x23EC)
      assert is_integer(frac_lead)
      # Should be in the Latin range (0x2A..0x5E)
      assert frac_lead >= 0x2A and frac_lead <= 0x5E
    end
  end

  describe "compare/3 with reorder" do
    test "Greek before Latin with reorder: [:Grek]" do
      assert Localize.Collation.compare("α", "a", reorder: [:Grek], backend: :elixir) == :lt
    end

    test "Cyrillic before Latin with reorder: [:Cyrl]" do
      assert Localize.Collation.compare("б", "a", reorder: [:Cyrl], backend: :elixir) == :lt
    end

    test "Greek before Cyrillic with reorder: [:Grek]" do
      assert Localize.Collation.compare("α", "б", reorder: [:Grek], backend: :elixir) == :lt
    end

    test "without reorder, Latin before Greek" do
      assert Localize.Collation.compare("a", "α", backend: :elixir) == :lt
    end

    test "without reorder, Latin before Cyrillic" do
      assert Localize.Collation.compare("a", "б", backend: :elixir) == :lt
    end

    test "empty reorder is a no-op" do
      assert Localize.Collation.compare("a", "α", reorder: [], backend: :elixir) == :lt
    end
  end

  describe "sort/2 with reorder" do
    test "reorder: [:Grek] promotes Greek before Latin" do
      words = ["alpha", "αλφα", "бета", "100"]
      result = Localize.Collation.sort(words, reorder: [:Grek], backend: :elixir)
      assert result == ["100", "αλφα", "alpha", "бета"]
    end

    test "reorder: [:Cyrl] promotes Cyrillic before Latin and Greek" do
      words = ["alpha", "αλφα", "бета", "100"]
      result = Localize.Collation.sort(words, reorder: [:Cyrl], backend: :elixir)
      assert result == ["100", "бета", "alpha", "αλφα"]
    end

    test "reorder: [:Grek, :Cyrl] promotes Greek first, then Cyrillic" do
      words = ["alpha", "αλφα", "бета", "100"]
      result = Localize.Collation.sort(words, reorder: [:Grek, :Cyrl], backend: :elixir)
      assert result == ["100", "αλφα", "бета", "alpha"]
    end

    test "reorder: [:Cyrl, :Grek] promotes Cyrillic first, then Greek" do
      words = ["alpha", "αλφα", "бета", "100"]
      result = Localize.Collation.sort(words, reorder: [:Cyrl, :Grek], backend: :elixir)
      assert result == ["100", "бета", "αλφα", "alpha"]
    end

    test "no reorder preserves default script order" do
      words = ["alpha", "αλφα", "бета", "100"]
      result = Localize.Collation.sort(words, backend: :elixir)
      assert result == ["100", "alpha", "αλφα", "бета"]
    end

    test "digits always sort before scripts regardless of reorder" do
      words = ["100", "alpha", "αλφα"]
      result = Localize.Collation.sort(words, reorder: [:Grek], backend: :elixir)
      assert hd(result) == "100"
    end
  end

  describe "Elixir/NIF parity with reorder" do
    @tag :nif
    test "reorder: [:Grek] matches NIF" do
      if Localize.Collation.Nif.available?() do
        words = ["alpha", "αλφα", "бета", "100"]
        elixir = Localize.Collation.sort(words, reorder: [:Grek], backend: :elixir)
        nif = Localize.Collation.sort(words, reorder: [:Grek], backend: :nif)
        assert elixir == nif
      end
    end

    @tag :nif
    test "reorder: [:Cyrl] matches NIF" do
      if Localize.Collation.Nif.available?() do
        words = ["alpha", "αλφα", "бета", "100"]
        elixir = Localize.Collation.sort(words, reorder: [:Cyrl], backend: :elixir)
        nif = Localize.Collation.sort(words, reorder: [:Cyrl], backend: :nif)
        assert elixir == nif
      end
    end

    @tag :nif
    test "reorder: [:Grek, :Cyrl] matches NIF" do
      if Localize.Collation.Nif.available?() do
        words = ["alpha", "αλφα", "бета", "100"]
        elixir = Localize.Collation.sort(words, reorder: [:Grek, :Cyrl], backend: :elixir)
        nif = Localize.Collation.sort(words, reorder: [:Grek, :Cyrl], backend: :nif)
        assert elixir == nif
      end
    end

    @tag :nif
    test "reorder: [:Cyrl, :Grek] matches NIF" do
      if Localize.Collation.Nif.available?() do
        words = ["alpha", "αλφα", "бета", "100"]
        elixir = Localize.Collation.sort(words, reorder: [:Cyrl, :Grek], backend: :elixir)
        nif = Localize.Collation.sort(words, reorder: [:Cyrl, :Grek], backend: :nif)
        assert elixir == nif
      end
    end

    @tag :nif
    test "compare with reorder: [:Grek] matches NIF" do
      if Localize.Collation.Nif.available?() do
        for {a, b} <- [{"α", "a"}, {"б", "a"}, {"α", "б"}] do
          elixir = Localize.Collation.compare(a, b, reorder: [:Grek], backend: :elixir)
          nif = Localize.Collation.compare(a, b, reorder: [:Grek], backend: :nif)
          assert elixir == nif, "#{a} vs #{b}: elixir=#{elixir}, nif=#{nif}"
        end
      end
    end
  end

  describe "reorder combined with other options" do
    test "reorder with strength: :secondary" do
      result =
        Localize.Collation.sort(
          ["Alpha", "αλφα", "alpha"],
          reorder: [:Grek],
          strength: :secondary,
          backend: :elixir
        )

      assert hd(result) == "αλφα"
    end

    test "reorder with alternate: :shifted" do
      result =
        Localize.Collation.sort(
          ["al-pha", "αλφα"],
          reorder: [:Grek],
          alternate: :shifted,
          backend: :elixir
        )

      assert result == ["αλφα", "al-pha"]
    end
  end
end
