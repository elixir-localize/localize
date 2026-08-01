defmodule Localize.Message.UnitOptionsTest do
  use ExUnit.Case, async: true

  alias Localize.Message.{Interpreter, Parser}

  defp format(source, bindings) do
    {:ok, parsed} = Parser.parse(source)
    options = [locale: "en-US"]

    case Interpreter.format_list(parsed, bindings, options) do
      {:ok, iolist, _, _} -> :erlang.iolist_to_binary(iolist)
      {:error, iolist, _, _} -> :erlang.iolist_to_binary(iolist)
    end
  end

  defp format_with_locale(source, bindings, locale) do
    {:ok, parsed} = Parser.parse(source)
    options = [locale: locale]

    case Interpreter.format_list(parsed, bindings, options) do
      {:ok, iolist, _, _} -> :erlang.iolist_to_binary(iolist)
      {:error, iolist, _, _} -> :erlang.iolist_to_binary(iolist)
    end
  end

  describe "unit formatting" do
    test "basic unit with long display (default)" do
      assert format("{$dist :unit unit=kilometer}", %{"dist" => 3}) == "3 kilometers"
    end

    test "unit with singular value" do
      assert format("{$dist :unit unit=kilometer}", %{"dist" => 1}) == "1 kilometer"
    end

    test "unit with decimal value" do
      assert format("{$weight :unit unit=kilogram}", %{"weight" => 2.5}) == "2.5 kilograms"
    end

    test "unit with string value" do
      assert format("{$dist :unit unit=meter}", %{"dist" => "100"}) == "100 meters"
    end
  end

  describe "unitDisplay option" do
    test "short displays abbreviated unit" do
      assert format(
               "{$dist :unit unit=kilometer unitDisplay=short}",
               %{"dist" => 3}
             ) == "3 km"
    end

    test "narrow displays minimal unit" do
      assert format(
               "{$dist :unit unit=kilometer unitDisplay=narrow}",
               %{"dist" => 3}
             ) == "3km"
    end

    test "long displays full unit name" do
      assert format(
               "{$dist :unit unit=kilometer unitDisplay=long}",
               %{"dist" => 3}
             ) == "3 kilometers"
    end
  end

  describe "various units" do
    test "temperature" do
      result = format("{$temp :unit unit=fahrenheit}", %{"temp" => 72})
      assert result =~ "72"
      assert result =~ "Fahrenheit" or result =~ "°F"
    end

    test "volume" do
      assert format(
               "{$vol :unit unit=liter unitDisplay=short}",
               %{"vol" => 2}
             ) == "2 L"
    end

    test "weight" do
      assert format(
               "{$w :unit unit=pound unitDisplay=short}",
               %{"w" => 5}
             ) == "5 lb"
    end
  end

  describe "locale-specific formatting" do
    test "German unit formatting" do
      result =
        format_with_locale(
          "{$dist :unit unit=kilometer}",
          %{"dist" => 3},
          "de"
        )

      assert result == "3 Kilometer"
    end

    test "French unit formatting" do
      result =
        format_with_locale(
          "{$dist :unit unit=kilometer unitDisplay=short}",
          %{"dist" => 3},
          "fr"
        )

      assert result =~ "km"
    end
  end

  describe "unit in message context" do
    test "unit value in a sentence" do
      assert format(
               "The distance is {$dist :unit unit=kilometer unitDisplay=short}.",
               %{"dist" => 42}
             ) == "The distance is 42 km."
    end
  end

  describe "Localize.Unit struct" do
    test "derives unit from struct" do
      unit = Localize.Unit.new!(3, "kilometer")
      assert format("{$dist :unit}", %{"dist" => unit}) == "3 kilometers"
    end

    test "derives unit and value from struct with singular" do
      unit = Localize.Unit.new!(1, "kilometer")
      assert format("{$dist :unit}", %{"dist" => unit}) == "1 kilometer"
    end

    test "explicit unit option overrides struct unit" do
      unit = Localize.Unit.new!(3, "kilometer")
      assert format("{$dist :unit unit=meter}", %{"dist" => unit}) == "3 meters"
    end

    test "unitDisplay option applied to struct" do
      unit = Localize.Unit.new!(3, "kilometer")
      assert format("{$dist :unit unitDisplay=short}", %{"dist" => unit}) == "3 km"
    end

    test "struct in a sentence" do
      unit = Localize.Unit.new!(42, "kilometer")

      assert format("The distance is {$dist :unit unitDisplay=short}.", %{"dist" => unit}) ==
               "The distance is 42 km."
    end
  end
end
