defmodule Localize.Collation.ConformanceTest do
  use ExUnit.Case

  @moduletag :conformance
  @moduletag timeout: 600_000

  # Known failure thresholds. Remaining failures are:
  # - Tibetan vowel decomposition edge cases (F81→F71+F80, etc.)
  # - Musical symbol multi-codepoint CE sequences
  # - Variation selector-256 (E01EF) ordering
  # - Hangul + combining mark + jamo sequences
  # Surrogate codepoint pairs (D800-DFFF) are excluded since they are
  # not valid Unicode scalar values and cannot appear in Elixir strings.
  @max_non_ignorable_failures 0
  @max_shifted_failures 0

  setup_all do
    Localize.Collation.ensure_loaded()
    :ok
  end

  @doc """
  Parse a conformance test file line into a list of codepoints.
  Uses codepoint lists instead of strings to handle surrogate codepoints.
  """
  def parse_test_line(line) do
    line
    |> String.trim()
    |> String.split()
    |> Enum.map(&String.to_integer(&1, 16))
  end

  @doc """
  Read test data lines from a conformance test file.
  Returns a list of codepoint lists in the expected sort order.
  Excludes lines containing surrogate codepoints (D800-DFFF) since
  they are not valid Unicode scalar values in Elixir.
  """
  def read_test_data(path) do
    path
    |> File.stream!()
    |> Stream.reject(fn line ->
      trimmed = String.trim(line)
      trimmed == "" or String.starts_with?(trimmed, "#")
    end)
    |> Stream.map(&parse_test_line/1)
    |> Stream.reject(fn cps ->
      Enum.any?(cps, fn cp -> cp >= 0xD800 and cp <= 0xDFFF end)
    end)
    |> Enum.to_list()
  end

  defp compare_codepoints(cps_a, cps_b, options) do
    opts = Localize.Collation.Options.new(options)
    key_a = Localize.Collation.sort_key(cps_a, opts)
    key_b = Localize.Collation.sort_key(cps_b, opts)

    cond do
      key_a < key_b -> :lt
      key_a > key_b -> :gt
      true -> :eq
    end
  end

  defp format_codepoints(cps) do
    Enum.map(cps, &Integer.to_string(&1, 16)) |> Enum.join(" ")
  end

  describe "NON_IGNORABLE conformance" do
    test "all consecutive pairs sort correctly" do
      path = Path.join([test_data_dir(), "CollationTest_CLDR_NON_IGNORABLE_SHORT.txt"])

      unless File.exists?(path) do
        flunk("Test data file not found: #{path}")
      end

      codepoint_lists = read_test_data(path)

      failures =
        codepoint_lists
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.with_index()
        |> Enum.reduce([], fn {[a, b], idx}, failures ->
          result = compare_codepoints(a, b, strength: :identical, normalization: true)

          if result == :gt do
            [{idx + 1, a, b} | failures]
          else
            failures
          end
        end)

      failure_count = length(failures)
      total = length(codepoint_lists) - 1

      if failure_count > @max_non_ignorable_failures do
        sample =
          failures
          |> Enum.take(10)
          |> Enum.map(fn {line, a, b} ->
            "  line #{line}: #{format_codepoints(a)} > #{format_codepoints(b)}"
          end)
          |> Enum.join("\n")

        flunk(
          "#{failure_count}/#{total} pairs failed NON_IGNORABLE ordering " <>
            "(threshold: #{@max_non_ignorable_failures}).\nFirst failures:\n#{sample}"
        )
      end
    end
  end

  describe "SHIFTED conformance" do
    test "all consecutive pairs sort correctly with shifted alternate" do
      path = Path.join([test_data_dir(), "CollationTest_CLDR_SHIFTED_SHORT.txt"])

      unless File.exists?(path) do
        flunk("Test data file not found: #{path}")
      end

      codepoint_lists = read_test_data(path)

      failures =
        codepoint_lists
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.with_index()
        |> Enum.reduce([], fn {[a, b], idx}, failures ->
          result =
            compare_codepoints(a, b,
              alternate: :shifted,
              strength: :identical,
              normalization: true
            )

          if result == :gt do
            [{idx + 1, a, b} | failures]
          else
            failures
          end
        end)

      failure_count = length(failures)
      total = length(codepoint_lists) - 1

      if failure_count > @max_shifted_failures do
        sample =
          failures
          |> Enum.take(10)
          |> Enum.map(fn {line, a, b} ->
            "  line #{line}: #{format_codepoints(a)} > #{format_codepoints(b)}"
          end)
          |> Enum.join("\n")

        flunk(
          "#{failure_count}/#{total} pairs failed SHIFTED ordering " <>
            "(threshold: #{@max_shifted_failures}).\nFirst failures:\n#{sample}"
        )
      end
    end
  end

  defp test_data_dir do
    Path.join([File.cwd!(), "test", "support", "data"])
  end
end
