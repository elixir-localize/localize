if Localize.Nif.available?() do
  defmodule Localize.Message.NifBackendTest do
    @moduledoc """
    Tests for `Localize.Message.format/3` with `backend: :nif` that
    assert NIF-specific behaviour. These tests are skipped if the NIF
    is not available (requires the NIF to be compiled with
    LOCALIZE_NIF=true). They format with `bidi: :none`, since ICU before
    79 has no bidi isolation and a message that asks for it is formatted
    by the interpreter instead.

    """

    use ExUnit.Case, async: true

    alias Localize.Message

    @moduletag :nif

    describe "format/3 with backend: :nif" do
      test "parse errors surface as :invalid_message_format" do
        assert {:error, %Localize.ParseError{reason: :invalid_message_format}} =
                 Message.format("bad {", %{}, backend: :nif, bidi: :none)
      end

      test "unbound variable used as a function option value is a BindError" do
        message = "{{N {$x :number minimumFractionDigits=$digits}}}"

        assert {:error, %Localize.BindError{unbound: ["digits"]}} =
                 Message.format(message, %{"x" => 1}, backend: :nif, bidi: :none)
      end

      test "bound function option variables format through ICU" do
        message = "{{N {$x :number minimumFractionDigits=$digits}}}"

        assert Message.format(message, %{"x" => 1, "digits" => 2}, backend: :nif, bidi: :none) ==
                 {:ok, "N 1.00"}
      end

      test "an invalid locale is rejected before formatting" do
        assert {:error, %Localize.InvalidLocaleError{}} =
                 Message.format("{{Hi}}", %{}, backend: :nif, bidi: :none, locale: "not a locale")
      end

      # Regression: `:json.encode/1` raised on a binding JSON cannot hold,
      # and ICU misread ones it could — a struct arrived as an object, `nil`
      # as "nil". A message with such a binding now goes to the interpreter.
      test "bindings ICU cannot take are formatted by the interpreter" do
        values = [
          ~U[2026-09-26 10:30:00Z],
          ~N[2026-09-26 10:30:00],
          ~T[10:30:00],
          ~D[2026-09-26],
          Decimal.new("1234.5678"),
          Localize.Unit.new!(3, "meter"),
          Bitwise.bsl(1, 70),
          nil,
          ~c"hi",
          [1, 2],
          {1, 2},
          self(),
          <<255>>
        ]

        for message <- ["{$x}", "{$x :string}", "{$x :number}", "{$x :datetime}"],
            value <- values do
          assert Message.format(message, %{"x" => value}, backend: :nif, bidi: :none) ==
                   Message.format(message, %{"x" => value}, backend: :elixir, bidi: :none),
                 "#{message} with #{inspect(value)}"
        end
      end

      test "strings keep their control characters and floats their value" do
        assert Message.format("{$x}", %{"x" => "a\u0001b\bc\fd"}, backend: :nif, bidi: :none) ==
                 {:ok, "a\u0001b\bc\fd"}

        assert Message.format("{$x :number}", %{"x" => 1.0e20}, backend: :nif, bidi: :none) ==
                 {:ok, "100,000,000,000,000,000,000"}
      end
    end
  end
end
