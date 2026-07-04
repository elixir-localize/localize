defmodule Localize.Collation.ReorderTest do
  use ExUnit.Case

  doctest Localize.Collation.Reorder

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

    test "lowercase script codes are equivalent to titlecase codes" do
      assert Localize.Collation.compare("α", "a", reorder: [:grek], backend: :elixir) == :lt
    end

    test "the punct alias normalizes to punctuation" do
      mapping = Localize.Collation.Reorder.build_mapping([:punct])
      assert is_function(mapping, 1)
    end

    test "unknown script codes leave the default order unchanged" do
      assert Localize.Collation.compare("a", "α", reorder: [:Xxquestionable], backend: :elixir) ==
               :lt

      assert Localize.Collation.compare("a", "б", reorder: [:Xxquestionable], backend: :elixir) ==
               :lt
    end

    test "builds a mapping when :others or :Zzzz is present" do
      assert is_function(Localize.Collation.Reorder.build_mapping([:Grek, :others]), 1)
      assert is_function(Localize.Collation.Reorder.build_mapping([:Grek, :Zzzz]), 1)
    end
  end

  describe "Reorder.apply_mapping/2" do
    test "nil mapping returns the primary unchanged" do
      assert Localize.Collation.Reorder.apply_mapping(nil, 0x23EC) == 0x23EC
    end

    test "a mapping function is applied to the primary" do
      double = fn primary -> primary * 2 end
      assert Localize.Collation.Reorder.apply_mapping(double, 21) == 42
    end
  end

  describe "Reorder.parse_primary_to_frac/1" do
    @tag :tmp_dir
    test "extracts fractional lead and sub bytes from data lines", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "frac_fixture.txt")

      File.write!(path, """
      # comment line
      [top_byte\t03\tSPACE ]
      FDD0 0041; marker line, skipped
      0020; [03 05, 05, 05]\t# Zyyy Zs\t[0209.0020.0002]\t* SPACE
      0041; [2B, 05, 9C]\t# Latn Lu\t[23EC.0020.0008]\t* LATIN CAPITAL LETTER A
      00E9; [33 45, 05, 05]\t# Latn Ll\t[2453.0020.0002]\t* TWO-BYTE LEAD
      0345; [, 97, 05]\t# combining, no fractional primary\t[0000.005C.0002]
      FFF0; [05 05, 05, 05]\t# zero allkeys primary is skipped\t[0000.0020.0002]
      not a data line
      """)

      mapping = Localize.Collation.Reorder.parse_primary_to_frac(path)

      assert mapping[0x23EC] == 0x2B
      assert mapping[{:sub, 0x23EC}] == 0
      assert mapping[0x2453] == 0x33
      assert mapping[{:sub, 0x2453}] == 0x45
      assert mapping[0x0209] == 0x03

      # Entries without a fractional primary or with a zero allkeys
      # primary are not recorded.
      refute Map.has_key?(mapping, 0x0000)
      refute Map.has_key?(mapping, {:sub, 0x0000})
    end
  end

  describe "Reorder.parse_top_bytes/1" do
    @tag :tmp_dir
    test "builds script ranges and filters non-reorderable groups", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "top_bytes_fixture.txt")

      File.write!(path, """
      [top_byte\t00\tTERMINATOR ]
      [top_byte\t01\tLEVEL-SEPARATOR ]
      [top_byte\t03\tSPACE PUNCTUATION ]
      [top_byte\t04\tSPACE PUNCTUATION ]
      [top_byte\t0F\tDIGIT ]
      0041; [2B, 05, 9C]\t# not a top_byte line
      """)

      ranges = Localize.Collation.Reorder.parse_top_bytes(path)

      assert ranges["space"] == {0x03, 0x04}
      assert ranges["punctuation"] == {0x03, 0x04}
      assert ranges["digit"] == {0x0F, 0x0F}
      refute Map.has_key?(ranges, "terminator")
      refute Map.has_key?(ranges, "level-separator")
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
