defmodule Localize.Gettext.InterpolationTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Localize.Gettext.Interpolation

  doctest Localize.Gettext.Interpolation

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

  describe "runtime_interpolate/2 — skip sentinel and format failures" do
    test "the skip-interpolation sentinel returns the message unchanged" do
      message = "{{Hello {$name}!}}"
      sentinel = Interpolation.skip_interpolation_sentinel()

      assert Interpolation.runtime_interpolate(message, sentinel) == {:ok, message}
    end

    test "a formatting failure returns the message unchanged and logs a warning" do
      # `:number` cannot format the string "abc"; the FormatError is
      # swallowed so a bad translation cannot crash the caller.
      message = "{{Num {$n :number}}}"

      {result, log} =
        with_log(fn -> Interpolation.runtime_interpolate(message, %{n: "abc"}) end)

      assert result == {:ok, message}
      assert log =~ "format failed"
    end

    test "accepts keyword-list bindings" do
      assert {:ok, "Hello World!"} =
               Interpolation.runtime_interpolate("{{Hello {$name}!}}", name: "World")
    end

    test "accepts string-keyed map bindings" do
      assert {:ok, "Hello World!"} =
               Interpolation.runtime_interpolate("{{Hello {$name}!}}", %{"name" => "World"})
    end

    test "accepts string-keyed tuple-list bindings" do
      assert {:ok, "Hello World!"} =
               Interpolation.runtime_interpolate("{{Hello {$name}!}}", [{"name", "World"}])
    end
  end

  describe "compile_interpolate/3 (compile-time AST)" do
    defmodule CompiledFixture do
      require Localize.Gettext.Interpolation

      def hello(bindings) do
        Localize.Gettext.Interpolation.compile_interpolate(
          :translation,
          "{{Hello {$name}!}}",
          bindings
        )
      end
    end

    test "interpolates bindings against the compile-time parsed AST" do
      assert CompiledFixture.hello(%{name: "World"}) == {:ok, "Hello World!"}
    end

    test "reports missing bindings with a partial message" do
      assert CompiledFixture.hello(%{}) == {:missing_bindings, "Hello !", [:name]}
    end

    test "the skip-interpolation sentinel bypasses MF2 evaluation" do
      sentinel = Localize.Gettext.Interpolation.skip_interpolation_sentinel()
      assert CompiledFixture.hello(sentinel) == {:ok, "{{Hello {$name}!}}"}
    end

    test "an invalid MF2 message raises ArgumentError at compile time" do
      error =
        assert_raise ArgumentError, fn ->
          Code.eval_string("""
          defmodule BadCompiledFixture do
            require Localize.Gettext.Interpolation

            def bad(bindings) do
              Localize.Gettext.Interpolation.compile_interpolate(:translation, "bad {", bindings)
            end
          end
          """)
        end

      assert Exception.message(error) =~ "could not parse MF2 message"
    end
  end

  describe "expand_to_binary!/2 with binary-piece AST" do
    test "joins a <<>> AST whose pieces are all binaries" do
      assert Interpolation.expand_to_binary!({:<<>>, [], ["Hello ", "World"]}, __ENV__) ==
               "Hello World"
    end

    test "raises when a <<>> AST contains non-binary pieces" do
      pieces = [{:"::", [], [{:name, [], nil}, {:binary, [], nil}]}]

      assert_raise ArgumentError, ~r/expand to strings at compile-time/, fn ->
        Interpolation.expand_to_binary!({:<<>>, [], pieces}, __ENV__)
      end
    end
  end
end
