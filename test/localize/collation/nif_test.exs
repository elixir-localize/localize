defmodule Localize.Collation.NifTest do
  use ExUnit.Case, async: true

  doctest Localize.Collation.Nif

  describe "Localize.Collation.Nif.available?/0" do
    test "returns a boolean" do
      assert is_boolean(Localize.Collation.Nif.available?())
    end
  end

  describe "casing option compatibility" do
    test "casing: :insensitive treats a and A as equal" do
      assert Localize.Collation.compare("a", "A", casing: :insensitive) == :eq
    end

    test "casing: :sensitive distinguishes a and A" do
      assert Localize.Collation.compare("a", "A", casing: :sensitive) == :lt
    end

    test "casing: :insensitive is equivalent to strength: :secondary" do
      result_casing = Localize.Collation.sort(["café", "Cafe", "cafe"], casing: :insensitive)
      result_strength = Localize.Collation.sort(["café", "Cafe", "cafe"], strength: :secondary)
      assert result_casing == result_strength
    end

    test "invalid casing option raises" do
      assert_raise ArgumentError, ~r/invalid casing option/, fn ->
        Localize.Collation.compare("a", "b", casing: :invalid)
      end
    end
  end

  describe "backend option" do
    test "backend: :elixir always uses pure Elixir" do
      assert Localize.Collation.compare("a", "b", backend: :elixir) == :lt
    end

    test "backend: :elixir sort produces correct results" do
      assert Localize.Collation.sort(["b", "a", "c"], backend: :elixir) == ["a", "b", "c"]
    end

    test "backend: :default falls back to elixir when NIF unavailable or options incompatible" do
      # With tailoring options, NIF cannot be used even if available
      result = Localize.Collation.sort(["b", "a"], backend: :default, tailoring: %{})
      assert result == ["a", "b"]
    end

    test "backend: :nif raises when NIF is unavailable" do
      unless Localize.Collation.Nif.available?() do
        assert_raise RuntimeError, ~r/NIF collation backend requested but not available/, fn ->
          Localize.Collation.compare("a", "b", backend: :nif)
        end
      end
    end

    test "backend: :nif with incompatible options raises" do
      if Localize.Collation.Nif.available?() do
        assert_raise ArgumentError, ~r/NIF collation backend does not support/, fn ->
          Localize.Collation.compare("a", "b", backend: :nif, tailoring: %{})
        end
      end
    end
  end

  describe "Localize.Collation.Sensitive companion module" do
    test "compare/2 returns correct results" do
      assert Localize.Collation.Sensitive.compare("a", "b") == :lt
      assert Localize.Collation.Sensitive.compare("b", "a") == :gt
      assert Localize.Collation.Sensitive.compare("a", "a") == :eq
    end

    test "works with Enum.sort/2" do
      sorted = Enum.sort(["c", "a", "b"], Localize.Collation.Sensitive)
      assert sorted == ["a", "b", "c"]
    end

    test "case-sensitive ordering distinguishes case" do
      assert Localize.Collation.Sensitive.compare("a", "A") == :lt
    end
  end

  describe "Localize.Collation.Insensitive companion module" do
    test "compare/2 returns correct results" do
      assert Localize.Collation.Insensitive.compare("a", "b") == :lt
      assert Localize.Collation.Insensitive.compare("b", "a") == :gt
    end

    test "works with Enum.sort/2" do
      sorted = Enum.sort(["c", "a", "b"], Localize.Collation.Insensitive)
      assert sorted == ["a", "b", "c"]
    end

    test "case-insensitive ordering treats a and A as equal" do
      assert Localize.Collation.Insensitive.compare("a", "A") == :eq
    end
  end

  describe "Options.nif_compatible?/1" do
    test "default options are NIF-compatible" do
      assert Localize.Collation.Options.nif_compatible?(%Localize.Collation.Options{})
    end

    test "all strength levels are NIF-compatible" do
      for strength <- [:primary, :secondary, :tertiary, :quaternary, :identical] do
        assert Localize.Collation.Options.nif_compatible?(%Localize.Collation.Options{
                 strength: strength
               })
      end
    end

    test "numeric option is NIF-compatible" do
      assert Localize.Collation.Options.nif_compatible?(%Localize.Collation.Options{
               numeric: true
             })
    end

    test "backwards option is NIF-compatible" do
      assert Localize.Collation.Options.nif_compatible?(%Localize.Collation.Options{
               backwards: true
             })
    end

    test "alternate: :shifted is NIF-compatible" do
      assert Localize.Collation.Options.nif_compatible?(%Localize.Collation.Options{
               alternate: :shifted
             })
    end

    test "case_first is NIF-compatible" do
      assert Localize.Collation.Options.nif_compatible?(%Localize.Collation.Options{
               case_first: :upper
             })

      assert Localize.Collation.Options.nif_compatible?(%Localize.Collation.Options{
               case_first: :lower
             })
    end

    test "case_level is NIF-compatible" do
      assert Localize.Collation.Options.nif_compatible?(%Localize.Collation.Options{
               case_level: true
             })
    end

    test "normalization is NIF-compatible" do
      assert Localize.Collation.Options.nif_compatible?(%Localize.Collation.Options{
               normalization: true
             })
    end

    test "locale tailoring is not NIF-compatible" do
      refute Localize.Collation.Options.nif_compatible?(%Localize.Collation.Options{
               tailoring: %{}
             })
    end

    test "recognized reorder codes are NIF-compatible" do
      assert Localize.Collation.Options.nif_compatible?(%Localize.Collation.Options{
               reorder: [:Grek]
             })

      assert Localize.Collation.Options.nif_compatible?(%Localize.Collation.Options{
               reorder: [:Grek, :Latn]
             })
    end

    test "unrecognized reorder codes are not NIF-compatible" do
      refute Localize.Collation.Options.nif_compatible?(%Localize.Collation.Options{
               reorder: [:Unknown]
             })
    end

    test "non-default max_variable is not NIF-compatible" do
      refute Localize.Collation.Options.nif_compatible?(%Localize.Collation.Options{
               max_variable: :space
             })
    end
  end

  # Tests that verify NIF and Elixir backends produce identical results.
  describe "NIF/Elixir parity" do
    defp assert_parity(a, b, options) do
      nif_result = Localize.Collation.compare(a, b, [{:backend, :nif} | options])
      elixir_result = Localize.Collation.compare(a, b, [{:backend, :elixir} | options])

      assert nif_result == elixir_result,
             "NIF (#{inspect(nif_result)}) != Elixir (#{inspect(elixir_result)}) " <>
               "for compare(#{inspect(a)}, #{inspect(b)}, #{inspect(options)})"
    end

    defp assert_sort_parity(strings, options) do
      nif_result = Localize.Collation.sort(strings, [{:backend, :nif} | options])
      elixir_result = Localize.Collation.sort(strings, [{:backend, :elixir} | options])

      assert nif_result == elixir_result,
             "NIF sort != Elixir sort for #{inspect(options)}"
    end

    @tag :nif
    test "strength: :primary" do
      if Localize.Collation.Nif.available?() do
        assert_parity("a", "A", strength: :primary)
        assert_parity("café", "cafe", strength: :primary)
      end
    end

    @tag :nif
    test "strength: :secondary" do
      if Localize.Collation.Nif.available?() do
        assert_parity("a", "A", strength: :secondary)
        assert_parity("café", "cafe", strength: :secondary)
      end
    end

    @tag :nif
    test "strength: :tertiary" do
      if Localize.Collation.Nif.available?() do
        assert_parity("a", "A", strength: :tertiary)
        assert_parity("café", "cafe", strength: :tertiary)
      end
    end

    @tag :nif
    test "strength: :quaternary" do
      if Localize.Collation.Nif.available?() do
        assert_parity("a", "A", strength: :quaternary)
        assert_parity("café", "cafe", strength: :quaternary)
      end
    end

    @tag :nif
    test "strength: :identical" do
      if Localize.Collation.Nif.available?() do
        assert_parity("a", "A", strength: :identical)
      end
    end

    @tag :nif
    test "backwards: true (French collation)" do
      if Localize.Collation.Nif.available?() do
        assert_parity("côte", "coté", backwards: true)
        assert_parity("côte", "coté", backwards: false)
      end
    end

    @tag :nif
    test "alternate: :shifted" do
      if Localize.Collation.Nif.available?() do
        assert_parity("black-bird", "blackbird", alternate: :shifted)
        assert_parity("black bird", "blackbird", alternate: :shifted)
      end
    end

    @tag :nif
    test "case_first: :upper" do
      if Localize.Collation.Nif.available?() do
        assert_parity("a", "A", case_first: :upper)
        assert_sort_parity(["a", "A", "b", "B"], case_first: :upper)
      end
    end

    @tag :nif
    test "case_first: :lower" do
      if Localize.Collation.Nif.available?() do
        assert_parity("a", "A", case_first: :lower)
        assert_sort_parity(["a", "A", "b", "B"], case_first: :lower)
      end
    end

    @tag :nif
    test "case_level: true" do
      if Localize.Collation.Nif.available?() do
        assert_parity("a", "A", case_level: true)
      end
    end

    @tag :nif
    test "normalization: true" do
      if Localize.Collation.Nif.available?() do
        assert_parity("é", "e\u0301", normalization: true)
      end
    end

    @tag :nif
    test "numeric: true" do
      if Localize.Collation.Nif.available?() do
        assert_parity("2", "10", numeric: true)
        assert_sort_parity(["file10", "file2", "file1"], numeric: true)
      end
    end

    @tag :nif
    test "combined options" do
      if Localize.Collation.Nif.available?() do
        assert_parity("a", "A", strength: :secondary, numeric: true)
        assert_parity("2", "10", strength: :primary, numeric: true)
      end
    end

    @tag :nif
    test "NIF handles numeric option directly" do
      if Localize.Collation.Nif.available?() do
        result = Localize.Collation.compare("2", "10", backend: :nif, numeric: true)
        assert result == :lt
      end
    end

    @tag :nif
    test "reorder: Greek before Latin" do
      if Localize.Collation.Nif.available?() do
        assert Localize.Collation.compare("a", "α", backend: :nif) == :lt

        result = Localize.Collation.compare("α", "a", backend: :nif, reorder: [:Grek])
        assert result == :lt
      end
    end

    @tag :nif
    test "reorder: sort with script reordering" do
      if Localize.Collation.Nif.available?() do
        strings = ["alpha", "α", "beta", "β"]

        nif_result = Localize.Collation.sort(strings, backend: :nif, reorder: [:Grek])

        greek_positions =
          Enum.map(["α", "β"], &Enum.find_index(nif_result, fn s -> s == &1 end))

        latin_positions =
          Enum.map(["alpha", "beta"], &Enum.find_index(nif_result, fn s -> s == &1 end))

        assert Enum.max(greek_positions) < Enum.min(latin_positions),
               "Expected Greek strings before Latin, got: #{inspect(nif_result)}"
      end
    end

    @tag :nif
    test "reorder: empty list is no-op" do
      if Localize.Collation.Nif.available?() do
        assert_parity("a", "α", reorder: [])
      end
    end

    @tag :nif
    test "reorder: with other options combined" do
      if Localize.Collation.Nif.available?() do
        nif_result =
          Localize.Collation.sort(["A", "α", "a"],
            backend: :nif,
            reorder: [:Grek],
            strength: :secondary
          )

        alpha_idx = Enum.find_index(nif_result, &(&1 == "α"))
        assert alpha_idx == 0, "Expected Greek α first, got: #{inspect(nif_result)}"
      end
    end

    @tag :nif
    test "unrecognized reorder codes fall back to Elixir with :default backend" do
      result = Localize.Collation.sort(["b", "a"], backend: :default, reorder: [:Unknown])
      assert result == ["a", "b"]
    end
  end

  describe "Nif.reorder_codes_supported?/1" do
    test "returns true for empty list" do
      assert Localize.Collation.Nif.reorder_codes_supported?([])
    end

    test "returns true for recognized codes" do
      assert Localize.Collation.Nif.reorder_codes_supported?([:Grek, :Latn, :Cyrl])
      assert Localize.Collation.Nif.reorder_codes_supported?([:space, :punct, :digit])
    end

    test "returns false for unrecognized codes" do
      refute Localize.Collation.Nif.reorder_codes_supported?([:Unknown])
      refute Localize.Collation.Nif.reorder_codes_supported?([:Grek, :BadCode])
    end
  end
end
