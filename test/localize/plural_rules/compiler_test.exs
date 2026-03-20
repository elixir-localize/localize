defmodule Localize.Number.PluralRule.CompilerTest do
  use ExUnit.Case, async: true

  alias Localize.Number.PluralRule.Compiler

  test "tokenize and parse a plural rule definition" do
    plural_rule = "i = 0 or n = 1 @integer 0, 1 @decimal 0.0~1.0, 0.00~0.04"
    {:ok, tokens, _} = Compiler.tokenize(plural_rule)
    assert {:ok, _ast} = Compiler.parse(plural_rule)
    assert is_list(tokens)
  end

  test "parse a simple equality rule" do
    assert {:ok, _ast} = Compiler.parse("n = 1")
  end

  test "parse a range rule" do
    assert {:ok, _ast} = Compiler.parse("n = 1..5")
  end

  test "parse a rule with mod operator" do
    assert {:ok, _ast} = Compiler.parse("n % 10 = 1")
  end

  test "parse a compound rule with and/or" do
    assert {:ok, _ast} = Compiler.parse("i = 1 and v = 0")
    assert {:ok, _ast} = Compiler.parse("n = 0 or n = 1")
  end

  test "parse a rule with not-equal operator" do
    assert {:ok, _ast} = Compiler.parse("n != 0")
  end

  test "parse a rule using the within operator" do
    assert {:ok, _ast} = Compiler.parse("n = 1..5 or n within 10..20")
  end
end
