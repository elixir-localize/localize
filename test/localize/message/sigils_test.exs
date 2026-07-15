defmodule Localize.Message.SigilsTest do
  use ExUnit.Case, async: true

  import Localize.Message.Sigils

  doctest Localize.Message.Sigils

  describe "sigil_M/2 at compile time" do
    test "valid single-line message compiles and returns canonical form" do
      assert ~M(Hello {$name}) == "Hello {$name}"
    end

    test "valid multi-line message compiles" do
      message = ~M"""
      .input {$count :number}
      .match $count
      1 {{one item}}
      * {{other items}}
      """

      assert is_binary(message)
      assert message =~ ".input"
      assert message =~ ".match"
    end

    test "invalid message raises at compile time with file, line, and column" do
      error =
        assert_raise CompileError, fn ->
          Code.eval_string("""
          import Localize.Message.Sigils
          ~M(Hello {unclosed)
          """)
        end

      # The exception message is built by Elixir's CompileError and
      # embeds the description we raised with.
      assert Exception.message(error) =~ "invalid MF2 message in ~M sigil"
      assert Exception.message(error) =~ "column"
    end

    test "column in compile error points inside the sigil body" do
      # Syntax error at the `{` on column 7 of the MF2 input.
      error =
        assert_raise CompileError, fn ->
          Code.eval_string("""
          import Localize.Message.Sigils
          ~M(Hello {broken)
          """)
        end

      msg = Exception.message(error)
      # The parser reports column relative to the MF2 source; for a
      # single-line sigil that maps directly to the message column.
      assert msg =~ ~r/column \d+/
    end
  end

  describe "sigil_t/2" do
    defmodule Fixture do
      use Localize.Message.Sigils, backend: Localize.Gettext

      @user_id 42

      def static, do: ~t"Hello, world!"
      def with_var(name), do: ~t"Hello, #{name}!"
      # `@name` interpolation has the same AST shape whether `@name` is a
      # plain module attribute or a Phoenix assign — both reach the
      # sigil as `{:@, _, [{:name, _, _}]}`. Using a module attribute
      # keeps this test free of a Phoenix dependency.
      def with_module_attribute, do: ~t"User #{@user_id}"
      def with_dot_access(user), do: ~t"Hello, #{user.name}!"
      def with_remote_call(text), do: ~t"Code is #{String.upcase(text)}"
      def with_explicit_key(value), do: ~t"Total: #{total = value * 2}"
      def with_repeated_var(name), do: ~t"#{name} is #{name}"
    end

    test "static message has no bindings and round-trips through gettext + MF2" do
      assert Fixture.static() == "Hello, world!"
    end

    test "interpolated variable is rewritten as {$name} placeholder" do
      assert Fixture.with_var("Kip") == "Hello, Kip!"
    end

    test "@name interpolation (Phoenix-assign-shaped AST) derives binding from the name" do
      assert Fixture.with_module_attribute() == "User 42"
    end

    test "dot access derives parent_key binding" do
      assert Fixture.with_dot_access(%{name: "Kip"}) == "Hello, Kip!"
    end

    test "remote call derives mod_fun binding" do
      assert Fixture.with_remote_call("hi") == "Code is HI"
    end

    test "explicit `key = expr` overrides automatic derivation" do
      assert Fixture.with_explicit_key(5) == "Total: 10"
    end

    test "the same expression repeated produces a single binding" do
      assert Fixture.with_repeated_var("Kip") == "Kip is Kip"
    end

    test "modifiers are rejected" do
      error =
        assert_raise CompileError, fn ->
          Code.eval_string("""
          defmodule Bad do
            use Localize.Message.Sigils, backend: Localize.Gettext
            def go, do: ~t"hello"x
          end
          """)
        end

      assert Exception.message(error) =~ "modifiers are not yet supported"
    end

    test "use without :backend raises" do
      error =
        assert_raise CompileError, fn ->
          Code.eval_string("""
          defmodule MissingBackend do
            use Localize.Message.Sigils
          end
          """)
        end

      assert Exception.message(error) =~ ":backend option"
    end

    test "~t without `use` raises a clear compile error" do
      error =
        assert_raise CompileError, fn ->
          Code.eval_string("""
          defmodule NoUse do
            import Localize.Message.Sigils
            def go, do: ~t"hello"
          end
          """)
        end

      assert Exception.message(error) =~ "without `use Localize.Message.Sigils"
    end

    test "conflicting bindings for the same derived key raise" do
      # Both `String.upcase/1` calls derive the key `:string_upcase` but
      # the value ASTs differ (different arguments), so the macro must
      # raise rather than silently keep the first binding.
      error =
        assert_raise CompileError, fn ->
          Code.eval_string("""
          defmodule Conflict do
            use Localize.Message.Sigils, backend: Localize.Gettext
            def go(a, b), do: ~t"\#{String.upcase(a)} and \#{String.upcase(b)}"
          end
          """)
        end

      msg = Exception.message(error)
      assert msg =~ "binding"
      assert msg =~ "two different expressions"
    end

    test "invalid MF2 in ~t raises at compile time with sigil name in message" do
      error =
        assert_raise CompileError, fn ->
          Code.eval_string("""
          defmodule BadMF2 do
            use Localize.Message.Sigils, backend: Localize.Gettext
            def go, do: ~t"Hello {unclosed"
          end
          """)
        end

      assert Exception.message(error) =~ "invalid MF2 message in ~t sigil"
    end
  end

  describe "sigil_M/2 and sigil_m/2 modifiers" do
    test "u modifier returns the compact canonical form" do
      assert ~M(.input {$c :number} {{{$c}}})u == ".input {$c :number}\n{{{$c}}}"
    end

    test "~m canonicalises a static message at compile time" do
      assert ~m(Hello   {$name}) == "Hello   {$name}"
    end

    test "~m unescapes string escapes before parsing" do
      assert ~m(Tab\tseparated) == "Tab\tseparated"
    end

    test "~m with interpolation canonicalises at runtime" do
      name = "name"
      assert ~m(Hello {$#{name}}) == "Hello {$name}"
    end

    test "~m with interpolation raises at runtime for invalid MF2" do
      variable = "{oops"

      assert_raise Localize.ParseError, fn ->
        ~m(Hello #{variable})
      end
    end

    test "options/1 maps the u modifier to pretty: false" do
      assert Localize.Message.Sigils.options(~c"u") == [pretty: false]
      assert Localize.Message.Sigils.options(~c"U") == [pretty: false]
      assert Localize.Message.Sigils.options([]) == [pretty: true]
    end
  end

  describe "sigil_t/2 — assigns-rooted derivation" do
    defmodule AssignsFixture do
      use Localize.Message.Sigils, backend: Localize.Gettext

      @user %{name: "Kip"}

      # HEEx rewrites `@count` to `assigns.count` before the sigil
      # macro sees it; these fixtures exercise that AST shape without
      # a Phoenix dependency.
      def single_level(assigns), do: ~t"Count: #{assigns.count}"
      def multi_level(assigns), do: ~t"City: #{assigns.user.address.city}"
      def attribute_dot_access, do: ~t"Hello, #{@user.name}!"
      def atom_module_call, do: ~t"Pi is #{:math.pi()}"
    end

    test "assigns.key derives the bare key name" do
      assert AssignsFixture.single_level(%{count: 3}) == "Count: 3"
    end

    test "assigns.a.b.c chain derives an underscore-joined key" do
      assigns = %{user: %{address: %{city: "Tokyo"}}}
      assert AssignsFixture.multi_level(assigns) == "City: Tokyo"
    end

    test "@attribute.field derives parent_key like assigns access" do
      assert AssignsFixture.attribute_dot_access() == "Hello, Kip!"
    end

    test "remote call on an atom module derives mod_fun" do
      # An unannotated numeric operand formats with the locale-aware
      # :number default (at most three fraction digits, matching the
      # MF2 implicit formatting behaviour and Intl.NumberFormat).
      assert AssignsFixture.atom_module_call() =~ "Pi is 3.142"
    end

    test "nested dot access not rooted at assigns raises" do
      error =
        assert_raise CompileError, fn ->
          Code.eval_string("""
          defmodule NotAssignsRooted do
            use Localize.Message.Sigils, backend: Localize.Gettext
            def go(x), do: ~t"Value: \#{x.a.b}"
          end
          """)
        end

      assert Exception.message(error) =~ "not rooted at `assigns`"
    end

    test "underivable expression raises with a hint to use key = expr" do
      error =
        assert_raise CompileError, fn ->
          Code.eval_string("""
          defmodule Underivable do
            use Localize.Message.Sigils, backend: Localize.Gettext
            def go, do: ~t"Sum: \#{1 + 2}"
          end
          """)
        end

      assert Exception.message(error) =~ "cannot derive a binding name"
    end
  end

  describe "sigil_t/2 — domain and context options" do
    defmodule DomainFixture do
      use Localize.Message.Sigils,
        backend: Localize.Gettext,
        sigils: [domain: "localize", context: "test"]

      def greeting(name), do: ~t"Hello, #{name}!"
    end

    test "messages route through the configured domain and context" do
      assert DomainFixture.greeting("Kip") == "Hello, Kip!"
    end
  end
end
