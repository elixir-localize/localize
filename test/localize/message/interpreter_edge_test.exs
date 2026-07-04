defmodule Localize.Message.InterpreterEdgeTest do
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

  describe ":offset function" do
    test "adds a non-negative integer" do
      assert {:ok, ["45"], [], []} = format("{42 :offset add=3}", %{}, locale: :en)
    end

    test "subtracts a non-negative integer" do
      assert {:ok, ["40"], [], []} = format("{42 :offset subtract=2}", %{}, locale: :en)
    end

    test "applies to a numeric string operand" do
      assert {:ok, ["9"], ["n"], []} =
               format("{$n :offset subtract=1}", %{"n" => "10"}, locale: :en)
    end

    test "errors when neither add nor subtract is given" do
      assert {:format_error, {:formatter_failed, reason}} =
               format("{42 :offset}", %{}, locale: :en)

      assert reason =~ "requires one of the `add` or `subtract` options"
    end

    test "errors when both add and subtract are given" do
      assert {:format_error, {:formatter_failed, reason}} =
               format("{42 :offset add=3 subtract=2}", %{}, locale: :en)

      assert reason =~ "exactly one of `add` or `subtract`"
      assert reason =~ "add=3 subtract=2"
    end

    test "errors for a negative adjustment" do
      assert {:format_error, {:formatter_failed, reason}} =
               format("{42 :offset add=-3}", %{}, locale: :en)

      assert reason =~ "non-negative integer"
    end

    test "errors for a non-integer adjustment" do
      assert {:format_error, {:formatter_failed, reason}} =
               format("{42 :offset add=1.5}", %{}, locale: :en)

      assert reason =~ "non-negative integer"
    end

    test "applies the offset before selection" do
      message = ".input {$n :offset add=2}\n.match $n\n5 {{five}}\n* {{other {$n}}}"

      assert {:ok, ["five"], _bound, []} = format(message, %{"n" => 3}, locale: :en)
    end
  end

  describe ":percent selection" do
    test "matches keys against the value scaled by 100" do
      message =
        ".input {$count :percent}\n.match $count\n1 {{full}}\n0.5 {{half}}\n* {{other: {$count}}}"

      # count=0.005 scales to 0.5, matching the 0.5 key.
      assert {:ok, ["half"], _bound, []} = format(message, %{"count" => 0.005}, locale: :en)

      # count=0.5 scales to 50, matching no explicit key.
      assert {:ok, ["other: ", "50%"], _bound, []} =
               format(message, %{"count" => 0.5}, locale: :en)

      # count=1 scales to 100, matching no explicit key.
      assert {:ok, ["other: ", "100%"], _bound, []} =
               format(message, %{"count" => 1}, locale: :en)
    end

    test "an exactly-integral scaled value selects as an integer" do
      message = ".input {$count :percent}\n.match $count\n25 {{quarter}}\n* {{other}}"

      assert {:ok, ["quarter"], _bound, []} = format(message, %{"count" => 0.25}, locale: :en)
    end
  end

  describe "selector resolution" do
    test "an unbound .match variable falls back and reports the variable" do
      assert {:error, ["fallback"], [], ["missing"]} =
               format(".match $missing\n* {{fallback}}", %{}, locale: :en)
    end

    test "Message.format surfaces unbound .match variables as a BindError" do
      assert {:error, %Localize.BindError{unbound: ["missing"]}} =
               Localize.Message.format(".match $missing\n* {{fallback}}", %{}, backend: :elixir)
    end

    test "no matching variant and no catchall reports an error" do
      message = ".match $n\n1 {{one}}\n2 {{two}}"

      assert {:error, [], ["n"], ["no matching variant"]} = format(message, %{"n" => 5}, [])
    end

    test "integer selection truncates fractional operands" do
      message = ".input {$n :integer}\n.match $n\n2 {{two}}\n* {{other}}"

      assert {:ok, ["two"], _bound, []} = format(message, %{"n" => 2.7}, locale: :en)
      assert {:ok, ["two"], _bound, []} = format(message, %{"n" => "2"}, locale: :en)
    end

    test "select=exact disables plural category matching" do
      message = ".input {$n :number select=exact}\n.match $n\none {{one-category}}\n* {{other}}"

      assert {:ok, ["other"], _bound, []} = format(message, %{"n" => 1}, locale: :en)
    end

    test "select=ordinal matches ordinal plural categories" do
      message = ".input {$n :number select=ordinal}\n.match $n\nfew {{fewth}}\n* {{other}}"

      assert {:ok, ["fewth"], _bound, []} = format(message, %{"n" => 3}, locale: :en)
    end

    test "match results deduplicate bound variables like format_pattern does" do
      # Regression: evaluate_match returned the same variable once per
      # use (e.g. ["count", "count", "count"]) while simple patterns
      # deduplicated with Enum.uniq.
      message =
        ".input {$count :number}\n.match $count\none {{{$count} item}}\n* {{{$count} items}}"

      assert {:ok, ["3", " items"], ["count"], []} =
               format(message, %{"count" => 3}, locale: :en)

      assert {:ok, [text: "3 items"], ["count"], []} =
               format_structured(message, %{"count" => 3}, locale: :en)
    end
  end

  describe "declarations" do
    test ".local declarations chain through earlier declarations" do
      message = ".local $a = {1 :number} .local $b = {$a :number}\n{{{$b}}}"

      assert {:ok, ["1"], bound, []} = format(message, %{}, locale: :en)
      assert "a" in bound
      assert "b" in bound
    end

    test ".local referencing an unbound variable leaves the local unbound" do
      message = ".local $x = {$y :number}\n{{value {$x}}}"

      assert {:error, ["value "], [], ["x"]} = format(message, %{}, locale: :en)
    end

    test "a failing .input declaration halts with a format error" do
      message = ".input {$n :number}\n{{value {$n}}}"

      assert {:format_error, {:formatter_failed, reason}} =
               format(message, %{"n" => "not-a-number"}, locale: :en)

      assert reason =~ "cannot parse"
    end
  end

  describe "function option resolution" do
    test "resolves options from variables" do
      assert {:ok, ["3.00"], ["n"], []} =
               format(
                 "{$n :number minimumFractionDigits=$digits}",
                 %{"n" => 3, "digits" => 2},
                 locale: :en
               )
    end

    test "an unbound variable option is an unresolved-variable error" do
      # Per the MF2 spec ("Unresolved Variable" resolution error), an
      # option value referencing an unbound variable is reported, not
      # silently dropped.
      assert {:error, [], [], ["missing"]} =
               format("{$n :number minimumFractionDigits=$missing}", %{"n" => 3}, locale: :en)
    end

    test "useGrouping=never suppresses grouping" do
      assert {:ok, ["12345"], ["n"], []} =
               format("{$n :number useGrouping=never}", %{"n" => 12_345}, locale: :en)
    end

    test "useGrouping=min2 requires at least two leading digits" do
      assert {:ok, ["1234"], ["n"], []} =
               format("{$n :number useGrouping=min2}", %{"n" => 1234}, locale: :en)

      assert {:ok, ["12,345"], ["n"], []} =
               format("{$n :number useGrouping=min2}", %{"n" => 12_345}, locale: :en)
    end

    test "an unknown numbering system is a format error" do
      assert {:format_error, {:formatter_failed, reason}} =
               format("{$n :number numberingSystem=zzzz}", %{"n" => 3}, locale: :en)

      assert reason =~ "unknown numbering system"
    end

    test "a currency function without a currency option is a format error" do
      assert {:format_error, {:formatter_failed, reason}} =
               format("{$amount :currency}", %{"amount" => 3}, locale: :en)

      assert reason =~ "currency option is required"
    end
  end

  describe ":list function options" do
    test "maps the style option onto CLDR list styles" do
      assert {:ok, ["a b c"], ["items"], []} =
               format("{$items :list style=unit-narrow}", %{"items" => ["a", "b", "c"]},
                 locale: :en
               )
    end

    test "accepts type as an alias for style" do
      assert {:ok, ["a, b, or c"], ["items"], []} =
               format("{$items :list type=or-short}", %{"items" => ["a", "b", "c"]}, locale: :en)
    end

    test "rejects unknown style names" do
      assert {:format_error, {:formatter_failed, %Localize.InvalidValueError{}}} =
               format("{$items :list style=bogus}", %{"items" => ["a", "b"]}, locale: :en)
    end

    test "rejects a non-list operand" do
      assert {:format_error, {:formatter_failed, reason}} =
               format("{$items :list}", %{"items" => "not-a-list"}, locale: :en)

      assert reason =~ "requires a list operand"
    end
  end

  describe "unknown functions" do
    test "fall back to string conversion when no custom function is registered" do
      assert {:ok, ["7"], ["n"], []} = format("{$n :no_such_function}", %{"n" => 7}, [])
    end
  end

  describe "fallback rendering with unbound variables" do
    test "returns a partial iolist with bound and unbound names" do
      assert {:error, [" "], [], unbound} = format("{$one :string} {$two}", %{}, [])
      assert Enum.sort(unbound) == ["one", "two"]
    end

    test "bound variables are unique even when referenced twice" do
      assert {:ok, ["x", " is ", "x"], ["name"], []} =
               format("{$name} is {$name}", %{"name" => "x"}, [])
    end
  end

  describe "markup in flat formatting" do
    test "markup tags render as empty strings" do
      assert {:ok, ["hello ", "", "world", "", " end"], [], []} =
               format("hello {#b}world{/b} end", %{}, [])
    end
  end

  describe "markup in structured formatting" do
    test "nests children under the markup node" do
      assert {:ok, [{:text, "hello "}, {:markup, "b", %{"class" => "big"}, [text: "world"]}],
              ["c"], []} =
               format_structured("hello {#b class=$c}world{/b}", %{"c" => "big"}, [])
    end

    test "renders standalone markup with literal options" do
      assert {:ok, [{:text, "a "}, {:markup, "img", %{"src" => "x.png"}, []}, {:text, " b"}], [],
              []} =
               format_structured("a {#img src=|x.png|/} b", %{}, [])
    end

    test "resolves numeric literal markup options" do
      assert {:ok, [{:markup, "b", %{"opt" => 42}, [text: "x"]}], [], []} =
               format_structured("{#b opt=42}x{/b}", %{}, [])
    end

    test "drops markup options bound to unresolvable variables" do
      assert {:ok, [{:markup, "b", %{}, [text: "x"]}], [], []} =
               format_structured("{#b opt=$missing}x{/b}", %{}, [])
    end

    test "unclosed markup is a format error" do
      assert {:format_error, {:unbalanced_markup, :unclosed}} =
               format_structured("hello {#b}world", %{}, [])
    end

    test "a mismatched close is a format error naming the tag" do
      assert {:format_error, {:unbalanced_markup, {:mismatched_close, "i"}}} =
               format_structured("hello {#b}world{/i}", %{}, [])
    end

    test "matches through declarations and selectors" do
      message = ".local $x = {$n :number}\n.match $x\n1 {{one x}}\n* {{many x}}"

      assert {:ok, [text: "one x"], ["x"], []} =
               format_structured(message, %{"n" => 1}, locale: :en)
    end

    test "an unbound selector produces the fallback variant and an error" do
      assert {:error, [text: "fb"], [], ["missing"]} =
               format_structured(".match $missing\n* {{fb}}", %{}, [])
    end
  end

  describe "bidi isolation" do
    @fsi "\u2068"
    @lri "\u2066"
    @rli "\u2067"
    @pdi "\u2069"

    test "mode :none leaves values unwrapped" do
      assert {:ok, ["x"], ["name"], []} = format("{$name}", %{"name" => "x"}, bidi: :none)
      assert {:ok, ["x"], ["name"], []} = format("{$name}", %{"name" => "x"}, [])
    end

    test "mode :isolate wraps values in FSI/PDI" do
      assert {:ok, [[@fsi, "x", @pdi]], ["name"], []} =
               format("{$name}", %{"name" => "x"}, bidi: :isolate)
    end

    test "mode :auto wraps only when the locale is right-to-left" do
      assert {:ok, [[@fsi, "x", @pdi]], ["name"], []} =
               format("{$name}", %{"name" => "x"}, bidi: :auto, locale: :ar)

      assert {:ok, ["x"], ["name"], []} =
               format("{$name}", %{"name" => "x"}, bidi: :auto, locale: :en)

      assert {:ok, ["x"], ["name"], []} =
               format("{$name}", %{"name" => "x"}, bidi: :auto)
    end

    test "a u:dir attribute forces isolation even in mode :none" do
      assert {:ok, [[@rli, "x", @pdi]], ["name"], []} =
               format("{$name @u:dir=rtl}", %{"name" => "x"}, [])

      assert {:ok, [[@fsi, "x", @pdi]], ["name"], []} =
               format("{$name @u:dir=auto}", %{"name" => "x"}, [])
    end

    test "a u:dir attribute overrides the bidi mode" do
      assert {:ok, [[@lri, "x", @pdi]], ["name"], []} =
               format("{$name @u:dir=ltr}", %{"name" => "x"}, bidi: :isolate)
    end
  end

  describe "operands and escapes" do
    test "formats literal and negative-number operands" do
      assert {:ok, ["5.5"], [], []} = format("{|5.5| :number}", %{}, locale: :en)
      assert {:ok, ["-42"], [], []} = format("{-42 :number}", %{}, locale: :en)
    end

    test "renders escaped braces as text" do
      assert {:ok, ["hello ", "{", "world", "}"], [], []} =
               format("hello \\{world\\}", %{}, [])
    end
  end
end
