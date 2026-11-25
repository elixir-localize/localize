defmodule Localize.Message.ListOptionsTest do
  use ExUnit.Case, async: true

  alias Localize.Message.{Interpreter, Parser}

  defp format(source, bindings), do: format_with_locale(source, bindings, "en-US")

  defp format_with_locale(source, bindings, locale) do
    {:ok, parsed} = Parser.parse(source)
    options = [locale: locale, bidi: :none]

    case Interpreter.format_list(parsed, bindings, options) do
      {:ok, iolist, _, _} -> :erlang.iolist_to_binary(iolist)
      {:error, iolist, _, _} -> :erlang.iolist_to_binary(iolist)
    end
  end

  describe ":list without the localize namespace (deprecated)" do
    test "formats as :localize:list does, with its options" do
      bindings = %{"items" => ["red", "green", "blue"]}

      assert format("{$items :list style=or}", bindings) ==
               format("{$items :localize:list style=or}", bindings)

      assert format("{$items :list}", bindings) == "red, green, and blue"
    end

    test "returns the error :localize:list returns for an operand that is not a list" do
      assert {:error, %Localize.FormatError{}} =
               Localize.Message.format("{$items :list}", %{"items" => 3}, locale: :en)
    end
  end

  describe ":localize:list — default style" do
    test "joins three string elements with the standard 'and' conjunction" do
      assert "apple, banana, and cherry" =
               format("{$items :localize:list}", %{"items" => ["apple", "banana", "cherry"]})
    end

    test "two elements use the locale's two-element pattern" do
      assert "apple and banana" =
               format("{$items :localize:list}", %{"items" => ["apple", "banana"]})
    end

    test "single element renders the element by itself" do
      assert "apple" = format("{$items :localize:list}", %{"items" => ["apple"]})
    end

    test "empty list renders as an empty string" do
      assert "" = format("{$items :localize:list}", %{"items" => []})
    end
  end

  describe ":localize:list — style option" do
    test "style=or uses the disjunctive pattern" do
      assert "apple, banana, or cherry" =
               format(
                 ~S({$items :localize:list style=or}),
                 %{"items" => ["apple", "banana", "cherry"]}
               )
    end

    test "style=or-narrow uses the narrow disjunctive pattern" do
      assert "a, b, or c" =
               format(
                 ~S({$items :localize:list style=or-narrow}),
                 %{"items" => ["a", "b", "c"]}
               )
    end

    test "style=unit-narrow joins with no conjunction" do
      assert "a b c" =
               format(
                 ~S({$items :localize:list style=unit-narrow}),
                 %{"items" => ["a", "b", "c"]}
               )
    end

    test "style=and is the default standard list style" do
      assert "a, b, and c" =
               format(
                 ~S({$items :localize:list style=and}),
                 %{"items" => ["a", "b", "c"]}
               )
    end

    test "type option is accepted as an alias for style" do
      assert "apple, banana, or cherry" =
               format(
                 ~S({$items :localize:list type=or}),
                 %{"items" => ["apple", "banana", "cherry"]}
               )
    end
  end

  describe ":localize:list — locale-aware element formatting" do
    test "numbers are formatted with the message's locale" do
      assert "1.234 und 5.678" =
               format_with_locale(
                 "{$items :localize:list}",
                 %{"items" => [1234, 5678]},
                 "de"
               )
    end

    test "floats use the locale's decimal separator" do
      assert "1.234,5 und 5.678,9" =
               format_with_locale(
                 "{$items :localize:list}",
                 %{"items" => [1234.5, 5678.9]},
                 "de"
               )
    end

    test "dates use the locale's calendar pattern" do
      assert "Jul 10, 2025 and Aug 15, 2025" =
               format(
                 "{$items :localize:list}",
                 %{"items" => [~D[2025-07-10], ~D[2025-08-15]]}
               )
    end

    test "Localize.Unit elements are formatted with the locale" do
      {:ok, km} = Localize.Unit.new(42, "kilometer")
      {:ok, kg} = Localize.Unit.new(3, "kilogram")

      assert "42 kilometers and 3 kilograms" =
               format("{$items :localize:list}", %{"items" => [km, kg]})
    end

    test "atoms fall through to Kernel.to_string" do
      assert "foo and bar" =
               format("{$items :localize:list}", %{"items" => [:foo, :bar]})
    end

    test "French locale uses 'et' as the conjunction" do
      assert "a, b et c" =
               format_with_locale(
                 "{$items :localize:list}",
                 %{"items" => ["a", "b", "c"]},
                 "fr"
               )
    end
  end

  describe ":localize:list — interpolation in larger messages" do
    test "list expression embedded in surrounding text" do
      assert "You have apple, banana, and cherry in your cart." =
               format(
                 "You have {$items :localize:list} in your cart.",
                 %{"items" => ["apple", "banana", "cherry"]}
               )
    end

    test "list expression in a quoted-pattern complex message" do
      message = """
      .input {$items :localize:list}
      {{Available: {$items}}}\
      """

      assert "Available: a, b, and c" =
               format(message, %{"items" => ["a", "b", "c"]})
    end
  end

  describe ":localize:list — error handling" do
    test "non-list operand returns a format error" do
      {:ok, parsed} = Parser.parse("{$item :localize:list}")

      assert {:format_error, {:formatter_failed, detail}} =
               Interpreter.format_list(parsed, %{"item" => "not a list"}, locale: "en")

      assert detail =~ "requires a list operand"
    end

    test "invalid style atom surfaces as an error from Localize.List" do
      {:ok, parsed} = Parser.parse(~S({$items :localize:list style=nonexistent}))

      assert {:format_error, _reason} =
               Interpreter.format_list(parsed, %{"items" => ["a", "b"]}, locale: "en")
    end

    # Regression: the binary-fallthrough in `add_list_style/2` used to
    # call `String.to_atom/1` on the raw style name, which grew the
    # atom table per distinct attacker-supplied string before the
    # downstream `Localize.List` rejected the unknown style.
    test "unknown style name does not create an atom" do
      bogus = "ZZZ_list_style_#{System.unique_integer([:positive])}"
      {:ok, parsed} = Parser.parse(~S({$items :localize:list style=) <> bogus <> ~S(}))

      assert {:format_error, _reason} =
               Interpreter.format_list(parsed, %{"items" => ["a", "b"]}, locale: "en")

      assert nil == Localize.Utils.Helpers.existing_atom(bogus)
    end
  end
end
