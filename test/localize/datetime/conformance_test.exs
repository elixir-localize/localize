defmodule Localize.DateTime.ConformanceTest do
  @moduledoc """
  Data-driven conformance tests for date/time formatting using
  CLDR test data from `test/support/data/date_time_formatting.json`.

  These tests compare Localize formatting output against the expected
  results defined by the Unicode CLDR standard.

  Adapted from DateTime.CldrUnitTest in ex_cldr_dates_times.
  """

  use ExUnit.Case, async: true

  # Every Gregorian case in the fixture passes. Three things got it there,
  # each of which had been standing in for the others:
  #
  #   * The datetime wrapper defaults to TR35's `atTime` pattern, as CLDR 48
  #     specified. Two cases were excluded as `@should_be_at_format`.
  #
  #   * The date/time split path adjusts the matched patterns' field widths.
  #     It did not, so a requested zone symbol was silently replaced by
  #     whichever the matched format carried — `:MMMMdjmsO` matched `hmsv`
  #     and rendered "GMT" where `O` gives "GMT+0". That accounted for eight
  #     of the `@timezone_tests` and all six `@skeleton_match_issues`.
  #
  #   * `:tz` is a test dependency, so `Australia/Adelaide` resolves to a
  #     real offset and daylight flag. Fifteen cases needed it; without a
  #     timezone database `DateTime.shift_zone/2` fails and the fixture's
  #     input silently arrives as UTC.
  #
  # The remaining `@wrong_format` indices are not Gregorian and so never
  # ran; they are kept for whenever the other calendars are enabled below.
  @wrong_format [283, 256, 266, 285, 258, 267, 284, 257, 265, 286]

  @maybe_incorrect_test_result @wrong_format

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
