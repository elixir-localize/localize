defmodule Localize.Message.ApiTest do
  use ExUnit.Case, async: true

  alias Localize.Message

  describe "format/3 options" do
    test ":locale option changes number formatting" do
      message = "{{You have {$n :number}}}"

      assert Message.format(message, %{"n" => 1234.5}, locale: "en") ==
               {:ok, "You have 1,234.5"}

      assert Message.format(message, %{"n" => 1234.5}, locale: "de") ==
               {:ok, "You have 1.234,5"}
    end

    test "trim: true strips surrounding whitespace before parsing" do
      assert Message.format("  {{Hi}}  ", %{}, trim: true) == {:ok, "Hi"}
    end

    test "returns a ParseError for an invalid message" do
      assert {:error, %Localize.ParseError{line: 1, column: 5}} =
               Message.format("bad {", %{})
    end

    test "markup is stripped from plain formatted output" do
      assert Message.format("Click {#b}here{/b} now {#br/}", %{}) ==
               {:ok, "Click here now "}
    end
  end

  describe "format/3 with backend: :nif (falls back to :elixir when unavailable)" do
    # These assertions hold whether the NIF is present (ICU formats)
    # or not (Localize.Backend.resolve/1 falls back to the Elixir
    # interpreter). NIF-specific behaviour is covered in
    # message_nif_backend_test.exs.

    test "formats a simple message" do
      assert Message.format("{{Hello {$name}!}}", %{"name" => "World"}, backend: :nif) ==
               {:ok, "Hello World!"}
    end

    test "missing bindings return a BindError" do
      assert {:error, %Localize.BindError{unbound: ["name"]}} =
               Message.format("{{Hello {$name}!}}", %{}, backend: :nif)
    end

    test "local declarations are not reported as unbound" do
      assert Message.format(".local $x = {1 :number} {{{$x}}}", %{}, backend: :nif) ==
               {:ok, "1"}
    end

    test ".input declarations format correctly" do
      assert Message.format(".input {$c :number} {{{$c}}}", %{"c" => 3}, backend: :nif) ==
               {:ok, "3"}
    end

    test "keyword-list bindings are normalized" do
      assert Message.format("{{Hi {$a}}}", [a: 1], backend: :nif) == {:ok, "Hi 1"}
    end

    test ":locale option applies to number formatting" do
      assert Message.format(
               "{{You have {$n :number}}}",
               %{"n" => 1234.5},
               backend: :nif,
               locale: "de"
             ) == {:ok, "You have 1.234,5"}
    end

    test "markup messages format with markup stripped" do
      assert Message.format("{#b}bold{/b}", %{}, backend: :nif) == {:ok, "bold"}
    end

    test "atom-key map bindings and literal function options" do
      assert Message.format(
               "{{Hi {$a} {$b :number style=decimal}}}",
               %{a: 1, b: 2},
               backend: :nif
             ) == {:ok, "Hi 1 2"}
    end
  end

  describe "format_to_iolist/3" do
    test "returns a ParseError tuple for an invalid message" do
      assert {:error, %Localize.ParseError{}} = Message.format_to_iolist("bad {", %{})
    end

    test "markup renders as empty strings in the iolist" do
      assert {:ok, iolist, [], []} = Message.format_to_iolist("Hello {#b}bold{/b}", %{})
      assert :erlang.iolist_to_binary(iolist) == "Hello bold"
    end
  end

  describe "canonical_message/2 and canonical_message!/2" do
    test "trims by default and normalizes declaration spacing" do
      assert Message.canonical_message("  .input {$c :number}   {{ {$c} }}  ") ==
               {:ok, ".input {$c :number}\n{{ {$c} }}"}
    end

    test "pretty: false produces the compact canonical form" do
      assert Message.canonical_message(".input {$c :number} {{{$c}}}", pretty: false) ==
               {:ok, ".input {$c :number}\n{{{$c}}}"}
    end
  end

  describe "jaro_distance/3 and jaro_distance!/3" do
    test "returns a ParseError when the first message is invalid" do
      assert {:error, %Localize.ParseError{input: "bad {"}} =
               Message.jaro_distance("bad {", "{{Hello}}")
    end

    test "returns a ParseError when the second message is invalid" do
      assert {:error, %Localize.ParseError{input: "bad {"}} =
               Message.jaro_distance("{{Hello}}", "bad {")
    end

    test "trim: true compares the trimmed canonical forms" do
      assert Message.jaro_distance("  {{Hello}}  ", "{{Hello}}", trim: true) == {:ok, 1.0}
    end

    test "jaro_distance!/3 raises on a parse error" do
      assert_raise Localize.ParseError, fn ->
        Message.jaro_distance!("bad {", "{{Hello}}")
      end
    end
  end

  describe "format_to_safe_list/3 parse errors" do
    test "returns a ParseError for an invalid message" do
      assert {:error, %Localize.ParseError{}} = Message.format_to_safe_list("bad {")
    end
  end

  describe "default_options/0" do
    test "defaults to trim: false" do
      assert Message.default_options() == [trim: false]
    end
  end

  describe "to_tokens/2" do
    test "trims by default" do
      assert Message.to_tokens("  Hello  ") == {:ok, [text: "Hello"]}
    end

    test "trim: false preserves surrounding whitespace" do
      assert Message.to_tokens("  Hello  ", trim: false) == {:ok, [text: "  Hello  "]}
    end

    test "returns a ParseError for an invalid message" do
      assert {:error, %Localize.ParseError{}} = Message.to_tokens("bad {")
    end
  end

  describe "to_html/2" do
    test "standalone: true wraps output in pre/code with the wrapper class" do
      assert {:ok, html} = Message.to_html("Hello {$name}!", standalone: true)
      assert String.starts_with?(html, ~s(<pre class="mf2-highlight"><code>))
      assert String.ends_with?(html, "</code></pre>")
    end

    test ":class_prefix changes the per-token CSS class prefix" do
      assert {:ok, html} = Message.to_html("Hello {$name}!", class_prefix: "x-")
      assert html =~ ~s(<span class="x-variable">$name</span>)
      refute html =~ "mf2-"
    end

    test "returns a ParseError for an invalid message" do
      assert {:error, %Localize.ParseError{}} = Message.to_html("bad {")
    end
  end

  describe "to_ansi/2" do
    test ":palette overrides classes and an empty colour list leaves text bare" do
      assert {:ok, ansi} =
               Message.to_ansi("Hello {$name}!", palette: %{variable: [:red], text: []})

      assert ansi =~ IO.ANSI.red() <> "$name"
      assert String.starts_with?(ansi, "Hello ")
    end

    test "returns a ParseError for an invalid message" do
      assert {:error, %Localize.ParseError{}} = Message.to_ansi("bad {")
    end
  end
end
