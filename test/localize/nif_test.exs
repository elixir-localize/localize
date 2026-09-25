defmodule Localize.NifTest do
  use ExUnit.Case, async: true

  alias Localize.Nif

  doctest Localize.Nif

  # The NIF is optional: these tests assert the pure Elixir paths
  # unconditionally and exercise the ICU-backed paths only when the
  # shared library is loaded, so the suite passes with or without
  # the NIF compiled.

  describe "availability checks" do
    test "available?/0 returns a boolean" do
      assert is_boolean(Nif.available?())
    end

    test "collation_available?/0 returns a boolean" do
      assert is_boolean(Nif.collation_available?())
    end
  end

  describe "mf2_format/3 unbound variable detection (pure Elixir path)" do
    test "returns a BindError when a variable has no binding" do
      assert {:error, %Localize.BindError{unbound: ["name"]}} =
               Nif.mf2_format("Hello {$name}", "en", %{})
    end

    test "accepts JSON string arguments" do
      assert {:error, %Localize.BindError{unbound: ["name"]}} =
               Nif.mf2_format("Hi {$name}", "en", ~s({"other": 1}))
    end

    test "local declarations do not count as unbound" do
      result = safe_nif(fn -> Nif.mf2_format(".local $x = {1} {{X is {$x}}}", "en", %{}) end)

      if Nif.available?() do
        assert result == {:ok, "X is 1"}
      else
        assert result == :nif_not_loaded
      end
    end
  end

  # These arguments are refused before the NIF is called, so the checks
  # hold whether or not it is loaded.
  describe "mf2_format/3 arguments" do
    test "arguments ICU cannot take are an error, not a raise" do
      for args <- [
            "{not json",
            "[1, 2]",
            ~s({"x": true}),
            [x: 1],
            %{"x" => {1, 2}},
            %{"x" => ~U[2026-09-26 10:30:00Z]},
            %{"x" => <<255>>},
            %{"x" => Bitwise.bsl(1, 70)},
            %{"x" => nil}
          ] do
        assert {:error, %Localize.InvalidValueError{}} = Nif.mf2_format("{$x}", "en", args)
      end
    end

    test "a message or locale that is not a string is an error" do
      assert {:error, %Localize.InvalidValueError{}} = Nif.mf2_format(:hello, "en", %{})
      assert {:error, %Localize.InvalidValueError{}} = Nif.mf2_format("{$x}", :en, %{"x" => 1})
    end
  end

  describe "ICU-backed functions when the NIF is loaded" do
    test "mf2_validate/1 normalizes a valid message and rejects an invalid one" do
      case safe_nif(fn -> Nif.mf2_validate("Hello world") end) do
        :nif_not_loaded ->
          refute Nif.available?()

        result ->
          assert result == {:ok, "{{Hello world}}"}
          assert {:error, reason} = Nif.mf2_validate("{unclosed")
          assert reason =~ "parse error"
      end
    end

    test "mf2_format/3 formats bound variables" do
      case safe_nif(fn -> Nif.mf2_format("Hello {$name}", "en", %{"name" => "World"}) end) do
        :nif_not_loaded -> refute Nif.available?()
        result -> assert result == {:ok, "Hello World"}
      end
    end

    test "plural_rule/3 classifies integers, floats and Decimals" do
      case safe_nif(fn -> Nif.plural_rule(1, "en", :cardinal) end) do
        :nif_not_loaded ->
          refute Nif.available?()

        result ->
          assert result == {:ok, :one}
          assert Nif.plural_rule(2, "en", :ordinal) == {:ok, :two}
          assert Nif.plural_rule(1.0, "en") == {:ok, :one}
          assert Nif.plural_rule(Decimal.new("1.5"), "en", :cardinal) == {:ok, :other}
      end
    end

    test "number_format/3 formats currencies and honours options" do
      options = [
        currency: "USD",
        min_fraction_digits: 2,
        max_fraction_digits: 2,
        notation: "standard",
        use_grouping: true
      ]

      case safe_nif(fn -> Nif.number_format(1234.5, "en", options) end) do
        :nif_not_loaded ->
          refute Nif.available?()

        result ->
          assert result == {:ok, "$1,234.50"}
          assert Nif.number_format(1234, "de", use_grouping: false) == {:ok, "1234"}
      end
    end

    test "mf2_format/3 reads JSON escapes and exponent numbers" do
      case safe_nif(fn -> Nif.mf2_format("{$x}", "en", ~s({"x": "a\\u0001b"})) end) do
        :nif_not_loaded ->
          refute Nif.available?()

        result ->
          assert result == {:ok, "a\u0001b"}
          assert Nif.mf2_format("{$x}", "en", ~s({"x": "\\b\\f"})) == {:ok, "\b\f"}
          assert Nif.mf2_format("{$x}", "en", ~s({"x": "\\ud83d\\ude00"})) == {:ok, "😀"}

          assert Nif.mf2_format("{$x :number}", "en", ~s({"x": 1.0e20})) ==
                   {:ok, "100,000,000,000,000,000,000"}
      end
    end

    test "unit_format/4 formats units and converts unit names to ICU form" do
      case safe_nif(fn -> Nif.unit_format(5, "meter", "en") end) do
        :nif_not_loaded ->
          refute Nif.available?()

        result ->
          assert result == {:ok, "5 meters"}
          assert Nif.unit_format(5, "mile_per_hour", "en", style: :short) == {:ok, "5 mph"}
      end
    end
  end

  # Runs an ICU-backed call when the shared library is loaded, and returns a
  # sentinel otherwise, so each test can assert either outcome explicitly.
  # Without the library the call would raise, so it is not made.
  defp safe_nif(function) do
    if Nif.available?(), do: function.(), else: :nif_not_loaded
  end
end
