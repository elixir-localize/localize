defmodule Localize.Message.Formatter.PluginTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Localize.Message.Formatter.Plugin

  describe "features/1" do
    test "declares :M sigil and .mf2 extension" do
      assert Plugin.features([]) == [sigils: [:M], extensions: [".mf2"]]
    end

    test "does not claim the lowercase :m sigil" do
      refute :m in Plugin.features([])[:sigils]
    end
  end

  describe "format/2 — ~M sigils" do
    test "canonicalises an already-canonical single-line message (idempotent)" do
      assert Plugin.format("Hello {$name}", sigil: :M) == "Hello {$name}"
    end

    test "normalises excess whitespace inside expressions" do
      # Whatever whitespace the user typed, the output is canonical.
      input = "Hello {   $name    }"
      output = Plugin.format(input, sigil: :M)
      assert output != input
      # Whatever the canonical form is, running format again is a no-op.
      assert Plugin.format(output, sigil: :M) == output
    end

    test "pretty-prints multi-line complex messages when :auto" do
      input = ".input {$count :number}\n.match $count\n1 {{one}}\n* {{other}}"
      output = Plugin.format(input, sigil: :M)

      assert output =~ ".input"
      assert output =~ ".match"
      # Contains newlines (pretty form).
      assert String.contains?(output, "\n")
    end

    test "compact form with mf2: [pretty: false]" do
      input = ".input {$count :number}\n.match $count\n1 {{one}}\n* {{other}}"
      output = Plugin.format(input, sigil: :M, mf2: [pretty: false])
      refute String.contains?(String.trim(output), "\n\n")
    end

    test "invalid MF2 returns input unchanged and warns" do
      input = "Hello {unclosed"

      log =
        capture_io(:stderr, fn ->
          assert Plugin.format(input, sigil: :M, file: "lib/foo.ex", line: 10) == input
        end)

      assert log =~ "lib/foo.ex"
      assert log =~ "~M sigil"
    end

    test "preserves trailing newline shape" do
      # Heredoc-style input with trailing newline.
      input = "Hello {$name}\n"
      output = Plugin.format(input, sigil: :M)
      assert String.ends_with?(output, "\n")

      # Non-heredoc input without trailing newline.
      input = "Hello {$name}"
      output = Plugin.format(input, sigil: :M)
      refute String.ends_with?(output, "\n")
    end
  end

  describe "format/2 — .mf2 files" do
    test "canonicalises a standalone file" do
      input = ".input {  $count :number  }\n.match $count\n1 {{one}}\n* {{other}}"
      output = Plugin.format(input, extension: ".mf2")

      assert String.ends_with?(output, "\n")
      # Idempotent on a second pass.
      assert Plugin.format(output, extension: ".mf2") == output
    end

    test "always ends with a single newline" do
      input = "Hello"
      output = Plugin.format(input, extension: ".mf2")
      assert String.ends_with?(output, "\n")
      refute String.ends_with?(output, "\n\n")
    end

    test "invalid MF2 returns input unchanged and warns" do
      input = "{unclosed"

      log =
        capture_io(:stderr, fn ->
          assert Plugin.format(input, extension: ".mf2", file: "priv/a.mf2") == input
        end)

      assert log =~ "priv/a.mf2"
      assert log =~ "MF2 file"
    end
  end

  describe "format/2 — no sigil, no extension" do
    test "returns input unchanged" do
      assert Plugin.format("whatever", []) == "whatever"
    end
  end

  describe "format/2 — :pretty option validation" do
    test "raises on invalid :pretty value" do
      assert_raise ArgumentError, fn ->
        Plugin.format("Hello", sigil: :M, mf2: [pretty: :sometimes])
      end
    end
  end

  # ── Property: idempotency ─────────────────────────────────────────

  describe "idempotency property" do
    use ExUnitProperties

    @sample_messages [
      "Hello",
      "Hello {$name}",
      "Hello {$name :string}",
      "Hello {$count :number minimumFractionDigits=2}",
      "{#bold}text{/bold}",
      "Click {#link href=|/home|}here{/link}",
      "before {#br /}after",
      "{$x @translate}",
      "{$x @dir=|ltr|}",
      "{42} and {3.14}",
      "{|literal with \\| pipe|}",
      "escaped \\{ brace",
      ".input {$count :number}\n.match $count\n1 {{one}}\n* {{other}}",
      ".local $x = {$count}\n{{Count is {$x}}}"
    ]

    property "formatting is idempotent across a sample of real MF2 messages" do
      check all(message <- StreamData.member_of(@sample_messages)) do
        once = Plugin.format(message, sigil: :M)
        twice = Plugin.format(once, sigil: :M)
        assert once == twice
      end
    end
  end
end
