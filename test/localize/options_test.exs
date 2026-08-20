defmodule Localize.OptionsTest do
  @moduledoc """
  An option key a function does not recognise is almost always a typo, and
  ignoring it silently turns the typo into a wrong-looking result with nothing
  to trace it to. These cover the rejection and the suggestion.

  Option *values* are validated by the function that uses them; only keys are
  checked here.

  """

  use ExUnit.Case, async: true

  doctest Localize.Options

  alias Localize.UnknownOptionError

  describe "rejecting an unknown option key" do
    test "the mistake that motivated this: a misspelled :currency" do
      # Previously {:ok, "1,234.5"} — a request for currency formatting that
      # silently produced a bare number.
      assert {:error, %UnknownOptionError{option: :currancy}} =
               Localize.Number.to_string(1234.5, currancy: :USD)
    end

    test "across every leaf formatter" do
      unit = Localize.Unit.new!(3, "meter")

      assert {:error, %UnknownOptionError{}} = Localize.Number.to_string(1, nonsense: 1)

      assert {:error, %UnknownOptionError{}} =
               Localize.Date.to_string(~D[2026-03-22], nonsense: 1)

      assert {:error, %UnknownOptionError{}} = Localize.Time.to_string(~T[14:30:00], nonsense: 1)

      assert {:error, %UnknownOptionError{}} =
               Localize.DateTime.to_string(~N[2026-03-22 14:30:00], nonsense: 1)

      assert {:error, %UnknownOptionError{}} = Localize.Unit.to_string(unit, nonsense: 1)
    end

    test "the error names the nearest option when there is one" do
      {:error, exception} = Localize.Number.to_string(1234.5, currancy: :USD)

      assert exception.suggestion == :currency
      assert Exception.message(exception) =~ "Did you mean :currency?"
    end

    test "and offers none when nothing is close" do
      {:error, exception} = Localize.Number.to_string(1234.5, wildly_unrelated: 1)

      assert exception.suggestion == nil
      refute Exception.message(exception) =~ "Did you mean"
    end

    test "the accepted options travel with the error, for the caller to inspect" do
      {:error, exception} = Localize.Date.to_string(~D[2026-03-22], nonsense: 1)

      assert :format in exception.known
      assert :locale in exception.known
    end
  end

  describe "not breaking what already worked" do
    test "correct options still format" do
      assert {:ok, "$1,234.50"} = Localize.Number.to_string(1234.5, currency: :USD)
      assert {:ok, "1.234,5"} = Localize.Number.to_string(1234.5, locale: :de)
      assert {:ok, "March 22, 2026"} = Localize.Date.to_string(~D[2026-03-22], format: :long)
    end

    test "no options at all is the common case and stays free" do
      assert {:ok, _} = Localize.Number.to_string(1234.5)
      assert {:ok, _} = Localize.Date.to_string(~D[2026-03-22])
    end

    test "an option a sibling forwards is still accepted" do
      # `Localize.List` forwards everything but its own keys to whatever
      # formats the elements, so a sibling's option legitimately arrives at a
      # leaf. Rejecting those would break composition.
      assert {:ok, _} = Localize.List.to_string([1234.5, 2345.6], fractional_digits: 2)
    end

    test "an interval still honours its own axis selectors" do
      assert {:ok, _} =
               Localize.Interval.to_string(~T[12:00:00], ~T[14:00:00],
                 time_format: "HH:mm",
                 locale: :ja
               )
    end
  end

  describe "validate_keys/2 directly" do
    test "an empty list is accepted without inspecting the known set" do
      assert {:ok, []} = Localize.Options.validate_keys([], MapSet.new([]))
    end

    test "options are returned unchanged when every key is known" do
      known = MapSet.new([:locale, :format])
      options = [locale: :en, format: :long]

      assert {:ok, ^options} = Localize.Options.validate_keys(options, known)
    end

    test "the first unknown key is the one reported" do
      known = MapSet.new([:locale])

      assert {:error, %UnknownOptionError{option: :first}} =
               Localize.Options.validate_keys([first: 1, second: 2], known)
    end
  end
end
