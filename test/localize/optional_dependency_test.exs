defmodule Localize.OptionalDependencyTest do
  @moduledoc """
  Parsing is implemented here, so `Localize.Date.parse/2` and its siblings
  need no other package. Two things they reach for do live elsewhere —
  calendar modules for non-Gregorian calendars, and time-zone resolution —
  and `calendrical` supplies both. It depends on Localize in turn, so
  Localize cannot depend on it back and resolves it at runtime instead.

  Localize's own test run has no `calendrical` in it, which is what makes
  these tests meaningful: they assert that its absence costs a caller
  nothing for the ordinary case, and degrades rather than fails for the
  rest.

  """

  use ExUnit.Case, async: true

  describe "parsing without the calendrical package" do
    test "dates, times and datetimes parse with nothing else installed" do
      refute Code.ensure_loaded?(Calendrical),
             "this test only means something while calendrical is absent"

      assert Localize.Date.parse("22.03.2026", locale: :de) == {:ok, ~D[2026-03-22]}
      assert Localize.Time.parse("3:45 PM", locale: :en) == {:ok, ~T[15:45:00]}

      assert Localize.DateTime.parse("March 22, 2026 3:45 PM", locale: :en) ==
               {:ok, ~N[2026-03-22 15:45:00]}
    end

    # A named zone carries no offset of its own, so resolving it needs a
    # TZ database Localize does not carry. Losing the zone is the
    # documented outcome — the parse is preserved rather than failed.
    test "a named-zone datetime degrades to a NaiveDateTime rather than failing" do
      assert {:ok, %NaiveDateTime{}} =
               Localize.DateTime.parse("March 22, 2026 3:45 PM Asia/Tokyo", locale: :en)
    end

    # A fixed offset is arithmetic, so it needs no dependency at all.
    test "a fixed-offset datetime resolves with no calendrical present" do
      assert {:ok, %DateTime{utc_offset: 37_800}} =
               Localize.DateTime.parse("March 22, 2026 3:45 PM GMT+10:30", locale: :en)

      assert {:ok, %DateTime{utc_offset: 0}} =
               Localize.DateTime.parse("March 22, 2026 3:45 PM UTC", locale: :en)
    end

    # A non-Gregorian calendar names a module that ships with calendrical.
    # Without it there is no Hebrew date to return, so the caller gets an
    # error naming the package to add rather than a silently Gregorian
    # result.
    test "a non-Gregorian calendar names the package it needs" do
      assert {:error, %Localize.DependencyRequiredError{package: "calendrical"}} =
               Localize.Date.parse("22.03.2026", locale: :de, calendar: :hebrew)
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
