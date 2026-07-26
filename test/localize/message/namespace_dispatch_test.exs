defmodule Localize.Message.NamespaceDispatchTest do
  # Phase A: first-class MF2 function-namespace dispatch. A custom
  # namespace routes to one `Localize.Message.Namespace` handler that
  # dispatches on the local name; reserved namespaces (`l`, `u`) never
  # route to a user handler; the flat-string custom registry keeps
  # working for back-compat.
  use ExUnit.Case, async: false

  alias Localize.Message

  defmodule AcmeNamespace do
    @behaviour Localize.Message.Namespace

    @impl true
    def format("shout", value, _func_opts, _options) do
      {:ok, String.upcase(to_string(value))}
    end

    def format("echo", value, func_opts, _options) do
      {:ok, to_string(value) <> (func_opts["suffix"] || "")}
    end

    def format(name, _value, _func_opts, _options) do
      {:error, {:unknown_function, ":acme:" <> name}}
    end
  end

  defmodule OtherNamespace do
    @behaviour Localize.Message.Namespace

    @impl true
    def format(_name, _value, _func_opts, _options) do
      {:ok, "other"}
    end
  end

  defmodule FlatPriceFunction do
    @behaviour Localize.Message.Function

    @impl true
    def format(value, _func_opts, _options) do
      {:ok, "flat:" <> to_string(value)}
    end
  end

  defp unknown_function?({:error, %Localize.FormatError{reason: :unknown_function}}), do: true
  defp unknown_function?(_other), do: false

  describe "per-call :namespaces registration" do
    test "routes a namespaced function to its handler by local name" do
      assert {:ok, "HELLO"} =
               Message.format("{$w :acme:shout}", %{w: "hello"}, locale: :en, namespaces: ns())
    end

    test "passes function options through to the handler" do
      assert {:ok, "hello!"} =
               Message.format(
                 "{$w :acme:echo suffix=|!|}",
                 %{w: "hello"},
                 locale: :en,
                 namespaces: ns()
               )
    end

    test "a local name the handler does not implement is an Unknown Function" do
      assert unknown_function?(
               Message.format("{$w :acme:whisper}", %{w: "hi"}, locale: :en, namespaces: ns())
             )
    end
  end

  describe "application-level :mf2_namespaces registration" do
    setup do
      Application.put_env(:localize, :mf2_namespaces, %{"acme" => AcmeNamespace})
      on_exit(fn -> Application.delete_env(:localize, :mf2_namespaces) end)
    end

    test "routes via the application config" do
      assert {:ok, "HELLO"} = Message.format("{$w :acme:shout}", %{w: "hello"}, locale: :en)
    end

    test "per-call handlers take precedence over application-level ones" do
      assert {:ok, "other"} =
               Message.format(
                 "{$w :acme:shout}",
                 %{w: "hello"},
                 locale: :en,
                 namespaces: %{"acme" => OtherNamespace}
               )
    end
  end

  describe "reserved namespaces" do
    test "u: never routes to a user handler even when one is registered" do
      assert unknown_function?(
               Message.format("{$w :u:shout}", %{w: "hi"},
                 locale: :en,
                 namespaces: %{"u" => AcmeNamespace}
               )
             )
    end

    test "l: never routes to a user handler (built-ins own the namespace)" do
      assert unknown_function?(
               Message.format("{$w :l:shout}", %{w: "hi"},
                 locale: :en,
                 namespaces: %{"l" => AcmeNamespace}
               )
             )
    end

    test "built-in l:inflect is unaffected by a registered l handler" do
      assert {:ok, "lights"} =
               Message.format("{$w :l:inflect grammaticalNumber=plural}", %{w: "light"},
                 locale: :en,
                 namespaces: %{"l" => AcmeNamespace}
               )
    end
  end

  describe "back-compat and unknown namespaces" do
    test "a flat-string :functions key with a namespace still resolves" do
      assert {:ok, "flat:widget"} =
               Message.format(
                 "{$w :acme:price}",
                 %{w: "widget"},
                 locale: :en,
                 functions: %{"acme:price" => FlatPriceFunction}
               )
    end

    test "a flat-string exact-name match takes precedence over the namespace handler" do
      assert {:ok, "flat:widget"} =
               Message.format(
                 "{$w :acme:price}",
                 %{w: "widget"},
                 locale: :en,
                 functions: %{"acme:price" => FlatPriceFunction},
                 namespaces: %{"acme" => OtherNamespace}
               )
    end

    test "an unregistered namespace is an Unknown Function" do
      assert unknown_function?(Message.format("{$w :acme:shout}", %{w: "hi"}, locale: :en))
    end
  end

  defp ns, do: %{"acme" => AcmeNamespace}
end
