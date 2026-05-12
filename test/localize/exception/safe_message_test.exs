defmodule Localize.Exception.SafeMessageTest do
  use ExUnit.Case, async: true

  # A binding whose value isn't JSON-encodable (functions can't be
  # serialised to JSON). The NIF formatter path encodes bindings as
  # JSON before crossing the NIF boundary, so this is the simplest
  # realistic way to force a raise from inside the formatter pipeline.
  defp hostile_binding, do: fn -> nil end

  # `Localize.Exception.safe_message/3` is the wrapper every exception's
  # `message/1` callback uses in place of `Gettext.dpgettext/5`. The
  # narrow contract is: it must return a string, never raise — even
  # when the formatter pipeline raises on a bound value.

  describe "safe_message/3" do
    test "returns the formatted message on the happy path" do
      result =
        Localize.Exception.safe_message(
          "locale",
          "Locale {$locale} is unknown",
          locale: ":xx"
        )

      assert is_binary(result)
      assert result =~ ":xx"
    end

    test "falls back to the msgid when the formatter raises on a binding" do
      # The MF2 NIF pipeline `:json.encode`-s bindings before crossing
      # the NIF boundary; a function can't be JSON-encoded and would
      # otherwise propagate as a raise out of `Exception.message/1`.
      result =
        Localize.Exception.safe_message(
          "locale",
          "Value is {$value}",
          value: hostile_binding()
        )

      assert is_binary(result)
    end

    test "returns a string when bindings are missing for the msgid" do
      # The msgid references {$missing} but no binding is supplied.
      # Gettext's interpolation adapter degrades gracefully; safe_message
      # forwards that string-or-msgid result without raising.
      result = Localize.Exception.safe_message("locale", "Hello {$missing}", [])

      assert is_binary(result)
    end
  end

  describe "Exception.message/1 resilience" do
    test "produces a string for every fixture exception even with a hostile binding" do
      exceptions = [
        Localize.UnknownLocaleError.exception(locale_id: hostile_binding()),
        Localize.UnknownCurrencyError.exception(currency: hostile_binding()),
        Localize.InvalidValueError.exception(
          value: hostile_binding(),
          expected: :integer,
          context: :test
        )
      ]

      for exception <- exceptions do
        assert is_binary(Exception.message(exception)),
               "Exception.message/1 must return a string for #{inspect(exception.__struct__)}"
      end
    end
  end
end
