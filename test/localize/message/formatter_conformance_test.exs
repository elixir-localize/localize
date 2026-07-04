defmodule Localize.Message.FormatterConformanceTest do
  @moduledoc """
  MF2 WG formatter-conformance tests for `Localize.Message.format/3`.

  Runs the MessageFormat 2 working group's official test suite
  (vendored under `test/support/data/mf2_conformance/`) against the
  Elixir interpreter and asserts the formatted output — not just the
  parse verdict, which `Localize.Message.ConformanceTest` already
  covers for `syntax.json` and `syntax-errors.json`.

  Each test case is asserted as one of:

  * cases with an `exp` value and no expected errors must format to
    exactly that output: `{:ok, exp}`.

  * cases with a non-empty `expErrors` list must return `{:error, _}`.
    The error type is not matched — the WG error taxonomy does not map
    one-to-one onto Localize exceptions.

  * cases with neither `exp` nor `expErrors` (including
    `expParts`-only cases) must format without error: `{:ok, _}`.
    The output is not compared because it is unspecified.

  Typed parameter values are converted before formatting:
  `{"date": ms}` becomes a `DateTime` and `{"decimal": s}` becomes a
  `Decimal`.

  Files whose `defaultTestProperties` request the WG `default` bidi
  isolation strategy are run with `bidi: :isolate`, which is the
  closest Localize equivalent. The `:isolate` mode wraps every
  placeholder in FSI/PDI, whereas the WG default strategy leaves
  placeholders with a known LTR direction unisolated — the handful of
  cases where the two differ are excluded below.

  Cases the implementation cannot yet satisfy are excluded via
  `@exclusions`, each with a one-line reason. Remove entries as the
  gaps close.

  To refresh the vendored JSONs from upstream:

      curl -sL https://raw.githubusercontent.com/unicode-org/message-format-wg/main/test/tests/<file> \\
        > test/support/data/mf2_conformance/<file>
  """

  use ExUnit.Case, async: true

  # Resolve the conformance JSONs at compile time, independent of the
  # directory `mix test` is invoked from.
  @conformance_dir Path.expand(
                     "../../support/data/mf2_conformance",
                     __DIR__
                   )

  @files [
    "syntax.json",
    "data-model-errors.json",
    "pattern-selection.json",
    "fallback.json",
    "bidi.json",
    "u-options.json",
    "functions/currency.json",
    "functions/date.json",
    "functions/datetime.json",
    "functions/integer.json",
    "functions/number.json",
    "functions/offset.json",
    "functions/percent.json",
    "functions/string.json",
    "functions/time.json"
  ]

  for file <- @files do
    @external_resource Path.join(@conformance_dir, file)
  end

  # Excluded cases, grouped per file as reason => [case indexes].
  # Every exclusion is a real, documented implementation gap; the
  # remaining cases in each file are asserted.
  @exclusion_groups %{
    "syntax.json" => %{
      "known gap: unknown functions fall back to formatting the operand instead of an unknown-function error" =>
        [12, 13, 17, 18, 27, 34, 35, 36, 37, 38, 45, 46, 47, 57, 58, 59, 60],
      "known gap: unannotated number operands are not implicitly formatted with the locale-aware :number function" =>
        [90]
    },
    "data-model-errors.json" => %{
      # Cases 16 and 17 (a declaration option referencing a not-yet-declared
      # variable) now pass: the unresolved option variable is reported as an
      # unbound-variable error.
      "known gap: duplicate-declaration data-model validation not implemented" => [
        8,
        9,
        10,
        11,
        12,
        13,
        14,
        15
      ],
      "known gap: duplicate-option-name data-model validation not implemented" => [18, 19]
    },
    "pattern-selection.json" => %{
      "WG :test:select/:test:format registry functions not implemented" => [
        2,
        6,
        7,
        8,
        9,
        10,
        11,
        12,
        14,
        20,
        21
      ]
    },
    "fallback.json" => %{
      "WG :test:* registry functions and unknown-function errors not implemented" => [
        0,
        1,
        4,
        5,
        6,
        7
      ]
    },
    "bidi.json" => %{
      "WG default bidi strategy leaves known-LTR placeholders unisolated; :isolate wraps all placeholders" =>
        [16, 19, 20]
    },
    "u-options.json" => %{
      "u:dir/u:id expression options not implemented" => [1, 2, 3, 5, 6, 8]
    },
    "functions/currency.json" => %{
      "known gap: :currency is not rejected as a selector (no bad-selector error)" => [11],
      "known gap: declarations bind the formatted string, so re-annotating an annotated variable fails" =>
        [7]
    },
    "functions/date.json" => %{
      "known gap: declarations bind the formatted string, so re-annotating an annotated variable fails" =>
        [6]
    },
    "functions/integer.json" => %{
      "known gap: select option validation (literal-only, operand restrictions) not implemented" =>
        [8, 9, 11, 12]
    },
    "functions/number.json" => %{
      "known gap: number-literal operand validation (leading zero or plus sign) not enforced" => [
        18,
        19
      ],
      "known gap: invalid digit size option values are ignored instead of a bad-option error" => [
        28,
        32
      ],
      "known gap: select option validation (literal-only, operand restrictions) not implemented" =>
        [35, 36, 38, 39]
    },
    "functions/offset.json" => %{
      "known gap: signDisplay option not implemented" => [10, 11]
    },
    "functions/percent.json" => %{
      "known gap: declarations bind the formatted string, so re-annotating an annotated variable fails" =>
        [5]
    },
    "functions/string.json" => %{
      "known gap: variant keys are not NFC-normalized, so duplicate-variant is not detected" => [
        4,
        5,
        6
      ]
    },
    "functions/time.json" => %{
      "known gap: declarations bind the formatted string, so re-annotating an annotated variable fails" =>
        [5]
    }
  }

  @exclusions (for {file, groups} <- @exclusion_groups,
                   {reason, indexes} <- groups,
                   index <- indexes,
                   into: %{} do
                 {{file, index}, reason}
               end)

  for file <- @files do
    data = @conformance_dir |> Path.join(file) |> File.read!() |> :json.decode()
    defaults = Map.get(data, "defaultTestProperties", %{})
    default_locale = Map.get(defaults, "locale", "en-US")
    default_errors = Map.get(defaults, "expErrors", [])

    bidi_options =
      if Map.get(defaults, "bidiIsolation") == "default", do: [bidi: :isolate], else: []

    describe "MF2 WG `#{file}` — formatted output" do
      for {test_case, index} <- Enum.with_index(Map.fetch!(data, "tests")),
          not Map.has_key?(@exclusions, {file, index}) do
        src =
          case Map.fetch!(test_case, "src") do
            list when is_list(list) -> Enum.join(list)
            binary when is_binary(binary) -> binary
          end

        locale = Map.get(test_case, "locale", default_locale)
        raw_params = Map.get(test_case, "params", [])
        exp_errors = Map.get(test_case, "expErrors", default_errors)
        format_options = [locale: locale] ++ bidi_options

        title =
          test_case
          |> Map.get("description", src)
          |> String.replace(["\n", "\t"], " ")
          |> String.slice(0, 80)

        expectation =
          cond do
            exp_errors == true or (is_list(exp_errors) and exp_errors != []) -> :error
            Map.has_key?(test_case, "exp") -> {:ok, Map.fetch!(test_case, "exp")}
            true -> :success
          end

        case expectation do
          {:ok, expected} ->
            @tag :mf2_formatter_conformance
            test "##{index}: #{title}" do
              params = convert_params(unquote(Macro.escape(raw_params)))

              assert Localize.Message.format(
                       unquote(src),
                       params,
                       unquote(format_options)
                     ) == {:ok, unquote(expected)}
            end

          :error ->
            @tag :mf2_formatter_conformance
            test "##{index}: #{title}" do
              params = convert_params(unquote(Macro.escape(raw_params)))

              assert {:error, _reason} =
                       Localize.Message.format(
                         unquote(src),
                         params,
                         unquote(format_options)
                       )
            end

          :success ->
            @tag :mf2_formatter_conformance
            test "##{index}: #{title}" do
              params = convert_params(unquote(Macro.escape(raw_params)))

              assert {:ok, _formatted} =
                       Localize.Message.format(
                         unquote(src),
                         params,
                         unquote(format_options)
                       )
            end
        end
      end
    end
  end

  # ── Parameter conversion ─────────────────────────────────────────
  #
  # The WG schema wraps typed parameter values: {"date": ms} is a
  # timestamp in milliseconds since the epoch and {"decimal": s} is
  # an arbitrary-precision decimal string. Plain values pass through.

  defp convert_params(params) do
    Map.new(params, fn %{"name" => name, "value" => value} ->
      {name, convert_value(value)}
    end)
  end

  defp convert_value(%{"date" => milliseconds}) do
    DateTime.from_unix!(milliseconds, :millisecond)
  end

  defp convert_value(%{"decimal" => string}) do
    Decimal.new(string)
  end

  defp convert_value(value), do: value
end
