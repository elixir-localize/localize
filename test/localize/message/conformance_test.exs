defmodule Localize.Message.ConformanceTest do
  @moduledoc """
  MF2 WG syntax-conformance tests for `Localize.Message.Parser`.

  Feeds the parser every input in the MessageFormat 2 working group's
  official syntax test suite and asserts the parse verdict matches
  what the spec says. The suite lives at
  https://github.com/unicode-org/message-format-wg/tree/main/test
  and is vendored under `test/support/data/mf2_conformance/`.

  Two files cover two regimes:

  * `syntax.json` — messages that **must parse successfully**. The
    `exp` field in each case is the expected formatted output, which
    we don't check at the parser level — only that the parse
    succeeds.

  * `syntax-errors.json` — messages that **must be rejected as
    syntax errors**. We assert the parser returns `{:error, _}`.

  The two suites together give a concrete compliance number for
  `Localize.Message.Parser` independent of any runtime behaviour.

  This mirrors the tree-sitter grammar's conformance runner at
  `mf2_treesitter/test/conformance/runner.js`, which tests the
  same suite against the browser-side parser.

  To refresh the vendored JSONs from upstream:

      curl -sL https://raw.githubusercontent.com/unicode-org/message-format-wg/main/test/tests/syntax.json \\
        > test/support/data/mf2_conformance/syntax.json
      curl -sL https://raw.githubusercontent.com/unicode-org/message-format-wg/main/test/tests/syntax-errors.json \\
        > test/support/data/mf2_conformance/syntax-errors.json
  """

  use ExUnit.Case, async: true

  alias Localize.Message.Parser

  # Resolve the conformance JSONs at compile time. Using
  # `Path.expand/2` with `__DIR__` keeps the path correct regardless
  # of where `mix test` is invoked from.
  @conformance_dir Path.expand(
                     "../../support/data/mf2_conformance",
                     __DIR__
                   )

  @syntax_json Path.join(@conformance_dir, "syntax.json")
  @syntax_errors_json Path.join(@conformance_dir, "syntax-errors.json")

  # Register the JSON files as external resources so `mix test`
  # picks them up for recompilation when they change.
  @external_resource @syntax_json
  @external_resource @syntax_errors_json

  @valid_cases @syntax_json
               |> File.read!()
               |> :json.decode()
               |> Map.fetch!("tests")

  @invalid_cases @syntax_errors_json
                 |> File.read!()
                 |> :json.decode()
                 |> Map.fetch!("tests")

  describe "MF2 WG `syntax.json` — inputs that must parse" do
    for {test_case, index} <- Enum.with_index(@valid_cases) do
      @tag :mf2_conformance
      @tag :mf2_conformance_valid
      @tag mf2_case_index: index
      test "##{index}: #{Map.get(test_case, "description", "(no description)") |> String.slice(0, 80)}" do
        src = unquote(Map.fetch!(test_case, "src"))

        case Parser.parse(src) do
          {:ok, _ast} ->
            :ok

          {:error, reason} ->
            flunk("""
            MF2 WG says this input should parse, but Localize.Message.Parser rejected it.

              src:     #{inspect(src)}
              desc:    #{unquote(Map.get(test_case, "description", ""))}
              reason:  #{inspect(reason)}
            """)
        end
      end
    end
  end

  describe "MF2 WG `syntax-errors.json` — inputs that must fail to parse" do
    for {test_case, index} <- Enum.with_index(@invalid_cases) do
      @tag :mf2_conformance
      @tag :mf2_conformance_invalid
      @tag mf2_case_index: index
      test "##{index}: #{Map.get(test_case, "description", Map.fetch!(test_case, "src")) |> String.slice(0, 80) |> String.replace("\n", " ") |> String.replace("\t", " ")}" do
        src = unquote(Map.fetch!(test_case, "src"))

        case Parser.parse(src) do
          {:error, _reason} ->
            :ok

          {:ok, ast} ->
            flunk("""
            MF2 WG says this input should be a syntax error, but Localize.Message.Parser accepted it.

              src: #{inspect(src)}
              ast: #{inspect(ast)}
            """)
        end
      end
    end
  end
end
