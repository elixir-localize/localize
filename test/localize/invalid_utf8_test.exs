defmodule Localize.InvalidUtf8Test do
  @moduledoc """
  A binary that is not UTF-8 is not a string. Every public function that
  reads text answers one with its documented error rather than raising: the
  Unicode regular expressions, case folding and code point conversions it
  reads text with raise on such input. Each case here raised before.

  """

  use ExUnit.Case, async: true

  # A lone 0xFF byte, and one inside otherwise valid text.
  @invalid [<<255>>, <<"3 kilo", 255, "meters">>]

  describe "number and unit parsing" do
    test "Localize.Number.parse/2 and scan/2 return an error" do
      for input <- @invalid do
        assert {:error, %Localize.InvalidValueError{value: ^input}} = Localize.Number.parse(input)
        assert {:error, %Localize.InvalidValueError{value: ^input}} = Localize.Number.scan(input)
      end
    end

    test "Localize.Unit.parse/2 returns an error, and parse!/2 raises Localize's" do
      for input <- @invalid do
        assert {:error, %Localize.InvalidValueError{value: ^input}} = Localize.Unit.parse(input)
        assert_raise Localize.InvalidValueError, fn -> Localize.Unit.parse!(input) end
      end
    end
  end

  describe "format patterns" do
    test "a number format pattern" do
      alias Localize.Number.Format.Compiler

      for input <- @invalid do
        assert {:error, %Localize.InvalidValueError{value: ^input}, 1} = Compiler.tokenize(input)
        assert {:error, message} = Compiler.parse(input)
        assert message =~ "UTF-8"
        assert {:error, ^message} = Compiler.compile(input)
        assert {:error, ^message} = Compiler.format_to_metadata(input)

        assert {:error, %Localize.InvalidValueError{}} =
                 Localize.Number.to_string(1234, format: input)
      end
    end

    test "a date or time pattern" do
      for input <- @invalid do
        assert {:error, %Localize.DateTimeFormatError{reason: :invalid_format}} =
                 Localize.Date.to_string(~D[2024-07-06], format: input)

        assert {:error, %Localize.DateTimeFormatError{reason: :invalid_format}} =
                 Localize.Time.to_string(~T[14:30:00], format: input)

        assert {:error, %Localize.DateTimeFormatError{reason: :invalid_format}} =
                 Localize.DateTime.to_string(~N[2024-07-06 14:30:00], format: input)

        assert {:error, %Localize.DateTimeFormatError{}} =
                 Localize.DateTime.to_string(~N[2024-07-06 14:30:00],
                   date_format: input,
                   time_format: :short
                 )
      end
    end

    test "an interval pattern" do
      for input <- @invalid do
        assert {:error, %Localize.DateTimeIntervalFormatError{reason: :invalid_format}} =
                 Localize.Interval.split_interval(input)

        # A date interval takes a pattern as a date does, so an invalid one is
        # the date formatter's error for it.
        assert {:error, %Localize.DateTimeFormatError{reason: :invalid_format}} =
                 Localize.Interval.to_string(~D[2024-07-06], ~D[2024-07-10], format: input)
      end
    end

    test "a semantic skeleton code" do
      for input <- @invalid do
        assert {:error, %Localize.InvalidValueError{value: ^input}} =
                 Localize.DateTime.SemanticSkeleton.new(input)
      end
    end
  end

  describe "names and text" do
    test "a territory name" do
      for input <- @invalid do
        assert {:error, %Localize.InvalidValueError{value: ^input}} =
                 Localize.Territory.normalize_name(input)

        assert {:error, %Localize.InvalidValueError{value: ^input}} =
                 Localize.Territory.to_territory_code(input, :en)

        assert {:error, %Localize.InvalidValueError{value: ^input}} =
                 Localize.Territory.translate_territory(input, :en)

        assert_raise Localize.InvalidValueError, fn ->
          Localize.Territory.to_territory_code!(input, :en)
        end
      end
    end

    test "collation" do
      for input <- @invalid do
        assert {:error, %Localize.InvalidValueError{value: ^input}} =
                 Localize.Collation.compare(input, "a")

        assert {:error, %Localize.InvalidValueError{value: ^input}} =
                 Localize.Collation.compare("a", input)

        assert {:error, %Localize.InvalidValueError{value: ^input}} =
                 Localize.Collation.sort(["a", input])

        assert {:error, %Localize.InvalidValueError{value: ^input}} =
                 Localize.Collation.sort_key(input)
      end
    end

    test "inflection" do
      alias Localize.Inflection.Concept

      for input <- @invalid do
        assert {:error, %Localize.InvalidValueError{value: ^input}} =
                 Localize.Inflection.inflect(input, :de, %{case: "dative"})

        assert {:error, %Localize.InvalidValueError{value: ^input}} =
                 Localize.Inflection.feature(input, :de, :gender)

        refute Localize.Inflection.known?(input, :de)

        assert {:error, %Localize.InvalidValueError{value: ^input}} = Concept.new(:en, input)

        assert {:error, %Localize.InvalidValueError{value: ^input}} =
                 Concept.new(:en, {"cat", input})
      end
    end

    test "an MF2 inflection operand" do
      for input <- @invalid do
        assert {:error, %Localize.FormatError{}} =
                 Localize.Message.format("{$x :i:inflect case=dative}", %{"x" => input},
                   locale: :de
                 )

        assert {:error, %Localize.FormatError{}} =
                 Localize.Message.format("{$x :i:quantify withValue=$n}", %{
                   "x" => input,
                   "n" => 3
                 })
      end
    end
  end
end
