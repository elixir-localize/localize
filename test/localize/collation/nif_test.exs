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

    test "invalid casing option is an error" do
      assert {:error, %Localize.InvalidValueError{} = error} =
               Localize.Collation.compare("a", "b", casing: :invalid)

      assert Exception.message(error) =~ "casing"
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

    test "backend: :nif falls back to elixir when NIF is unavailable" do
      # When NIF is not available, backend: :nif silently falls back to Elixir
      assert Localize.Collation.compare("a", "b", backend: :nif) == :lt
    end

    test "backend: :nif with incompatible options falls back to elixir" do
      # When NIF can't handle the options, it silently falls back to Elixir
      assert Localize.Collation.compare("a", "b", backend: :nif, tailoring: %{}) == :lt
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

  describe "sort in one NIF call" do
    @sort_alphabet String.graphemes("abcABCéèÉñÑöß012 .-_,") ++ ["中", "α", "Ω", "я"]

    @sort_options [
      [],
      [numeric: true],
      [strength: :primary],
      [strength: :secondary],
      [strength: :quaternary, alternate: :shifted],
      [strength: :identical],
      [alternate: :shifted],
      [case_first: :upper],
      [case_first: :lower],
      [case_level: true, strength: :primary],
      [backwards: true],
      [reorder: [:Grek, :Latn]]
    ]

    defp random_strings(seed) do
      :rand.seed(:exsss, {seed, seed, seed})

      for _ <- 1..300 do
        length = :rand.uniform(12)
        Enum.map_join(1..length, fn _ -> Enum.random(@sort_alphabet) end)
      end
    end

    # The order the NIF backend gave before sorting in one call: a stable
    # sort that compares each pair through the NIF.
    defp pairwise_nif_sort(strings, options) do
      options = Localize.Collation.Options.new([{:backend, :nif} | options])

      Enum.sort(strings, fn a, b ->
        Localize.Collation.Nif.nif_compare(a, b, options) in [:lt, :eq]
      end)
    end

    @tag :nif
    test "gives the order pairwise NIF compares give, for every option" do
      if Localize.Collation.Nif.available?() do
        for {options, seed} <- Enum.with_index(@sort_options, 1) do
          strings = random_strings(seed)

          assert Localize.Collation.sort(strings, [{:backend, :nif} | options]) ==
                   pairwise_nif_sort(strings, options),
                 "one-call NIF sort differs from pairwise compares for #{inspect(options)}"
        end
      end
    end

    @tag :nif
    test "keeps collation-equal strings in their input order" do
      if Localize.Collation.Nif.available?() do
        assert Localize.Collation.sort(["b", "B", "a", "A", "á"],
                 backend: :nif,
                 strength: :primary
               ) ==
                 ["a", "A", "á", "b", "B"]

        assert Localize.Collation.sort(["A", "a"], backend: :nif, strength: :primary) == [
                 "A",
                 "a"
               ]
      end
    end

    @tag :nif
    test "an empty or single-element list" do
      if Localize.Collation.Nif.available?() do
        assert Localize.Collation.sort([], backend: :nif) == []
        assert Localize.Collation.sort(["x"], backend: :nif) == ["x"]
      end
    end

    @tag :nif
    test "a string over the NIF's size cap is sorted by the Elixir backend instead" do
      if Localize.Collation.Nif.available?() do
        long = String.duplicate("b", 1_048_577)

        assert Localize.Nif.nif_collation_sort(["c", long], -1, -1, -1, -1, -1, -1, -1, <<>>) ==
                 {:error, :too_large}

        assert Localize.Collation.sort(["c", long, "a"], backend: :nif) == ["a", long, "c"]
      end
    end
  end

  describe "concurrent NIF calls" do
    # Each pooled collator is given a call's options and reset after it. If
    # two concurrent calls were ever given the same collator, one would sort
    # or compare with the other's options, so results under concurrency are
    # checked against the same calls made one at a time.
    @concurrent_options [
      [backend: :nif],
      [backend: :nif, strength: :primary],
      [backend: :nif, numeric: true],
      [backend: :nif, case_first: :upper],
      [backend: :nif, alternate: :shifted, strength: :quaternary],
      [backend: :nif, reorder: [:Grek, :Latn]]
    ]

    @tag :nif
    test "concurrent sorts and compares with different options do not share a collator" do
      if Localize.Collation.Nif.available?() do
        :rand.seed(:exsss, {7, 7, 7})
        alphabet = String.graphemes("aAbBéÉ1 10 2-_α") ++ ["Ω", "10", "9"]

        strings =
          for _ <- 1..400 do
            Enum.map_join(1..:rand.uniform(10), fn _ -> Enum.random(alphabet) end)
          end

        pairs = Enum.zip(strings, Enum.reverse(strings))

        expected =
          Map.new(@concurrent_options, fn options ->
            compares = Enum.map(pairs, fn {a, b} -> Localize.Collation.compare(a, b, options) end)
            {options, {Localize.Collation.sort(strings, options), compares}}
          end)

        results =
          1..(System.schedulers_online() * 8)
          |> Task.async_stream(
            fn index ->
              options = Enum.at(@concurrent_options, rem(index, length(@concurrent_options)))

              for _ <- 1..10 do
                compares =
                  Enum.map(pairs, fn {a, b} -> Localize.Collation.compare(a, b, options) end)

                {options, {Localize.Collation.sort(strings, options), compares}}
              end
            end,
            max_concurrency: System.schedulers_online() * 4,
            timeout: :infinity
          )
          |> Enum.flat_map(fn {:ok, runs} -> runs end)

        mismatches = Enum.count(results, fn {options, result} -> result != expected[options] end)

        assert mismatches == 0,
               "#{mismatches} of #{length(results)} concurrent runs gave another call's order"
      end
    end
  end
end
