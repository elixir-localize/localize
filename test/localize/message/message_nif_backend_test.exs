if Localize.Nif.available?() do
  defmodule Localize.Message.NifBackendTest do
    @moduledoc """
    Tests for `Localize.Message.format/3` with `backend: :nif` that
    assert NIF-specific behaviour. These tests are skipped if the NIF
    is not available (requires the NIF to be compiled with
    LOCALIZE_NIF=true).

    """

    use ExUnit.Case, async: true

    alias Localize.Message

    @moduletag :nif

    describe "format/3 with backend: :nif" do
      test "parse errors surface as :invalid_message_format" do
        assert {:error, %Localize.ParseError{reason: :invalid_message_format}} =
                 Message.format("bad {", %{}, backend: :nif)
      end

      test "unbound variable used as a function option value is a BindError" do
        message = "{{N {$x :number minimumFractionDigits=$digits}}}"

        assert {:error, %Localize.BindError{unbound: ["digits"]}} =
                 Message.format(message, %{"x" => 1}, backend: :nif)
      end

      test "bound function option variables format through ICU" do
        message = "{{N {$x :number minimumFractionDigits=$digits}}}"

        assert Message.format(message, %{"x" => 1, "digits" => 2}, backend: :nif) ==
                 {:ok, "N 1.00"}
      end

      test "an invalid locale is rejected before formatting" do
        assert {:error, %Localize.InvalidLocaleError{}} =
                 Message.format("{{Hi}}", %{}, backend: :nif, locale: "not a locale")
      end
    end
  end
end
