defmodule Localize.NumberQuotedPatternTest do
  @moduledoc """
  Number patterns with quoted literal text, and patterns with a character no
  pattern syntax accepts.

  TR35 §Number Format Patterns: single quotes enclose literal text, and two
  single quotes stand for one, inside or outside a quoted string: "'#'#"
  formats 123 as "#123" and "# o''clock" formats 5 as "5 o'clock". Literal
  text is kept as written, including spaces at either end: ICU4C 78.3 formats
  1234 with `#,##0 'units'` as "1,234 units", with `#,##0' units '` as
  "1,234 units " and 1939 with TR35's `'X '#' Q '` as "X 1939 Q ". A quoted
  run of more than one character used to loop in the pattern lexer and
  exhaust memory, so every call here runs under a timeout and a regression
  fails instead of hanging.

  """

  use ExUnit.Case, async: true

  defp bounded(fun) do
    task = Task.async(fun)

    case Task.yield(task, 5_000) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      _timed_out -> :timed_out
    end
  end

  defp joined({:ok, parts}), do: {:ok, Enum.map_join(parts, & &1.value)}
  defp joined(other), do: other

  test "quoted literal text formats as literal text, spaces included" do
    for {pattern, number, expected} <- [
          {"#,##0 'units'", 1234, "1,234 units"},
          {"#,##0' units '", 1234, "1,234 units "},
          {"#,##0' '", 1234, "1,234 "},
          {"#,##0 ", 1234, "1,234 "},
          {"'X '#' Q '", 1939, "X 1939 Q "},
          {"'  '#", 7, "  7"}
        ] do
      string = bounded(fn -> Localize.Number.to_string(number, format: pattern, locale: :en) end)

      parts =
        bounded(fn -> joined(Localize.Number.to_parts(number, format: pattern, locale: :en)) end)

      assert {pattern, string} == {pattern, {:ok, expected}}
      assert {pattern, parts} == {pattern, {:ok, expected}}
    end
  end

  test "a quoted special character and a doubled quote are literal" do
    for {pattern, number, expected} <- [
          {"'#'#", 123, "#123"},
          {"# o''clock", 5, "5 o'clock"},
          {"# 'o''clock'", 5, "5 o'clock"}
        ] do
      string = bounded(fn -> Localize.Number.to_string(number, format: pattern, locale: :en) end)

      parts =
        bounded(fn -> joined(Localize.Number.to_parts(number, format: pattern, locale: :en)) end)

      assert {pattern, string} == {pattern, {:ok, expected}}
      assert {pattern, parts} == {pattern, {:ok, expected}}
    end
  end

  test "a pattern with a character no pattern syntax accepts is an error" do
    for pattern <- ["#,##0*", "#,##0'", "'"] do
      assert {:error, %Localize.InvalidValueError{}} =
               bounded(fn -> Localize.Number.to_string(1234, format: pattern, locale: :en) end)

      assert {:error, %Localize.InvalidValueError{}} =
               bounded(fn -> Localize.Number.to_parts(1234, format: pattern, locale: :en) end)
    end
  end
end
