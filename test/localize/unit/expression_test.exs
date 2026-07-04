defmodule Localize.Unit.Data.ExpressionTest do
  use ExUnit.Case, async: true

  alias Localize.Unit.Data.Expression

  describe "parse_number/1" do
    test "parses an integer as a float" do
      assert Expression.parse_number("5") == 5.0
    end

    test "parses a float" do
      assert Expression.parse_number("3.14") == 3.14
    end

    test "parses a fraction" do
      assert_in_delta Expression.parse_number("1/3"), 0.3333333333, 1.0e-9
    end

    test "parses a fraction with embedded spaces" do
      assert Expression.parse_number("1 / 4") == 0.25
    end

    test "parses scientific notation" do
      assert Expression.parse_number("6.02214076E+23") == 6.022_140_76e23
    end
  end

  describe "evaluate_expression/2" do
    test "evaluates a product of literals" do
      assert Expression.evaluate_expression("2*3*4", %{}) == 24.0
    end

    test "evaluates a quotient" do
      assert Expression.evaluate_expression("12/4", %{}) == 3.0
    end

    test "resolves constants from the constant map" do
      assert_in_delta Expression.evaluate_expression("ft_to_m*3", %{"ft_to_m" => 0.3048}),
                      0.9144,
                      1.0e-9
    end

    test "everything after the slash multiplies into the denominator" do
      constants = %{"a" => 12.0, "b" => 2.0, "c" => 3.0, "d" => 4.0}
      assert Expression.evaluate_expression("a*b/c*d", constants) == 2.0
    end

    test "a bare constant evaluates to its value" do
      assert Expression.evaluate_expression("gravity", %{"gravity" => 9.80665}) == 9.80665
    end

    test "ignores embedded spaces" do
      assert Expression.evaluate_expression("2 * 3", %{}) == 6.0
    end
  end

  describe "resolve_all/2" do
    test "resolves constants that depend on other constants" do
      assert Expression.resolve_all(%{"a" => "2*3", "b" => "a*2"}, %{}) ==
               %{"a" => 6.0, "b" => 12.0}
    end

    test "leaves unresolvable constants out of the result" do
      assert Expression.resolve_all(%{"a" => "2", "b" => "missing*2"}, %{}) == %{"a" => 2.0}
    end

    test "returns the resolved map unchanged when already complete" do
      assert Expression.resolve_all(%{"a" => "2"}, %{"a" => 2.0}) == %{"a" => 2.0}
    end

    test "resolves a multi-level dependency chain" do
      raw = %{"a" => "2", "b" => "a*3", "c" => "b*a"}
      assert Expression.resolve_all(raw, %{}) == %{"a" => 2.0, "b" => 6.0, "c" => 12.0}
    end
  end
end
