defmodule Localize.LintTest do
  use ExUnit.Case, async: true

  # Source-level lint tests that catch fragile patterns the team has
  # been bitten by. These run as part of `mix test` so a CI failure
  # surfaces immediately on the offending PR — there is no separate
  # static-analysis step to wire up.

  @root File.cwd!() |> Path.join("lib")

  describe "no {:ok, _} = Localize.<fallible_call> anti-pattern" do
    # The original bug behind issue #26 (and the underlying anti-pattern
    # that surfaced as a `MatchError` in `mix localize.download_locales`)
    # was a bare `{:ok, _} = Localize.Message.format(...)` against
    # caller-shaped input. Any future `{:ok, ...} =` match on the
    # right-hand side of a fallible Localize call risks the same crash
    # mode. Use `case`, `with`, or `{:ok, _} = ...!` (the bang variant)
    # instead.
    #
    # This test scans `lib/` and fails if any new offender appears.
    # The empty allowlist below is deliberate: every existing instance
    # was fixed when the test was introduced. If a legitimate new use
    # arises (e.g. operating on bundled, never-failing data), justify
    # it in a comment at the site and add the file/line tuple to
    # `@allowed`.

    # Localize calls whose `{:ok, _}` result is unsafe to pattern-match
    # against because they can return `{:error, _}` on caller-controlled
    # input, locale fallback, or downstream data lookups.
    @unsafe_calls [
      "Localize.Message.format",
      "Localize.Message.format_to_iolist",
      "Localize.Message.format_to_safe_list",
      "Localize.Number.parse",
      "Localize.Number.to_string",
      "Localize.Date.to_string",
      "Localize.Time.to_string",
      "Localize.DateTime.to_string",
      "Localize.Interval.to_string",
      "Localize.Duration.to_string",
      "Localize.Unit.to_string",
      "Localize.Unit.new",
      "Localize.Unit.parse",
      "Localize.Unit.Parser.parse",
      "Localize.List.to_string",
      "Localize.LanguageTag.parse",
      "Localize.LanguageTag.new",
      "Localize.Locale.new",
      "Localize.Locale.get",
      "Localize.Locale.parent",
      "Localize.validate_locale"
    ]

    # File/line pairs that have been reviewed and are known-safe.
    # Add new entries with a justification comment on the line.
    @allowed []

    test "no source file pattern-matches {:ok, _} = <unsafe Localize call>" do
      offenders =
        @root
        |> all_elixir_files()
        |> Enum.flat_map(&scan_file/1)
        |> Enum.reject(fn {file, line, _snippet} -> {file, line} in @allowed end)

      assert offenders == [],
             "\n\nFragile `{:ok, _} = <Localize call>` matches found:\n\n" <>
               Enum.map_join(offenders, "\n", fn {file, line, snippet} ->
                 "  #{Path.relative_to(file, File.cwd!())}:#{line}\n    #{snippet}"
               end) <>
               "\n\nAny one of these can crash the calling process with a " <>
               "`MatchError` when the fallible call returns `{:error, _}`. " <>
               "Use `case`, `with`, or the bang variant of the function " <>
               "instead. See `test/localize/lint_test.exs` for context."
    end

    defp scan_file(path) do
      path
      |> File.stream!()
      |> Stream.with_index(1)
      |> Stream.reject(fn {line, _} -> doctest_line?(line) end)
      |> Stream.flat_map(fn {line, line_number} ->
        @unsafe_calls
        |> Enum.filter(&match_line?(line, &1))
        |> Enum.map(fn _call -> {path, line_number, String.trim(line)} end)
      end)
      |> Enum.to_list()
    end

    # A line is a doctest example if its first non-space character is
    # the `#` of a comment OR it starts with `iex>` / `...>` after
    # leading whitespace.
    defp doctest_line?(line) do
      trimmed = String.trim_leading(line)

      String.starts_with?(trimmed, "iex>") or String.starts_with?(trimmed, "...>") or
        String.starts_with?(trimmed, "#")
    end

    defp match_line?(line, call) do
      # Match `{:ok, ...} = <call>(` allowing single-line patterns
      # only. Multi-line tuple patterns are rare and we accept the
      # false-negative trade-off.
      Regex.match?(~r/\{\s*:ok\s*,[^}]+\}\s*=\s*#{Regex.escape(call)}\s*\(/, line)
    end

    defp all_elixir_files(root) do
      root
      |> Path.join("**/*.ex")
      |> Path.wildcard()
    end
  end
end
