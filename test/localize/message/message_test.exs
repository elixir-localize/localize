defmodule Localize.MessageTest do
  use ExUnit.Case

  doctest Localize.Message

  describe "format/3" do
    test "simple v2 text" do
      assert Localize.Message.format("{{Hello, world!}}") ==
               {:ok, "Hello, world!"}
    end

    test "v2 with variable" do
      assert Localize.Message.format("{{Hello {$name}!}}", %{"name" => "World"}) ==
               {:ok, "Hello World!"}
    end

    test "v2 with atom key bindings" do
      assert Localize.Message.format("{{Hello {$name}!}}", name: "World") ==
               {:ok, "Hello World!"}
    end

    test "v2 with unbound variable" do
      assert {:error, _} = Localize.Message.format("{{Hello {$name}!}}", %{})
    end

    test "simple message (no declarations)" do
      assert Localize.Message.format("Hello {$name}!", %{"name" => "World"}) ==
               {:ok, "Hello World!"}
    end

    test "empty message" do
      assert Localize.Message.format("") == {:ok, ""}
    end

    test "text with escapes" do
      expected = "Hello " <> "{" <> "world" <> "}"
      assert Localize.Message.format("Hello \\{world\\}") == {:ok, expected}
    end

    test "literal expression" do
      assert Localize.Message.format("{|hello|}") == {:ok, "hello"}
    end

    test "number literal expression" do
      assert Localize.Message.format("{42}") == {:ok, "42"}
    end

    test "local declaration" do
      msg = ".local $y = {$x :string}\n{{{$y} is the value}}"

      assert Localize.Message.format(msg, %{"x" => "hello"}) ==
               {:ok, "hello is the value"}
    end

    test "formatter_backend :elixir option" do
      assert Localize.Message.format("{{Hello!}}", %{}, formatter_backend: :elixir) ==
               {:ok, "Hello!"}
    end
  end

  describe "format!/3" do
    test "returns formatted string" do
      assert Localize.Message.format!("{{Hello {$name}!}}", %{"name" => "World"}) ==
               "Hello World!"
    end

    test "raises on error" do
      assert_raise Localize.BindError, fn ->
        Localize.Message.format!("{{Hello {$name}!}}", %{})
      end
    end
  end

  describe "format_to_iolist/3" do
    test "returns iolist with bound/unbound info" do
      assert {:ok, iolist, bound, []} =
               Localize.Message.format_to_iolist("{{Hello {$name}!}}", %{"name" => "World"})

      assert :erlang.iolist_to_binary(iolist) == "Hello World!"
      assert "name" in bound
    end

    test "reports unbound variables" do
      assert {:error, _iolist, _bound, unbound} =
               Localize.Message.format_to_iolist("{{Hello {$name}!}}", %{})

      assert "name" in unbound
    end
  end

  describe "canonical_message/2" do
    test "canonical v2 message" do
      assert {:ok, _} = Localize.Message.canonical_message("{{Hello {$name}!}}")
    end

    test "canonical preserves structure" do
      msg1 = ".input {$x :number}\n.match $x\n1 {{one}}\n* {{other}}"
      msg2 = ".input {$x :number}\n.match $x\n  1  {{one}}\n *   {{other}}"

      assert Localize.Message.canonical_message(msg1) ==
               Localize.Message.canonical_message(msg2)
    end

    test "returns error for invalid message" do
      assert {:error, _} = Localize.Message.canonical_message("{}")
    end
  end

  describe "canonical_message!/2" do
    test "returns canonical message" do
      assert is_binary(Localize.Message.canonical_message!("{{Hello!}}"))
    end

    test "raises on invalid message" do
      assert_raise Localize.ParseError, fn ->
        Localize.Message.canonical_message!("{}")
      end
    end
  end

  describe "jaro_distance/3" do
    test "identical messages have distance 1.0" do
      assert Localize.Message.jaro_distance("{{Hello}}", "{{Hello}}") == {:ok, 1.0}
    end

    test "jaro_distance! returns float" do
      assert Localize.Message.jaro_distance!("{{Hello}}", "{{Hello}}") == 1.0
    end

    test "similar messages have high distance" do
      assert {:ok, distance} =
               Localize.Message.jaro_distance("{{Hello {$name}!}}", "{{Hello {$user}!}}")

      assert distance > 0.8
    end
  end

  describe "number match selector" do
    test "match with :number selector" do
      msg = ".input {$count :number}\n.match $count\n1 {{one item}}\n* {{other items}}"

      assert Localize.Message.format(msg, %{"count" => 1}) == {:ok, "one item"}
      assert Localize.Message.format(msg, %{"count" => 5}) == {:ok, "other items"}
    end
  end
end
