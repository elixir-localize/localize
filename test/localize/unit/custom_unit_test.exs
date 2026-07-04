defmodule Localize.Unit.CustomUnitTest do
  use ExUnit.Case, async: false

  # Doctests for the registry are wired here (not in an async module)
  # because they mutate the global :persistent_term registry. The
  # setup block clears the registry around every test, doctests
  # included.
  doctest Localize.Unit.CustomRegistry

  alias Localize.Unit
  alias Localize.Unit.CustomRegistry

  setup do
    CustomRegistry.clear()
    on_exit(fn -> CustomRegistry.clear() end)
  end

  describe "define_unit/2" do
    test "registers a simple custom unit" do
      assert :ok =
               Unit.define_unit("smoot", %{
                 base_unit: "meter",
                 factor: 1.7018,
                 category: "length"
               })

      assert CustomRegistry.registered?("smoot")
    end

    test "registers a unit with display data" do
      assert :ok =
               Unit.define_unit("smoot", %{
                 base_unit: "meter",
                 factor: 1.7018,
                 category: "length",
                 display: %{
                   en: %{
                     long: %{one: "{0} smoot", other: "{0} smoots"}
                   }
                 }
               })

      definition = CustomRegistry.get("smoot")
      assert definition.display.en.long.other == "{0} smoots"
    end

    test "rejects invalid unit name" do
      assert {:error, message} =
               Unit.define_unit("123bad", %{
                 base_unit: "meter",
                 factor: 1.0,
                 category: "length"
               })

      assert message =~ "invalid unit name"
    end

    test "rejects missing base_unit" do
      assert {:error, message} =
               Unit.define_unit("smoot", %{
                 factor: 1.0,
                 category: "length"
               })

      assert message =~ "missing required key: base_unit"
    end

    test "rejects unknown base unit" do
      assert {:error, message} =
               Unit.define_unit("smoot", %{
                 base_unit: "nonexistent",
                 factor: 1.0,
                 category: "length"
               })

      assert message =~ "unknown base unit"
    end

    test "accepts custom category" do
      assert :ok =
               Unit.define_unit("smoot", %{
                 base_unit: "meter",
                 factor: 1.0,
                 category: "custom-stuff"
               })

      assert CustomRegistry.get("smoot").category == "custom-stuff"
    end

    test "rejects empty category" do
      assert {:error, message} =
               Unit.define_unit("smoot", %{
                 base_unit: "meter",
                 factor: 1.0,
                 category: ""
               })

      assert message =~ "invalid category"
    end

    test "rejects negative factor" do
      assert {:error, message} =
               Unit.define_unit("smoot", %{
                 base_unit: "meter",
                 factor: -1.0,
                 category: "length"
               })

      assert message =~ "factor must be positive"
    end

    test "rejects collision with existing CLDR unit" do
      assert {:error, message} =
               Unit.define_unit("meter", %{
                 base_unit: "meter",
                 factor: 1.0,
                 category: "length"
               })

      assert message =~ "already exists"
    end
  end

  describe "new/2 with custom unit" do
    test "creates a unit struct for a custom unit" do
      Unit.define_unit("smoot", %{
        base_unit: "meter",
        factor: 1.7018,
        category: "length"
      })

      assert {:ok, unit} = Unit.new(3, "smoot")
      assert unit.name == "smoot"
      assert unit.value == 3
    end
  end

  describe "convert/2 with custom unit" do
    test "converts custom unit to base unit" do
      Unit.define_unit("smoot", %{
        base_unit: "meter",
        factor: 1.7018,
        category: "length"
      })

      {:ok, unit} = Unit.new(3, "smoot")
      {:ok, result} = Unit.convert(unit, "meter")
      assert result.name == "meter"
      assert_in_delta result.value, 5.1054, 0.001
    end

    test "converts base unit to custom unit" do
      Unit.define_unit("smoot", %{
        base_unit: "meter",
        factor: 1.7018,
        category: "length"
      })

      {:ok, unit} = Unit.new(5.1054, "meter")
      {:ok, result} = Unit.convert(unit, "smoot")
      assert result.name == "smoot"
      assert_in_delta result.value, 3.0, 0.001
    end

    test "converts custom unit to another conformable unit" do
      Unit.define_unit("smoot", %{
        base_unit: "meter",
        factor: 1.7018,
        category: "length"
      })

      {:ok, unit} = Unit.new(1, "smoot")
      {:ok, result} = Unit.convert(unit, "foot")
      assert result.name == "foot"
      assert_in_delta result.value, 5.582, 0.01
    end

    test "converts between two custom units" do
      Unit.define_unit("smoot", %{
        base_unit: "meter",
        factor: 1.7018,
        category: "length"
      })

      Unit.define_unit("cubit", %{
        base_unit: "meter",
        factor: 0.4572,
        category: "length"
      })

      {:ok, unit} = Unit.new(1, "smoot")
      {:ok, result} = Unit.convert(unit, "cubit")
      assert result.name == "cubit"
      assert_in_delta result.value, 3.723, 0.01
    end
  end

  describe "to_string/2 with custom unit" do
    test "formats with custom display patterns" do
      Unit.define_unit("smoot", %{
        base_unit: "meter",
        factor: 1.7018,
        category: "length",
        display: %{
          en: %{
            long: %{one: "{0} smoot", other: "{0} smoots"}
          }
        }
      })

      {:ok, unit} = Unit.new(3, "smoot")
      {:ok, formatted} = Unit.to_string(unit, locale: :en)
      assert formatted == "3 smoots"
    end

    test "formats singular form" do
      Unit.define_unit("smoot", %{
        base_unit: "meter",
        factor: 1.7018,
        category: "length",
        display: %{
          en: %{
            long: %{one: "{0} smoot", other: "{0} smoots"}
          }
        }
      })

      {:ok, unit} = Unit.new(1, "smoot")
      {:ok, formatted} = Unit.to_string(unit, locale: :en)
      assert formatted == "1 smoot"
    end

    test "falls back to bare name when no display data" do
      Unit.define_unit("smoot", %{
        base_unit: "meter",
        factor: 1.7018,
        category: "length"
      })

      {:ok, unit} = Unit.new(3, "smoot")
      {:ok, formatted} = Unit.to_string(unit, locale: :en)
      assert formatted == "3 smoot"
    end
  end

  describe "SI prefix with custom unit" do
    setup do
      Unit.define_unit("smoot", %{base_unit: "meter", factor: 1.7018, category: "length"})
      :ok
    end

    test "parses kilosmoot" do
      assert {:ok, unit} = Unit.new(5, "kilosmoot")
      assert unit.name == "kilosmoot"
    end

    test "parses millismoot" do
      assert {:ok, unit} = Unit.new(3, "millismoot")
      assert unit.name == "millismoot"
    end

    test "converts kilosmoot to meter" do
      {:ok, unit} = Unit.new(5, "kilosmoot")
      {:ok, result} = Unit.convert(unit, "meter")
      assert_in_delta result.value, 8509.0, 0.1
    end

    test "converts kilosmoot to smoot" do
      {:ok, unit} = Unit.new(2, "kilosmoot")
      {:ok, result} = Unit.convert(unit, "smoot")
      assert_in_delta result.value, 2000.0, 0.1
    end
  end

  describe "power prefix with custom unit" do
    setup do
      Unit.define_unit("smoot", %{base_unit: "meter", factor: 1.7018, category: "length"})
      :ok
    end

    test "parses square-smoot" do
      assert {:ok, unit} = Unit.new(5, "square-smoot")
      assert unit.name == "square-smoot"
    end

    test "parses cubic-smoot" do
      assert {:ok, unit} = Unit.new(5, "cubic-smoot")
      assert unit.name == "cubic-smoot"
    end

    test "parses pow4-smoot" do
      assert {:ok, unit} = Unit.new(5, "pow4-smoot")
      assert unit.name == "pow4-smoot"
    end

    test "converts square-smoot to square-meter" do
      {:ok, unit} = Unit.new(5, "square-smoot")
      {:ok, result} = Unit.convert(unit, "square-meter")
      assert_in_delta result.value, 14.4806, 0.01
    end
  end

  describe "combined SI + power prefix with custom unit" do
    setup do
      Unit.define_unit("smoot", %{base_unit: "meter", factor: 1.7018, category: "length"})
      :ok
    end

    test "parses square-kilosmoot" do
      assert {:ok, unit} = Unit.new(5, "square-kilosmoot")
      assert unit.name == "square-kilosmoot"
    end
  end

  describe "compound custom unit" do
    setup do
      Unit.define_unit("smoot", %{base_unit: "meter", factor: 1.7018, category: "length"})
      :ok
    end

    test "parses smoot-per-second" do
      assert {:ok, unit} = Unit.new(5, "smoot-per-second")
      assert unit.name == "smoot-per-second"
    end
  end

  describe "SI prefix guard against greedy consumption" do
    test "decathlon is not split into deca + thlon" do
      Unit.define_unit("decathlon", %{
        base_unit: "second",
        factor: 86_400.0,
        category: "duration"
      })

      {:ok, unit} = Unit.new(1, "decathlon")
      assert unit.name == "decathlon"

      # Verify it parsed as a bare unit, not deca-prefixed
      {:unit, parts} = unit.parsed
      [single_unit: props] = parts[:numerator]
      assert props[:prefix] == nil
      assert props[:base] == "decathlon"
    end
  end

  describe "load_custom_units/1" do
    test "loads from fixture file" do
      path = Path.join([__DIR__, "..", "..", "support", "fixtures", "custom_units.exs"])
      assert {:ok, 3} = Unit.load_custom_units(path)
      assert CustomRegistry.registered?("smoot")
      assert CustomRegistry.registered?("cubit")
      assert CustomRegistry.registered?("scarmucci")
    end

    test "returns error for missing file" do
      assert {:error, message} = Unit.load_custom_units("nonexistent.exs")
      assert message =~ "file not found"
    end

    test "returns error when file has valid syntax but wrong shape" do
      path = Path.join([__DIR__, "..", "..", "support", "fixtures", "custom_units_bad_shape.exs"])
      assert {:error, message} = Unit.load_custom_units(path)
      assert message =~ "invalid definition"
    end

    test "returns error when file has invalid Elixir syntax" do
      path =
        Path.join([__DIR__, "..", "..", "support", "fixtures", "custom_units_bad_syntax.bad_exs"])

      assert {:error, message} = Unit.load_custom_units(path)
      assert message =~ "missing terminator"
    end
  end

  describe "custom registry" do
    test "clear removes all registrations" do
      Unit.define_unit("smoot", %{
        base_unit: "meter",
        factor: 1.7018,
        category: "length"
      })

      assert CustomRegistry.registered?("smoot")
      CustomRegistry.clear()
      refute CustomRegistry.registered?("smoot")
    end

    test "all returns all registered units" do
      Unit.define_unit("smoot", %{base_unit: "meter", factor: 1.7018, category: "length"})
      Unit.define_unit("cubit", %{base_unit: "meter", factor: 0.4572, category: "length"})

      all = CustomRegistry.all()
      assert map_size(all) == 2
      assert Map.has_key?(all, "smoot")
      assert Map.has_key?(all, "cubit")
    end
  end
end
