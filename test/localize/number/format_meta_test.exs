defmodule Localize.Number.Format.MetaTest do
  use ExUnit.Case, async: true

  alias Localize.Number.Format.Meta

  describe "new/0" do
    test "returns a struct with default values" do
      meta = Meta.new()

      assert %Meta{} = meta
      assert meta.integer_digits == %{min: 1, max: 0}
      assert meta.fractional_digits == %{min: 0, max: 0}
      assert meta.significant_digits == %{min: 0, max: 0}
      assert meta.exponent_digits == 0
      assert meta.exponent_sign == false
      assert meta.engineering_grouping == 0
      assert meta.scientific_rounding == 0
      assert meta.round_nearest == 0
      assert meta.padding_length == 0
      assert meta.padding_char == " "
      assert meta.multiplier == 1
      assert meta.currency == nil
      assert meta.number == 0
    end

    test "default grouping is zero for integer and fraction" do
      meta = Meta.new()

      assert meta.grouping == %{
               fraction: %{first: 0, rest: 0},
               integer: %{first: 0, rest: 0}
             }
    end

    test "default format has a positive and negative section" do
      meta = Meta.new()

      assert meta.format == [
               positive: [format: "#"],
               negative: [minus: ~c"-", format: :same_as_positive]
             ]
    end
  end

  describe "put_integer_digits/3" do
    test "sets min and max integer digits" do
      meta = Meta.new() |> Meta.put_integer_digits(2, 5)
      assert meta.integer_digits == %{min: 2, max: 5}
    end

    test "defaults max to 0 when omitted" do
      meta = Meta.new() |> Meta.put_integer_digits(3)
      assert meta.integer_digits == %{min: 3, max: 0}
    end
  end

  describe "put_fraction_digits/3" do
    test "sets min and max fractional digits" do
      meta = Meta.new() |> Meta.put_fraction_digits(1, 4)
      assert meta.fractional_digits == %{min: 1, max: 4}
    end

    test "defaults max to 0 when omitted" do
      meta = Meta.new() |> Meta.put_fraction_digits(2)
      assert meta.fractional_digits == %{min: 2, max: 0}
    end
  end

  describe "put_significant_digits/3" do
    test "sets min and max significant digits" do
      meta = Meta.new() |> Meta.put_significant_digits(1, 3)
      assert meta.significant_digits == %{min: 1, max: 3}
    end

    test "defaults max to 0 when omitted" do
      meta = Meta.new() |> Meta.put_significant_digits(2)
      assert meta.significant_digits == %{min: 2, max: 0}
    end
  end

  describe "exponent settings" do
    test "put_exponent_digits/2 sets the exponent digit count" do
      meta = Meta.new() |> Meta.put_exponent_digits(2)
      assert meta.exponent_digits == 2
    end

    test "put_exponent_sign/2 sets the forced exponent sign flag" do
      meta = Meta.new() |> Meta.put_exponent_sign(true)
      assert meta.exponent_sign == true
    end

    test "put_engineering_grouping/2 sets the engineering grouping" do
      meta = Meta.new() |> Meta.put_engineering_grouping(3)
      assert meta.engineering_grouping == 3
    end

    test "put_scientific_rounding_digits/2 sets the scientific rounding" do
      meta = Meta.new() |> Meta.put_scientific_rounding_digits(5)
      assert meta.scientific_rounding == 5
    end
  end

  describe "put_round_nearest_digits/2" do
    test "sets the round nearest value" do
      meta = Meta.new() |> Meta.put_round_nearest_digits(25)
      assert meta.round_nearest == 25
    end
  end

  describe "padding" do
    test "put_padding_length/2 sets the padding length" do
      meta = Meta.new() |> Meta.put_padding_length(10)
      assert meta.padding_length == 10
    end

    test "put_padding_char/2 sets the padding character" do
      meta = Meta.new() |> Meta.put_padding_char("*")
      assert meta.padding_char == "*"
    end
  end

  describe "put_multiplier/2" do
    test "sets the multiplier" do
      meta = Meta.new() |> Meta.put_multiplier(100)
      assert meta.multiplier == 100
    end
  end

  describe "put_integer_grouping/2 and put_integer_grouping/3" do
    test "sets distinct first and rest groups" do
      meta = Meta.new() |> Meta.put_integer_grouping(3, 2)
      assert meta.grouping.integer == %{first: 3, rest: 2}
    end

    test "single argument sets first and rest to the same value" do
      meta = Meta.new() |> Meta.put_integer_grouping(3)
      assert meta.grouping.integer == %{first: 3, rest: 3}
    end

    test "does not disturb fraction grouping" do
      meta =
        Meta.new()
        |> Meta.put_fraction_grouping(4)
        |> Meta.put_integer_grouping(3, 2)

      assert meta.grouping.fraction == %{first: 4, rest: 4}
    end
  end

  describe "put_fraction_grouping/2 and put_fraction_grouping/3" do
    test "sets distinct first and rest groups" do
      meta = Meta.new() |> Meta.put_fraction_grouping(2, 3)
      assert meta.grouping.fraction == %{first: 2, rest: 3}
    end

    test "single argument sets first and rest to the same value" do
      meta = Meta.new() |> Meta.put_fraction_grouping(5)
      assert meta.grouping.fraction == %{first: 5, rest: 5}
    end

    test "does not disturb integer grouping" do
      meta =
        Meta.new()
        |> Meta.put_integer_grouping(3)
        |> Meta.put_fraction_grouping(2)

      assert meta.grouping.integer == %{first: 3, rest: 3}
    end
  end

  describe "put_format/2 and put_format/3" do
    test "sets explicit positive and negative formats" do
      positive = [format: "#,##0.00"]
      negative = [literal: "(", format: :same_as_positive, literal: ")"]
      meta = Meta.new() |> Meta.put_format(positive, negative)

      assert meta.format == [positive: positive, negative: negative]
    end

    test "put_format/2 derives the default negative format" do
      positive = [format: "#,##0"]
      meta = Meta.new() |> Meta.put_format(positive)

      assert meta.format == [
               positive: positive,
               negative: [minus: ~c"-", format: :same_as_positive]
             ]
    end
  end

  describe "setters compose in a pipeline" do
    test "all fields updated by a chained pipeline" do
      meta =
        Meta.new()
        |> Meta.put_integer_digits(1, 10)
        |> Meta.put_fraction_digits(2, 2)
        |> Meta.put_significant_digits(0, 0)
        |> Meta.put_exponent_digits(1)
        |> Meta.put_exponent_sign(true)
        |> Meta.put_engineering_grouping(3)
        |> Meta.put_round_nearest_digits(5)
        |> Meta.put_scientific_rounding_digits(4)
        |> Meta.put_padding_length(12)
        |> Meta.put_padding_char("x")
        |> Meta.put_multiplier(1000)
        |> Meta.put_integer_grouping(3, 2)
        |> Meta.put_fraction_grouping(3)
        |> Meta.put_format([format: "#0"], minus: ~c"-", format: :same_as_positive)

      assert meta.integer_digits == %{min: 1, max: 10}
      assert meta.fractional_digits == %{min: 2, max: 2}
      assert meta.significant_digits == %{min: 0, max: 0}
      assert meta.exponent_digits == 1
      assert meta.exponent_sign == true
      assert meta.engineering_grouping == 3
      assert meta.round_nearest == 5
      assert meta.scientific_rounding == 4
      assert meta.padding_length == 12
      assert meta.padding_char == "x"
      assert meta.multiplier == 1000
      assert meta.grouping == %{integer: %{first: 3, rest: 2}, fraction: %{first: 3, rest: 3}}

      assert meta.format == [
               positive: [format: "#0"],
               negative: [minus: ~c"-", format: :same_as_positive]
             ]
    end
  end

  describe "compiled formats produce equivalent Meta values" do
    test "compiled percent pattern agrees with hand-built setters" do
      {:ok, compiled} = Localize.Number.Format.Compiler.format_to_metadata("#,##0%")

      hand_built =
        Meta.new()
        |> Meta.put_integer_grouping(3, 3)
        |> Meta.put_multiplier(100)

      assert compiled.multiplier == hand_built.multiplier
      assert compiled.grouping.integer == hand_built.grouping.integer
    end

    test "compiled padded pattern agrees with hand-built setters" do
      {:ok, compiled} = Localize.Number.Format.Compiler.format_to_metadata("*x#####0")

      hand_built =
        Meta.new()
        |> Meta.put_padding_length(6)
        |> Meta.put_padding_char("x")

      assert compiled.padding_length == hand_built.padding_length
      assert compiled.padding_char == hand_built.padding_char
    end
  end
end
