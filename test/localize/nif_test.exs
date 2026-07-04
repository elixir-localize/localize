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

  # Runs an ICU-backed call, mapping the "NIF not loaded" error to a
  # sentinel so each test can assert either outcome explicitly. The
  # rescue is a true system boundary: `:erlang.nif_error/1` raises
  # ErlangError when the shared library is absent.
  defp safe_nif(function) do
    function.()
  rescue
    ErlangError -> :nif_not_loaded
  end
end
