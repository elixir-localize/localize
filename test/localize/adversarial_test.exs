defmodule Localize.AdversarialTest do
  @moduledoc """
  Property-based adversarial tests for Localize public API functions.

  Every public formatting function must return either `{:ok, string}`
  or `{:error, exception}` for any combination of valid or invalid
  inputs. No exceptions should be raised and no BEAM crashes should
  occur.

  """

  use ExUnit.Case, async: false
  use ExUnitProperties

  # ── Shared generators ───────────────────────────────────────

  @known_locales [:en, :fr, :de, :ja, :es, :zh, :"en-AU", :"fr-CA", :"pt-BR"]
  @known_formats [:short, :medium, :long, :full]
  @known_number_formats [
    :standard,
    :currency,
    :accounting,
    :percent,
    :scientific,
    :decimal_short,
    :decimal_long,
    :currency_short
  ]
  @known_currencies [:USD, :EUR, :GBP, :JPY, :AUD, :CAD, :CHF, :CNY]
  @known_unit_names [
    "meter",
    "kilometer",
    "kilogram",
    "gram",
    "liter",
    "second",
    "minute",
    "hour",
    "day",
    "celsius",
    "fahrenheit",
    "mile",
    "foot",
    "inch",
    "pound",
    "ounce",
    "gallon",
    "hectare",
    "megabyte",
    "gigabyte",
    "percent",
    "mile-per-hour",
    "kilometer-per-hour"
  ]
  @known_territories [:US, :GB, :DE, :FR, :JP, :CN, :AU, :BR, :CA, :IN]
  @known_unit_styles [:long, :short, :narrow]

  # A locale that is valid or garbage
  defp locale_gen do
    one_of([
      member_of(@known_locales),
      atom(:alphanumeric),
      string(:alphanumeric, min_length: 1, max_length: 10),
      constant(nil),
      integer()
    ])
  end

  # A format that is valid or garbage
  defp format_gen do
    one_of([
      member_of(@known_formats),
      atom(:alphanumeric),
      string(:printable, min_length: 0, max_length: 50),
      constant(nil),
      integer()
    ])
  end

  # A number format that is valid or garbage
  defp number_format_gen do
    one_of([
      member_of(@known_number_formats),
      atom(:alphanumeric),
      string(:printable, min_length: 0, max_length: 30),
      constant(nil),
      integer()
    ])
  end

  # A number that is valid or garbage
  defp number_gen do
    one_of([
      integer(),
      float(),
      constant(0),
      constant(0.0),
      constant(-1),
      constant(1_000_000_000),
      constant(-999_999_999.999),
      constant(1.0e308),
      constant(-1.0e308),
      constant(1.0e-308)
    ])
  end

  # Arbitrary term for stress testing
  defp garbage_gen do
    one_of([
      integer(),
      float(),
      atom(:alphanumeric),
      binary(),
      constant(nil),
      constant(true),
      constant(false),
      list_of(integer(), max_length: 3),
      constant(%{}),
      constant({:foo, :bar}),
      constant(self())
    ])
  end

  # Build a keyword list of options, mixing valid and invalid keys/values
  defp options_gen(extra_generators \\ []) do
    base_generators = [
      constant([]),
      list_of(
        one_of(
          [
            tuple({constant(:locale), locale_gen()}),
            tuple({constant(:format), format_gen()}),
            tuple({constant(:prefer), member_of([:unicode, :ascii, :bogus, nil])}),
            tuple({constant(:style), member_of([:default, :short, :long, :narrow, :at, :bogus])}),
            tuple({constant(:bogus_option), garbage_gen()})
          ] ++ extra_generators
        ),
        max_length: 5
      )
    ]

    one_of(base_generators)
  end

  defp number_options_gen do
    options_gen([
      tuple({constant(:format), number_format_gen()}),
      tuple({constant(:currency), one_of([member_of(@known_currencies), atom(:alphanumeric)])}),
      tuple(
        {constant(:rounding_mode),
         member_of([:down, :half_up, :half_even, :ceiling, :floor, :half_down, :up, :bogus])}
      ),
      tuple(
        {constant(:fractional_digits), one_of([integer(0..10), integer(-5..-1), constant(nil)])}
      ),
      tuple(
        {constant(:number_system),
         one_of([constant(:default), constant(:native), constant(:latn), atom(:alphanumeric)])}
      )
    ])
  end

  # ── Safe call wrapper ───────────────────────────────────────

  # Calls a function and catches all possible failure modes:
  # exceptions, exits, and throws. Returns the result or a
  # tagged failure tuple.
  defp safe_call(fun) do
    {:returned, fun.()}
  rescue
    exception ->
      {:rescued, exception.__struct__, Exception.message(exception)}
  catch
    :exit, reason -> {:exit, reason}
    :throw, value -> {:throw, value}
  end

  # Asserts that a safe_call result is acceptable:
  # - {:returned, {:ok, string}} — success
  # - {:returned, {:error, exception}} — expected error
  # - {:rescued, FunctionClauseError, _} — acceptable for garbage types
  # Everything else is a bug.
  # One clause per safe_call failure mode, each with a distinct flunk
  # message for diagnosis.
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp assert_no_crash(safe_result, label) do
    case safe_result do
      {:returned, {:ok, string}} when is_binary(string) ->
        :ok

      {:returned, {:error, exception}} when is_exception(exception) ->
        :ok

      {:returned, {:error, reason}} ->
        flunk("#{label} returned {:error, #{inspect(reason)}} (not an exception)")

      {:returned, nil} ->
        flunk("#{label} returned nil instead of {:ok, _} or {:error, _}")

      {:returned, other} ->
        flunk("#{label} returned unexpected value: #{inspect(other)}")

      {:rescued, FunctionClauseError, _message} ->
        flunk("#{label} raised FunctionClauseError — should return {:error, _}")

      {:rescued, exception_mod, message} ->
        flunk("#{label} raised #{inspect(exception_mod)}: #{message}")

      {:exit, reason} ->
        flunk("#{label} exited: #{inspect(reason)}")

      {:throw, value} ->
        flunk("#{label} threw: #{inspect(value)}")
    end
  end

  # ── Number.to_string ────────────────────────────────────────

  describe "Localize.Number.to_string/2 adversarial" do
    property "valid numbers with random options" do
      check all(
              number <- number_gen(),
              options <- number_options_gen(),
              max_runs: 500
            ) do
        result = safe_call(fn -> Localize.Number.to_string(number, options) end)
        assert_no_crash(result, "Number.to_string(#{inspect(number)}, #{inspect(options)})")
      end
    end

    property "garbage first arguments" do
      check all(
              input <- garbage_gen(),
              options <- number_options_gen(),
              max_runs: 200
            ) do
        result = safe_call(fn -> Localize.Number.to_string(input, options) end)
        assert_no_crash(result, "Number.to_string(#{inspect(input)}, #{inspect(options)})")
      end
    end
  end

  # ── Date.to_string ──────────────────────────────────────────

  describe "Localize.Date.to_string/2 adversarial" do
    property "valid dates with random options" do
      check all(
              year <- integer(1..3000),
              month <- integer(1..12),
              day <- integer(1..28),
              options <- options_gen(),
              max_runs: 500
            ) do
        date = Date.new!(year, month, day)
        result = safe_call(fn -> Localize.Date.to_string(date, options) end)
        assert_no_crash(result, "Date.to_string(#{inspect(date)}, #{inspect(options)})")
      end
    end

    property "garbage first arguments" do
      check all(
              input <- garbage_gen(),
              options <- options_gen(),
              max_runs: 200
            ) do
        result = safe_call(fn -> Localize.Date.to_string(input, options) end)
        assert_no_crash(result, "Date.to_string(#{inspect(input)}, #{inspect(options)})")
      end
    end
  end

  # ── Time.to_string ──────────────────────────────────────────

  describe "Localize.Time.to_string/2 adversarial" do
    property "valid times with random options" do
      check all(
              hour <- integer(0..23),
              minute <- integer(0..59),
              second <- integer(0..59),
              options <- options_gen(),
              max_runs: 500
            ) do
        time = Time.new!(hour, minute, second)
        result = safe_call(fn -> Localize.Time.to_string(time, options) end)
        assert_no_crash(result, "Time.to_string(#{inspect(time)}, #{inspect(options)})")
      end
    end

    property "garbage first arguments" do
      check all(
              input <- garbage_gen(),
              options <- options_gen(),
              max_runs: 200
            ) do
        result = safe_call(fn -> Localize.Time.to_string(input, options) end)
        assert_no_crash(result, "Time.to_string(#{inspect(input)}, #{inspect(options)})")
      end
    end
  end

  # ── DateTime.to_string ──────────────────────────────────────

  describe "Localize.DateTime.to_string/2 adversarial" do
    property "valid datetimes with random options" do
      check all(
              year <- integer(1..3000),
              month <- integer(1..12),
              day <- integer(1..28),
              hour <- integer(0..23),
              minute <- integer(0..59),
              second <- integer(0..59),
              options <-
                options_gen([
                  tuple({constant(:date_format), member_of(@known_formats ++ [:bogus, nil])}),
                  tuple({constant(:time_format), member_of(@known_formats ++ [:bogus, nil])})
                ]),
              max_runs: 500
            ) do
        datetime = NaiveDateTime.new!(year, month, day, hour, minute, second)
        result = safe_call(fn -> Localize.DateTime.to_string(datetime, options) end)
        assert_no_crash(result, "DateTime.to_string(#{inspect(datetime)}, #{inspect(options)})")
      end
    end

    property "garbage first arguments" do
      check all(
              input <- garbage_gen(),
              options <- options_gen(),
              max_runs: 200
            ) do
        result = safe_call(fn -> Localize.DateTime.to_string(input, options) end)
        assert_no_crash(result, "DateTime.to_string(#{inspect(input)}, #{inspect(options)})")
      end
    end
  end

  # ── Unit.to_string ──────────────────────────────────────────

  describe "Localize.Unit.to_string/2 adversarial" do
    property "valid units with random options" do
      check all(
              amount <- number_gen(),
              unit_name <- member_of(@known_unit_names),
              options <-
                options_gen([
                  tuple({constant(:style), member_of(@known_unit_styles ++ [:bogus, nil])}),
                  tuple(
                    {constant(:grammatical_case),
                     member_of([:nominative, :accusative, :dative, :bogus])}
                  )
                ]),
              max_runs: 500
            ) do
        case Localize.Unit.new(amount, unit_name) do
          {:ok, unit} ->
            result = safe_call(fn -> Localize.Unit.to_string(unit, options) end)
            assert_no_crash(result, "Unit.to_string(#{inspect(unit)}, #{inspect(options)})")

          {:error, _} ->
            :ok
        end
      end
    end

    property "garbage unit names" do
      check all(
              amount <- number_gen(),
              unit_name <- string(:alphanumeric, min_length: 1, max_length: 20),
              options <- options_gen(),
              max_runs: 200
            ) do
        case Localize.Unit.new(amount, unit_name) do
          {:ok, unit} ->
            result = safe_call(fn -> Localize.Unit.to_string(unit, options) end)
            assert_no_crash(result, "Unit.to_string(#{inspect(unit)}, #{inspect(options)})")

          {:error, _} ->
            :ok
        end
      end
    end
  end

  # ── LocaleDisplay.display_name ──────────────────────────────

  describe "Localize.Locale.LocaleDisplay.display_name/2 adversarial" do
    property "valid and random locales with random options" do
      check all(
              locale <-
                one_of([
                  member_of(@known_locales),
                  atom(:alphanumeric),
                  string(:alphanumeric, min_length: 1, max_length: 15)
                ]),
              options <-
                options_gen([
                  tuple(
                    {constant(:language_display), member_of([:standard, :dialect, :bogus, nil])}
                  )
                ]),
              max_runs: 500
            ) do
        result = safe_call(fn -> Localize.Locale.LocaleDisplay.display_name(locale, options) end)

        assert_no_crash(
          result,
          "LocaleDisplay.display_name(#{inspect(locale)}, #{inspect(options)})"
        )
      end
    end
  end

  # ── Territory.display_name ──────────────────────────────────

  describe "Localize.Territory.display_name/2 adversarial" do
    property "valid and random territories with random options" do
      check all(
              territory <-
                one_of([
                  member_of(@known_territories),
                  atom(:alphanumeric),
                  string(:alphanumeric, min_length: 1, max_length: 10)
                ]),
              options <-
                options_gen([
                  tuple({constant(:style), member_of([:short, :standard, :variant, :bogus, nil])})
                ]),
              max_runs: 500
            ) do
        result = safe_call(fn -> Localize.Territory.display_name(territory, options) end)

        assert_no_crash(
          result,
          "Territory.display_name(#{inspect(territory)}, #{inspect(options)})"
        )
      end
    end
  end

  # ── Currency.display_name ───────────────────────────────────

  describe "Localize.Currency.display_name/2 adversarial" do
    property "valid and random currencies with random options" do
      check all(
              currency <-
                one_of([
                  member_of(@known_currencies),
                  atom(:alphanumeric),
                  string(:alphanumeric, min_length: 1, max_length: 10)
                ]),
              options <- options_gen(),
              max_runs: 500
            ) do
        result = safe_call(fn -> Localize.Currency.display_name(currency, options) end)

        assert_no_crash(
          result,
          "Currency.display_name(#{inspect(currency)}, #{inspect(options)})"
        )
      end
    end
  end
end
