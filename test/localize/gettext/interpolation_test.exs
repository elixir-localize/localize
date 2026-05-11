defmodule Localize.Gettext.InterpolationTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Localize.Gettext.Interpolation

  describe "runtime_interpolate/2" do
    test "formats a simple MF2 message with bindings" do
      assert {:ok, "Hello World!"} =
               Interpolation.runtime_interpolate(
                 "{{Hello {$name}!}}",
                 %{name: "World"}
               )
    end

    test "formats a message with no bindings" do
      assert {:ok, "Hello!"} =
               Interpolation.runtime_interpolate("{{Hello!}}", %{})
    end

    test "returns missing_bindings when bindings are absent" do
      result = Interpolation.runtime_interpolate("{{Hello {$name}!}}", %{})

      assert {:missing_bindings, _message, missing} = result
      assert :name in missing
    end

    test "converts atom keys to string keys for MF2" do
      assert {:ok, "Count: 42"} =
               Interpolation.runtime_interpolate(
                 "{{Count: {$count}}}",
                 %{count: 42}
               )
    end

    test "passes non-MF2 strings through unchanged and logs a warning" do
      # A library-safe failure mode: a gettext string that isn't valid
      # MF2 (e.g. dev-facing UI copy that happens to contain `{{…}}`)
      # must not crash the caller. Return the raw message and warn.
      input = "Smart indent inside {{…}}, .match, variants"

      {result, log} =
        with_log(fn -> Interpolation.runtime_interpolate(input, %{}) end)

      assert {:ok, ^input} = result
      assert log =~ "not valid MF2"
    end
  end

  describe "do_interpolate/2 (pre-parsed AST)" do
    test "formats a pre-parsed AST" do
      {:ok, parsed} = Localize.Message.Parser.parse("{{Hello {$name}!}}")

      assert {:ok, "Hello World!"} =
               Interpolation.do_interpolate(parsed, %{name: "World"})
    end

    test "returns missing_bindings for pre-parsed AST with missing bindings" do
      {:ok, parsed} = Localize.Message.Parser.parse("{{Hello {$name}!}}")

      assert {:missing_bindings, _partial, missing} =
               Interpolation.do_interpolate(parsed, %{})

      assert :name in missing
    end
  end

  describe "message_format/0" do
    test "returns icu-format" do
      assert "icu-format" = Interpolation.message_format()
    end
  end

  describe "expand_to_binary!/2" do
    test "expands a binary term" do
      assert "hello" = Interpolation.expand_to_binary!("hello", __ENV__)
    end

    test "raises for non-binary terms" do
      assert_raise ArgumentError, ~r/expand to strings at compile-time/, fn ->
        Interpolation.expand_to_binary!({:foo, [], nil}, __ENV__)
      end
    end
  end

  # Regression: `safe_to_atom/1` used to fall through to `String.to_atom/1`
  # when no atom existed for a binding name. That defeated the helper's
  # name and was an atom-table DOS vector if MF2 messages with unbound
  # bindings could be attacker-controlled. The helper now returns the
  # binary unchanged when no atom exists.
  describe "atom-table bound on missing-binding report" do
    test "unbound binding with no existing atom does not create an atom" do
      bogus = "zzz_binding_#{Elixir.System.unique_integer([:positive])}"
      message = "{{Hello {$" <> bogus <> "}!}}"

      assert {:missing_bindings, _msg, missing} =
               Interpolation.runtime_interpolate(message, %{})

      # The binding name appears in the missing list (as a binary when
      # no atom exists for it).
      assert bogus in missing
      assert nil == Localize.Utils.Helpers.existing_atom(bogus)
    end
  end
end
