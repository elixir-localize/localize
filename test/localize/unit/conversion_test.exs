defmodule Localize.Unit.ConversionTest do
  use ExUnit.Case, async: true

  alias Localize.Unit.Conversion

  # ── convertible?/2 ──────────────────────────────────────────────────

  describe "convertible?/2" do
    test "same-category units are convertible" do
      assert Conversion.convertible?("foot", "meter")
      assert Conversion.convertible?("mile-per-hour", "meter-per-second")
      assert Conversion.convertible?("celsius", "fahrenheit")
      assert Conversion.convertible?("kilogram", "pound")
    end

    test "different-category units are not convertible" do
      refute Conversion.convertible?("foot", "kilogram")
      refute Conversion.convertible?("meter", "second")
      refute Conversion.convertible?("watt", "joule")
    end

    test "unit is convertible with itself" do
      assert Conversion.convertible?("meter", "meter")
    end
  end

  # ── convert/3 ───────────────────────────────────────────────────────

  describe "convert/3 basic" do
    test "identity conversion" do
      assert {:ok, 1000.0} = Conversion.convert(1000, "meter", "meter")
    end

    test "returns error for incompatible units" do
      assert {:error, _} = Conversion.convert(1, "meter", "kilogram")
    end

    test "returns error for unknown units" do
      assert {:error, _} = Conversion.convert(1, "foobar", "meter")
    end

    test "accepts integer input" do
      assert {:ok, _} = Conversion.convert(100, "foot", "meter")
    end

    test "accepts float input" do
      assert {:ok, _} = Conversion.convert(100.0, "foot", "meter")
    end
  end

  describe "convert/3 temperature" do
    test "32 fahrenheit → 0 celsius" do
      assert {:ok, result} = Conversion.convert(32, "fahrenheit", "celsius")
      assert_in_delta result, 0.0, 0.001
    end

    test "212 fahrenheit → 100 celsius" do
      assert {:ok, result} = Conversion.convert(212, "fahrenheit", "celsius")
      assert_in_delta result, 100.0, 0.001
    end

    test "0 celsius → 273.15 kelvin" do
      assert {:ok, result} = Conversion.convert(0, "celsius", "kelvin")
      assert_in_delta result, 273.15, 0.001
    end

    test "100 celsius → 373.15 kelvin" do
      assert {:ok, result} = Conversion.convert(100, "celsius", "kelvin")
      assert_in_delta result, 373.15, 0.001
    end
  end

  describe "convert!/3" do
    test "returns value directly on success" do
      assert 304.8 = Conversion.convert!(1000, "foot", "meter")
    end

    test "raises on error" do
      assert_raise Localize.UnitConversionError, fn ->
        Conversion.convert!(1, "meter", "kilogram")
      end
    end
  end

  # ── CLDR unitsTest.txt validation ───────────────────────────────────
  #
  # The test data format is:
  #   quantity ; source_unit ; target_unit ; conversion_expression ; expected_result_for_1000
  #
  # We convert 1000 of the source unit to the target unit and compare
  # against the expected value at the precision indicated by the test data.

  @test_data_path Path.join(
                    Application.compile_env(
                      :localize,
                      :cldr_data_dir,
                      "/Users/kip/Development/cldr_repo"
                    ),
                    "common/testData/units/unitsTest.txt"
                  )

  @external_resource @test_data_path

  @test_cases File.read!(@test_data_path)
              |> String.split("\n")
              |> Enum.reject(fn line ->
                String.starts_with?(line, "#") or String.trim(line) == ""
              end)
              |> Enum.map(fn line ->
                [_quantity, source, target, _expression, expected] =
                  String.split(line, "\t;\t")

                source = String.trim(source)
                target = String.trim(target)
                expected = String.trim(expected) |> String.replace(",", "")

                {source, target, expected}
              end)

  describe "CLDR unitsTest.txt conversions (1000 x → y)" do
    for {source, target, expected_str} <- @test_cases do
      @source source
      @target target
      @expected_str expected_str

      test "#{source} → #{target} (expected #{expected_str})" do
        expected = parse_test_number(@expected_str)

        case Conversion.convert(1000, @source, @target) do
          {:ok, result} ->
            precision = determine_precision(@expected_str)

            assert_in_delta result,
                            expected,
                            precision,
                            "Converting 1000 #{@source} → #{@target}: expected #{expected}, got #{result}"

          {:error, reason} ->
            flunk("Failed to convert #{@source} → #{@target}: #{reason}")
        end
      end
    end
  end

  # ── Helpers ─────────────────────────────────────────────────────────

  defp parse_test_number(string) do
    cleaned = String.replace(string, ",", "")

    cond do
      String.contains?(cleaned, "E") ->
        {value, ""} = Float.parse(cleaned)
        value

      String.contains?(cleaned, ".") ->
        {value, ""} = Float.parse(cleaned)
        value

      true ->
        String.to_integer(cleaned) * 1.0
    end
  end

  # Determine acceptable precision based on the expected value's
  # significant digits in the test data.
  defp determine_precision(expected_str) do
    cleaned = String.replace(expected_str, ",", "")

    cond do
      String.contains?(cleaned, "E") ->
        # Scientific notation: precision is relative
        {value, ""} = Float.parse(cleaned)
        abs(value) * 1.0e-4

      String.contains?(cleaned, ".") ->
        # Count decimal places
        [_int, frac] = String.split(cleaned, ".")
        decimal_places = String.length(frac)
        :math.pow(10, -decimal_places) * 5

      true ->
        0.5
    end
  end
end
