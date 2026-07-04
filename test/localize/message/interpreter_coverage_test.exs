defmodule Localize.Message.InterpreterCoverageTest do
  use ExUnit.Case, async: true

  alias Localize.Message.Interpreter
  alias Localize.Message.Parser

  defp format(message, bindings, options) do
    {:ok, ast} = Parser.parse(message)
    Interpreter.format_list(ast, bindings, options)
  end

  defp format_structured(message, bindings, options) do
    {:ok, ast} = Parser.parse(message)
    Interpreter.format_structured(ast, bindings, options)
  end

  defp match_body(message) do
    {:ok, [{:complex, [], {:match, _, _} = match}]} = Parser.parse(message)
    match
  end

  defp quoted_pattern_body(message) do
    {:ok, [{:complex, [], {:quoted_pattern, _} = quoted}]} = Parser.parse(message)
    quoted
  end

  describe "format_list/3 AST shapes" do
    test "a bare single-element match list" do
      match = match_body(".match $count\n1 {{one}}\n* {{other}}")

      assert {:ok, ["one"], ["count"], []} =
               Interpreter.format_list([match], %{"count" => 1}, locale: :en)
    end

    test "a bare single-element quoted pattern list" do
      quoted = quoted_pattern_body("{{quoted}}")
      assert {:ok, ["quoted"], [], []} = Interpreter.format_list([quoted], %{}, [])
    end

    test "an unwrapped quoted pattern tuple" do
      quoted = quoted_pattern_body("{{quoted}}")
      assert {:ok, ["quoted"], [], []} = Interpreter.format_list(quoted, %{}, [])
    end

    test "an unwrapped match tuple" do
      match = match_body(".match $count\n1 {{one}}\n* {{other}}")

      assert {:ok, ["other"], ["count"], []} =
               Interpreter.format_list(match, %{"count" => 2}, locale: :en)
    end
  end

  describe "format_structured/3 AST shapes" do
    test "keyword list bindings with a bare match list" do
      match = match_body(".match $count\n1 {{one}}\n* {{other}}")

      assert {:ok, [text: "one"], ["count"], []} =
               Interpreter.format_structured([match], [count: 1], locale: :en)
    end

    test "a bare single-element quoted pattern list" do
      quoted = quoted_pattern_body("{{quoted}}")
      assert {:ok, [text: "quoted"], [], []} = Interpreter.format_structured([quoted], %{}, [])
    end

    test "an unwrapped quoted pattern tuple" do
      quoted = quoted_pattern_body("{{quoted}}")
      assert {:ok, [text: "quoted"], [], []} = Interpreter.format_structured(quoted, %{}, [])
    end

    test "an unwrapped match tuple" do
      match = match_body(".match $count\n1 {{one}}\n* {{other}}")

      assert {:ok, [text: "other"], ["count"], []} =
               Interpreter.format_structured(match, %{"count" => 5}, locale: :en)
    end

    test "a complex message with a quoted pattern body" do
      assert {:ok, [text: "x is 42"], ["x"], []} =
               format_structured(".local $x = {42 :number}\n{{x is {$x}}}", %{}, locale: :en)
    end

    test "a complex message with a match body" do
      message = ".input {$n :number}\n.match $n\n1 {{one}}\n* {{many {$n}}}"

      assert {:ok, [text: "many 7"], ["n"], []} =
               format_structured(message, %{"n" => 7}, locale: :en)
    end

    test "an unbound input declaration reports the variable" do
      message = ".input {$n :number}\n.match $n\n1 {{one}}\n* {{many {$n}}}"

      assert {:error, [text: "many "], [], ["n"]} =
               format_structured(message, %{}, locale: :en)
    end

    test "an unbound local declaration reports the variable" do
      assert {:error, [text: "v "], [], ["x"]} =
               format_structured(".local $x = {$missing :number}\n{{v {$x}}}", %{}, locale: :en)
    end

    test "a declaration formatter error is surfaced" do
      assert {:format_error, {:formatter_failed, reason}} =
               format_structured(".local $x = {42 :offset}\n{{v {$x}}}", %{}, locale: :en)

      assert reason =~ "add"
    end

    test "an unbound variable inside a matched variant" do
      message = ".input {$n :number}\n.match $n\n1 {{one {$missing}}}\n* {{other {$missing}}}"

      assert {:error, [text: "one "], ["n"], ["missing"]} =
               format_structured(message, %{"n" => 1}, locale: :en)
    end

    test "no matching variant is an error" do
      message = ".input {$n :number}\n.match $n\n1 {{one}}\n2 {{two}}"

      assert {:error, [], ["n"], ["no matching variant"]} =
               format_structured(message, %{"n" => 9}, locale: :en)
    end

    test "escaped characters become text" do
      assert {:ok, [text: "a {b"], [], []} = format_structured("a \\{b", %{}, [])
    end

    test "a mismatched markup close is a format error" do
      assert {:format_error, {:unbalanced_markup, {:mismatched_close, "b"}}} =
               format_structured("a {/b}", %{}, [])
    end
  end

  describe "format_list/3 error paths" do
    test "an unbound input declaration reports the variable" do
      message = ".input {$n :number}\n.match $n\n1 {{one}}\n* {{many {$n}}}"
      assert {:error, ["many "], [], ["n"]} = format(message, %{}, locale: :en)
    end

    test "an unbound variable inside a matched variant" do
      message = ".input {$n :number}\n.match $n\n1 {{one {$missing}}}\n* {{other {$missing}}}"

      assert {:error, ["one "], ["n"], ["missing"]} =
               format(message, %{"n" => 1}, locale: :en)
    end

    test "a declaration formatter error is surfaced" do
      assert {:format_error, {:formatter_failed, reason}} =
               format(".local $x = {42 :offset}\n{{v {$x}}}", %{}, locale: :en)

      assert reason =~ "add"
    end

    test "no matching variant is an error" do
      message = ".input {$n :number}\n.match $n\n1 {{one}}\n2 {{two}}"

      assert {:error, [], ["n"], ["no matching variant"]} =
               format(message, %{"n" => 9}, locale: :en)
    end
  end

  describe ":time and :date styles" do
    test "time style short" do
      assert {:ok, ["10:30 AM"], ["t"], []} =
               format("{$t :time style=short}", %{"t" => ~T[10:30:00]}, locale: :en)
    end

    test "time style medium" do
      assert {:ok, ["10:30:00 AM"], ["t"], []} =
               format("{$t :time style=medium}", %{"t" => ~T[10:30:00]}, locale: :en)
    end

    test "time style full formats a DateTime through the time function" do
      assert {:ok, ["10:30:00 AM Greenwich Mean Time"], ["t"], []} =
               format("{$t :time style=full}", %{"t" => ~U[2024-01-01 10:30:00Z]}, locale: :en)
    end

    test "time style minute maps to short" do
      assert {:ok, ["10:30 AM"], ["t"], []} =
               format("{$t :time style=minute}", %{"t" => ~T[10:30:00]}, locale: :en)
    end

    test "date style medium" do
      assert {:ok, ["Jun 1, 2024"], ["d"], []} =
               format("{$d :date style=medium}", %{"d" => ~D[2024-06-01]}, locale: :en)
    end

    test "date style full" do
      assert {:ok, ["Saturday, June 1, 2024"], ["d"], []} =
               format("{$d :date style=full}", %{"d" => ~D[2024-06-01]}, locale: :en)
    end

    test "a DateTime is converted to a date for the date function" do
      assert {:ok, ["Jun 1, 2024"], ["d"], []} =
               format("{$d :date}", %{"d" => ~U[2024-06-01 08:00:00Z]}, locale: :en)
    end

    test "an ISO datetime string with offset is parsed for the date function" do
      assert {:ok, ["6/1/24"], ["d"], []} =
               format("{$d :date style=short}", %{"d" => "2024-06-01T08:00:00Z"}, locale: :en)
    end

    test "an ISO datetime string with offset is parsed for the datetime function" do
      assert {:ok, ["Jun 1, 2024, 8:00:00 AM"], ["t"], []} =
               format("{$t :datetime}", %{"t" => "2024-06-01T08:00:00Z"}, locale: :en)
    end
  end

  describe ":list styles" do
    test "and-short" do
      assert {:ok, ["a, b, & c"], ["l"], []} =
               format("{$l :list style=and-short}", %{"l" => ["a", "b", "c"]}, locale: :en)
    end

    test "and-narrow" do
      assert {:ok, ["a, b, c"], ["l"], []} =
               format("{$l :list style=and-narrow}", %{"l" => ["a", "b", "c"]}, locale: :en)
    end

    test "unit" do
      assert {:ok, ["a, b, c"], ["l"], []} =
               format("{$l :list style=unit}", %{"l" => ["a", "b", "c"]}, locale: :en)
    end

    test "unit-short" do
      assert {:ok, ["a, b, c"], ["l"], []} =
               format("{$l :list style=unit-short}", %{"l" => ["a", "b", "c"]}, locale: :en)
    end
  end

  describe "number operand coercion" do
    test "a Decimal operand formats" do
      assert {:ok, ["1.5"], ["n"], []} =
               format("{$n :number}", %{"n" => Decimal.new("1.5")}, locale: :en)
    end

    test "a negative Decimal operand selects the negative pattern" do
      assert {:ok, ["-1.5"], ["n"], []} =
               format("{$n :number}", %{"n" => Decimal.new("-1.5")}, locale: :en)
    end

    test "the offset function adds to a Decimal operand" do
      assert {:ok, ["5"], ["n"], []} =
               format("{$n :offset add=3}", %{"n" => Decimal.new(2)}, locale: :en)
    end
  end

  describe "option value coercion" do
    test "currency code given as an atom through a variable" do
      assert {:ok, ["$2.00"], ["n"], []} =
               format("{$n :currency currency=$c}", %{"n" => 2, "c" => :USD}, locale: :en)
    end

    test "minimumFractionDigits as a float is rounded" do
      assert {:ok, ["1.00"], ["n"], []} =
               format("{$n :number minimumFractionDigits=$f}", %{"n" => 1, "f" => 2.0},
                 locale: :en
               )
    end

    test "minimumFractionDigits with an unparseable literal is ignored" do
      assert {:ok, ["1"], ["n"], []} =
               format("{$n :number minimumFractionDigits=abc}", %{"n" => 1}, locale: :en)
    end

    test "minimumFractionDigits with a non-numeric variable value is ignored" do
      assert {:ok, ["1"], ["n"], []} =
               format("{$n :number minimumFractionDigits=$f}", %{"n" => 1, "f" => :two},
                 locale: :en
               )
    end

    test "numberingSystem not carried by the locale still transliterates digits" do
      assert {:ok, ["๑๒๓"], ["n"], []} =
               format("{$n :number numberingSystem=thai}", %{"n" => 123}, locale: :en)
    end
  end

  describe "selector value coercion" do
    test "a numeric string selects through the integer function" do
      message = ".input {$n :integer}\n.match $n\n1 {{one}}\n* {{other}}"
      assert {:ok, ["one"], ["n"], []} = format(message, %{"n" => "1.2"}, locale: :en)
    end

    test "a numeric string resolves a plural category" do
      message = ".input {$n :number}\n.match $n\none {{one!}}\n* {{other!}}"
      assert {:ok, ["one!"], ["n"], []} = format(message, %{"n" => "1"}, locale: :en)
    end

    test "a non-numeric string operand is a formatter error" do
      message = ".input {$n :integer}\n.match $n\nabc {{alpha}}\n* {{fallthru}}"

      assert {:format_error, {:formatter_failed, reason}} =
               format(message, %{"n" => "abc"}, locale: :en)

      assert reason =~ "cannot parse"
    end

    test "a float-only numeric string parses through the float branch" do
      message = ".input {$n :integer}\n.match $n\n0 {{zero}}\n* {{other}}"

      assert {:format_error, {:formatter_failed, reason}} =
               format(message, %{"n" => ".5"}, locale: :en)

      assert reason =~ "cannot parse"
    end
  end

  describe "bidi isolation" do
    test "an explicit u:dir=rtl attribute wraps in RLI" do
      assert {:ok, [["\u2067", "abc", "\u2069"]], ["x"], []} =
               format("{$x :string @u:dir=rtl}", %{"x" => "abc"}, locale: :en, bidi: :isolate)
    end

    test "u:dir=auto wraps in FSI" do
      assert {:ok, [["\u2068", "abc", "\u2069"]], ["x"], []} =
               format("{$x :string @u:dir=auto}", %{"x" => "abc"}, locale: :en, bidi: :isolate)
    end

    test "an unknown u:dir value falls back to FSI" do
      assert {:ok, [["\u2068", "abc", "\u2069"]], ["x"], []} =
               format("{$x :string @u:dir=updown}", %{"x" => "abc"}, locale: :en, bidi: :isolate)
    end
  end
end
