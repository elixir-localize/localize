defmodule Localize.Message.FormatterTest do
  use ExUnit.Case, async: true

  alias Localize.Message
  alias Localize.Message.Formatter

  describe "HTML formatter" do
    test "wraps each token in a span with mf2- prefixed class" do
      {:ok, html} = Message.to_html("Hello {$name}")
      assert html =~ ~s(<span class="mf2-text">Hello </span>)
      assert html =~ ~s(<span class="mf2-name_variable">$name</span>)
      assert html =~ ~s(<span class="mf2-punctuation">{</span>)
    end

    test "HTML-escapes token content" do
      # Text with HTML-reserved characters is escaped in the output.
      {:ok, html} = Message.to_html("<script>alert(1)</script>")
      refute html =~ "<script>"
      assert html =~ "&lt;script&gt;"
    end

    test "produces fragment output by default" do
      {:ok, html} = Message.to_html("Hello")
      refute String.starts_with?(html, "<pre")
    end

    test "wraps in <pre><code> when standalone: true" do
      {:ok, html} = Message.to_html("Hello", standalone: true)
      assert String.starts_with?(html, ~s(<pre class="mf2-highlight"><code>))
      assert String.ends_with?(html, "</code></pre>")
    end

    test "respects :class_prefix option" do
      {:ok, html} = Message.to_html("Hello", class_prefix: "xx-")
      assert html =~ ~s(<span class="xx-text">)
      refute html =~ ~s(<span class="mf2-text">)
    end

    test "stripping spans from HTML output yields canonical message" do
      msgs = ["Hello {$name}", "{#bold}x{/bold}", "{|literal|}"]

      for msg <- msgs do
        {:ok, canonical} = Message.canonical_message(msg)
        {:ok, html} = Message.to_html(msg)

        unescaped =
          html
          |> String.replace(~r/<[^>]+>/, "")
          |> String.replace("&lt;", "<")
          |> String.replace("&gt;", ">")
          |> String.replace("&quot;", "\"")
          |> String.replace("&amp;", "&")

        assert unescaped == canonical, "round-trip failed for #{inspect(msg)}"
      end
    end
  end

  describe "ANSI formatter" do
    test "emits ANSI escape codes for coloured classes" do
      {:ok, ansi} = Message.to_ansi("Hello {$name}")
      # Cyan = \e[36m for punctuation. Green = \e[32m for variable.
      assert ansi =~ "\e["
    end

    test "emits a :reset sequence after each coloured token" do
      {:ok, ansi} = Message.to_ansi("{$name}")
      # \e[0m is the reset sequence.
      assert ansi =~ "\e[0m"
    end

    test "stripping ANSI escapes from output yields canonical message" do
      msgs = [
        "Hello",
        "Hello {$name}",
        "{#bold}text{/bold}",
        ".input {$n :number}\n.match $n\n1 {{one}}\n* {{other}}"
      ]

      for msg <- msgs do
        {:ok, canonical} = Message.canonical_message(msg)
        {:ok, ansi} = Message.to_ansi(msg)
        stripped = Regex.replace(~r/\e\[[0-9;]*m/, ansi, "")
        assert stripped == canonical, "round-trip failed for #{inspect(msg)}"
      end
    end

    test "custom palette overrides the default" do
      custom = %{name_variable: [:red]}
      {:ok, default} = Message.to_ansi("{$name}")
      {:ok, custom_out} = Message.to_ansi("{$name}", palette: custom)
      refute default == custom_out
      # Red = \e[31m
      assert custom_out =~ "\e[31m"
    end
  end

  describe "Formatter.render/3 dispatch" do
    test "dispatches :plain to the Plain formatter" do
      {:ok, tokens} = Message.to_tokens("Hello")
      assert Formatter.render(tokens, :plain) == "Hello"
    end

    test "dispatches :html to the HTML formatter" do
      {:ok, tokens} = Message.to_tokens("Hello")
      html = Formatter.render(tokens, :html)
      assert html =~ ~s(<span class="mf2-text">)
    end

    test "dispatches :ansi to the ANSI formatter" do
      {:ok, tokens} = Message.to_tokens("Hello")
      ansi = Formatter.render(tokens, :ansi)
      assert is_binary(ansi)
    end
  end
end
