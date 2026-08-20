defmodule Localize.OptionalDependencyTest do
  @moduledoc """
  `Localize.Date.parse/2` and its siblings delegate to `calendrical`, which
  depends on Localize in turn — so Localize cannot depend on it back, and
  resolves it at runtime instead. Localize's own test run has no `calendrical`
  in it, so these cover the absent path. The present path is exercised from a
  package that has both; see `Localize.Date.parse/2`'s documentation.

  """

  use ExUnit.Case, async: true

  describe "parse/2 without the calendrical package" do
    test "returns a typed error naming the package rather than raising" do
      for {module, operation} <- [
            {Localize.Date, "Localize.Date.parse/2"},
            {Localize.Time, "Localize.Time.parse/2"},
            {Localize.DateTime, "Localize.DateTime.parse/2"}
          ] do
        assert {:error, %Localize.DependencyRequiredError{} = exception} =
                 module.parse("22.03.2026", locale: :de)

        assert exception.package == "calendrical"
        assert exception.operation == operation
      end
    end

    test "the message tells the caller what to add" do
      {:error, exception} = Localize.Date.parse("22.03.2026")
      message = Exception.message(exception)

      assert message =~ "calendrical"
      assert message =~ "Localize.Date.parse/2"
      assert message =~ "dependencies"
    end
  end

  describe "the runtime resolution itself" do
    test "calls through when the module and function are present" do
      # `String.upcase/1` stands in for a sibling package that is installed.
      assert Localize.OptionalDependency.call("String", :upcase, ["abc"],
               package: "nope",
               operation: "test"
             ) == "ABC"
    end

    test "reports the package when the module is absent" do
      assert {:error, %Localize.DependencyRequiredError{package: "ghost"}} =
               Localize.OptionalDependency.call("No.Such.Module", :parse, ["x"],
                 package: "ghost",
                 operation: "test"
               )
    end

    test "reports the package when the module exists but the function does not" do
      assert {:error, %Localize.DependencyRequiredError{}} =
               Localize.OptionalDependency.call("String", :no_such_function, ["x"],
                 package: "ghost",
                 operation: "test"
               )
    end
  end

  describe "parse/format symmetry" do
    test "every module that formats a value can also parse one" do
      for module <- [
            Localize.Number,
            Localize.Date,
            Localize.Time,
            Localize.DateTime,
            Localize.Unit
          ] do
        functions = module.__info__(:functions)

        assert Enum.any?(functions, &(elem(&1, 0) == :to_string)),
               "#{inspect(module)} does not format"

        assert Enum.any?(functions, &(elem(&1, 0) == :parse)),
               "#{inspect(module)} formats but cannot parse — the rule a caller " <>
                 "forms from Localize.Number.parse/2 must hold across the family"
      end
    end
  end
end
