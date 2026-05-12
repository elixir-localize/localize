defmodule Localize.Message.Formatter.Plugin do
  @moduledoc """
  [`mix format`](https://hexdocs.pm/mix/Mix.Tasks.Format.html) plugin that
  canonicalises ICU MessageFormat 2 (MF2) messages.

  The plugin handles two input shapes:

  * **`~M` sigils in Elixir source.** Content between `~M"..."`,
    `~M\"""...\"""`, `~M(...)`, etc. is parsed as MF2 and rewritten to
    its canonical form (same form the `~M` sigil produces at compile
    time via `Localize.Message.canonical_message!/2`). This keeps the
    source text identical to what the compiler records and makes
    translator keys stable regardless of developer whitespace
    preferences.

  * **Standalone `.mf2` files.** Files listed under the formatter's
    `:inputs` and matching `*.mf2` are rewritten in place. Useful when
    messages live in their own files rather than embedded in Elixir.

  The lowercase `~m` sigil is *not* supported by this plugin. `~m`
  permits `\#{interpolation}`, which cannot be round-tripped through
  the MF2 parser without losing structure. Use `~M` for anything you
  want `mix format` to touch.

  ## Installation

  Add to the project's `.formatter.exs`:

      [
        plugins: [Localize.Message.Formatter.Plugin],
        inputs: [
          "{mix,.formatter}.exs",
          "{config,lib,test}/**/*.{ex,exs}",
          "priv/messages/**/*.mf2"
        ]
      ]

  Running `mix format` will then canonicalise every `~M` sigil body in
  the Elixir files and every `.mf2` file under `priv/messages/`.

  ## Options

  Plugin options live under the `:mf2` key in `.formatter.exs`:

      [
        plugins: [Localize.Message.Formatter.Plugin],
        mf2: [pretty: true]
      ]

  * `:pretty` — `true | false | :auto` (default `:auto`). When `:auto`,
    single-line input is kept compact and multi-line input is
    pretty-printed. `true`/`false` force one or the other regardless of
    the input shape.

  ## Error handling

  If an MF2 message fails to parse, the plugin **returns the input
  unchanged** and emits a `Mix.shell().error/1` warning naming the file
  (or sigil location, when available) and the line / column reported by
  the parser. `mix format` continues formatting the rest of the file.
  `mix format --check-formatted` then surfaces the warning without
  blocking the run on other files.

  ## Idempotency

  Canonical MF2 is a fixed point of `canonical_message/2`, and a
  property test in the Localize test-suite locks this in. Running
  `mix format` twice produces identical output on the second run.

  """

  @behaviour Mix.Tasks.Format

  @sigils [:M]
  @extensions [".mf2"]

  @impl true
  def features(_opts) do
    [sigils: @sigils, extensions: @extensions]
  end

  @impl true
  def format(contents, opts) when is_binary(contents) do
    cond do
      sigil = opts[:sigil] -> format_sigil(contents, sigil, opts)
      ext = opts[:extension] -> format_file(contents, ext, opts)
      true -> contents
    end
  end

  # ── Sigils ──────────────────────────────────────────────────────────

  # `format/2` is called with the inner body of the sigil. For
  # heredocs, Elixir's formatter has already handled outer indentation;
  # the body we see is the raw text with embedded newlines. We preserve
  # that newline shape to the caller.

  defp format_sigil(contents, sigil, opts) when sigil in @sigils do
    pretty = pretty_for(contents, opts)

    case Localize.Message.canonical_message(contents, pretty: pretty, trim: false) do
      {:ok, canonical} ->
        preserve_trailing_newline(canonical, contents)

      {:error, %Localize.ParseError{} = error} ->
        warn_parse_error(error, opts, "~#{sigil} sigil")
        contents
    end
  end

  # Any other sigil we've accidentally been dispatched for — leave alone.
  defp format_sigil(contents, _sigil, _opts), do: contents

  # ── Files ───────────────────────────────────────────────────────────

  defp format_file(contents, _extension, opts) do
    pretty = pretty_for(contents, opts, default_when_auto: true)

    case Localize.Message.canonical_message(contents, pretty: pretty, trim: true) do
      {:ok, canonical} ->
        # Standalone files end with a single newline (POSIX convention).
        String.trim_trailing(canonical) <> "\n"

      {:error, %Localize.ParseError{} = error} ->
        warn_parse_error(error, opts, "MF2 file")
        contents
    end
  end

  # ── Helpers ─────────────────────────────────────────────────────────

  defp pretty_for(contents, opts, keyword \\ []) do
    default_when_auto = Keyword.get(keyword, :default_when_auto, multi_line?(contents))

    case Keyword.get(opts[:mf2] || [], :pretty, :auto) do
      true -> true
      false -> false
      :auto -> default_when_auto
      other -> raise ArgumentError, "invalid :mf2 :pretty option: #{inspect(other)}"
    end
  end

  defp multi_line?(contents), do: String.contains?(contents, "\n")

  # Keep a single trailing newline iff the input ended with one. The
  # canonical printer may or may not emit one depending on `:pretty` and
  # the final node; we normalise both directions so round-trips are
  # stable.
  defp preserve_trailing_newline(canonical, original) do
    original_nl? = String.ends_with?(original, "\n")
    canonical_nl? = String.ends_with?(canonical, "\n")

    cond do
      original_nl? and not canonical_nl? -> canonical <> "\n"
      not original_nl? and canonical_nl? -> String.trim_trailing(canonical, "\n")
      true -> canonical
    end
  end

  defp warn_parse_error(%Localize.ParseError{} = error, opts, context) do
    file = opts[:file] || "(unknown file)"
    line = (opts[:line] || 0) + (error.line || 1) - 1
    column = error.column || 1

    shell = Mix.shell()

    shell.error(
      "#{file}:#{line}:#{column}: warning: #{context}: #{Exception.message(error)}. " <>
        "The message was left unchanged; fix the MF2 syntax and run `mix format` again."
    )
  end
end
