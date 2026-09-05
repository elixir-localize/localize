defmodule Localize.DateTime.ConformanceTest do
  @moduledoc """
  Data-driven conformance tests for date/time formatting using
  CLDR test data from `test/support/data/date_time_formatting.json`.

  These tests compare Localize formatting output against the expected
  results defined by the Unicode CLDR standard.

  Adapted from DateTime.CldrUnitTest in ex_cldr_dates_times.
  """

  use ExUnit.Case, async: true

  # Tests where ex_cldr_dates_times also has known issues
  @wrong_format [283, 256, 266, 285, 258, 267, 284, 257, 265, 286]

  # Tests requiring timezone name resolution (z, Z, O, v, V symbols)
  # or the `j` meta-symbol in skeleton matching. These need
  # full timezone support and locale-sensitive hour cycle resolution.
  #
  # 48, 51, 52, 56, 59 and 60 were previously excluded as `@should_be_at_format`
  # — the datetime wrapper now defaults to TR35's `atTime` pattern, which
  # retired 47 and 55, and showed the other six to be misfiled. They are zone
  # symbol substitution: the skeleton matcher treats `v`, `V`, `O`, `z` and `Z`
  # as interchangeable, so `:MMMMdjmsO` matches a format carrying `z` and
  # renders "GMT" where the requested `O` gives "GMT+0". Each symbol formats
  # correctly on its own; it is the match that loses the request.
  @timezone_tests [
    14,
    16,
    18,
    38,
    39,
    40,
    41,
    42,
    44,
    45,
    46,
    48,
    49,
    50,
    51,
    52,
    53,
    54,
    56,
    57,
    58,
    59,
    60
  ]
  @j_symbol_tests []
  @skeleton_match_issues [19, 20, 21, 34, 35, 36]

  @maybe_incorrect_test_result @wrong_format ++
                                 @timezone_tests ++
                                 @j_symbol_tests ++
                                 @skeleton_match_issues

  # Only test gregorian calendar for now
  @test_calendars [:gregorian]

  for test <- Localize.DateTime.TestData.parse(),
      test.calendar in @test_calendars,
      test.index not in @maybe_incorrect_test_result do
    case test.test_module do
      Localize.Date ->
        test "##{test.index} Date format #{inspect(test.date_format)} with locale #{inspect(test.locale)}" do
          assert {:ok, unquote(test.expected)} =
                   Localize.Date.to_string(unquote(Macro.escape(test.input)),
                     format: unquote(test.date_format),
                     locale: unquote(test.locale)
                   )
        end

      Localize.Time ->
        test "##{test.index} Time format #{inspect(test.time_format)} with locale #{inspect(test.locale)}" do
          assert {:ok, unquote(test.expected)} =
                   Localize.Time.to_string(unquote(Macro.escape(test.input)),
                     format: unquote(test.time_format),
                     locale: unquote(test.locale)
                   )
        end

      Localize.DateTime ->
        if test[:date_format] && test[:time_format] do
          test "##{test.index} DateTime date format #{inspect(test.date_format)} and time format #{inspect(test.time_format)} with locale #{inspect(test.locale)}" do
            assert {:ok, unquote(test.expected)} =
                     Localize.DateTime.to_string(unquote(Macro.escape(test.input)),
                       date_format: unquote(test.date_format),
                       time_format: unquote(test.time_format),
                       style: unquote(test.style),
                       locale: unquote(test.locale)
                     )
          end
        else
          test "##{test.index} DateTime format #{inspect(test[:skeleton])} with locale #{inspect(test.locale)}" do
            assert {:ok, unquote(test.expected)} =
                     Localize.DateTime.to_string(unquote(Macro.escape(test.input)),
                       format: unquote(test[:skeleton]),
                       style: unquote(test.style),
                       locale: unquote(test.locale)
                     )
          end
        end
    end
  end
end
