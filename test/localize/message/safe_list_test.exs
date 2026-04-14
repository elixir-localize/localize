defmodule Localize.Message.SafeListTest do
  use ExUnit.Case, async: true

  alias Localize.Message

  describe "format_to_safe_list/3 — plain and interpolated text" do
    test "returns a single text node for a plain string" do
      assert {:ok, [{:text, "Just text"}]} = Message.format_to_safe_list("Just text")
    end

    test "interpolates variables into a single coalesced text node" do
      assert {:ok, [{:text, "Hello Kip!"}]} =
               Message.format_to_safe_list("Hello {$name}!", %{"name" => "Kip"})
    end

    test "returns a BindError when a variable is unbound" do
      assert {:error, %Localize.BindError{unbound: ["name"]}} =
               Message.format_to_safe_list("Hello {$name}!")
    end
  end

  describe "format_to_safe_list/3 — markup" do
    test "wraps text in a markup node with resolved options" do
      assert {:ok,
              [
                {:text, "Click "},
                {:markup, "link", %{"href" => "/home"}, [{:text, "here"}]},
                {:text, "!"}
              ]} =
               Message.format_to_safe_list("Click {#link href=|/home|}here{/link}!")
    end

    test "resolves markup options from variable bindings" do
      assert {:ok,
              [
                {:text, "Click "},
                {:markup, "link", %{"href" => "/dashboard"}, [{:text, "here"}]}
              ]} =
               Message.format_to_safe_list(
                 "Click {#link href=$url}here{/link}",
                 %{"url" => "/dashboard"}
               )
    end

    test "standalone markup with no children" do
      assert {:ok,
              [
                {:text, "Line 1"},
                {:markup, "br", %{}, []},
                {:text, "Line 2"}
              ]} = Message.format_to_safe_list("Line 1{#br/}Line 2")
    end

    test "mixes variable interpolation and markup" do
      assert {:ok,
              [
                {:text, "Hello Kip, click "},
                {:markup, "link", %{"href" => "/home"}, [{:text, "here"}]},
                {:text, "!"}
              ]} =
               Message.format_to_safe_list(
                 "Hello {$name}, click {#link href=|/home|}here{/link}!",
                 %{"name" => "Kip"}
               )
    end

    test "nests markup regions correctly" do
      assert {:ok,
              [
                {:markup, "outer", %{},
                 [
                   {:text, "before "},
                   {:markup, "inner", %{}, [{:text, "middle"}]},
                   {:text, " after"}
                 ]}
              ]} =
               Message.format_to_safe_list("{#outer}before {#inner}middle{/inner} after{/outer}")
    end
  end

  describe "format_to_safe_list/3 — error handling" do
    test "returns FormatError for an unclosed markup tag" do
      assert {:error, %Localize.FormatError{reason: reason}} =
               Message.format_to_safe_list("{#open}no close")

      assert reason =~ "unclosed"
    end

    test "returns FormatError for a close tag with no matching open" do
      assert {:error, %Localize.FormatError{reason: reason}} =
               Message.format_to_safe_list("no open{/close}")

      assert reason =~ "does not match"
    end

    test "returns FormatError for mismatched open and close names" do
      assert {:error, %Localize.FormatError{reason: reason}} =
               Message.format_to_safe_list("{#a}text{/b}")

      assert reason =~ "does not match"
    end
  end

  describe "format_to_safe_list/3 — plurals and complex messages" do
    test "plural selection combined with markup" do
      message =
        ".input {$count :number}\n.match $count\n1 {{You have {$count} {#bold}message{/bold}.}}\n* {{You have {$count} {#bold}messages{/bold}.}}"

      assert {:ok,
              [
                {:text, "You have 5 "},
                {:markup, "bold", %{}, [{:text, "messages"}]},
                {:text, "."}
              ]} = Message.format_to_safe_list(message, %{"count" => 5})

      assert {:ok,
              [
                {:text, "You have 1 "},
                {:markup, "bold", %{}, [{:text, "message"}]},
                {:text, "."}
              ]} = Message.format_to_safe_list(message, %{"count" => 1})
    end
  end

  describe "format_to_safe_list!/3" do
    test "returns nodes directly on success" do
      assert [{:text, "Hello"}] = Message.format_to_safe_list!("Hello")
    end

    test "raises on error" do
      assert_raise Localize.BindError, fn ->
        Message.format_to_safe_list!("Hello {$name}!")
      end
    end
  end
end
