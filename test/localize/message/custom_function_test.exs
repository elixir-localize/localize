defmodule Localize.Message.CustomFunctionTest do
  use ExUnit.Case, async: false

  # async: false because some tests mutate :mf2_functions app config

  alias Localize.Message

  # ── Test function modules ──────────────────────────────────────

  defmodule UppercaseFunction do
    @behaviour Localize.Message.Function

    @impl true
    def format(value, _func_opts, _options) do
      {:ok, value |> Kernel.to_string() |> String.upcase()}
    end
  end

  defmodule ReverseFunction do
    @behaviour Localize.Message.Function

    @impl true
    def format(value, _func_opts, _options) do
      {:ok, value |> Kernel.to_string() |> String.reverse()}
    end
  end

  defmodule OptionEchoFunction do
    @behaviour Localize.Message.Function

    @impl true
    def format(value, func_opts, options) do
      locale = Keyword.get(options, :locale)
      # MF2 option keys are atomized when an existing atom matches
      # (e.g. "style" → :style), otherwise kept as strings. Look
      # up both forms for robustness.
      style = Map.get(func_opts, :style) || Map.get(func_opts, "style") || "default"
      {:ok, "#{value}|locale=#{locale}|style=#{style}"}
    end
  end

  defmodule ErrorFunction do
    @behaviour Localize.Message.Function

    @impl true
    def format(_value, _func_opts, _options) do
      {:error, "custom function failed intentionally"}
    end
  end

  setup do
    # Clean up app config after each test
    original = Application.get_env(:localize, :mf2_functions)

    on_exit(fn ->
      if original do
        Application.put_env(:localize, :mf2_functions, original)
      else
        Application.delete_env(:localize, :mf2_functions)
      end
    end)

    :ok
  end

  describe "per-call :functions option (Option A)" do
    test "dispatches to a custom function module" do
      assert {:ok, "HELLO"} =
               Message.format(
                 "{$val :upper}",
                 %{"val" => "hello"},
                 functions: %{"upper" => UppercaseFunction}
               )
    end

    test "passes MF2 options through to the custom function" do
      assert {:ok, result} =
               Message.format(
                 ~S({$val :echo style=fancy}),
                 %{"val" => "test"},
                 locale: :en,
                 functions: %{"echo" => OptionEchoFunction}
               )

      assert result =~ "test|locale="
      assert result =~ "style=fancy"
    end

    test "custom function can return an error" do
      {:ok, parsed} = Localize.Message.Parser.parse("{$val :fail}")

      assert {:format_error, {:formatter_failed, detail}} =
               Localize.Message.Interpreter.format_list(
                 parsed,
                 %{"val" => "x"},
                 functions: %{"fail" => ErrorFunction}
               )

      assert detail =~ "custom function failed"
    end

    test "multiple custom functions can coexist" do
      functions = %{
        "upper" => UppercaseFunction,
        "reverse" => ReverseFunction
      }

      assert {:ok, "HELLO"} =
               Message.format("{$val :upper}", %{"val" => "hello"}, functions: functions)

      assert {:ok, "olleh"} =
               Message.format("{$val :reverse}", %{"val" => "hello"}, functions: functions)
    end

    test "custom function does not interfere with built-in functions" do
      assert {:ok, "1,234"} =
               Message.format(
                 "{$n :number}",
                 %{"n" => 1234},
                 locale: :en,
                 functions: %{"upper" => UppercaseFunction}
               )
    end
  end

  describe "application-level :mf2_functions config (Option B)" do
    test "dispatches to an app-config registered function" do
      Application.put_env(:localize, :mf2_functions, %{"upper" => UppercaseFunction})

      assert {:ok, "WORLD"} =
               Message.format("{$val :upper}", %{"val" => "world"})
    end

    test "app-config function receives MF2 options" do
      Application.put_env(:localize, :mf2_functions, %{"echo" => OptionEchoFunction})

      assert {:ok, result} =
               Message.format(
                 ~S({$val :echo style=bold}),
                 %{"val" => "test"},
                 locale: :de
               )

      assert result =~ "style=bold"
      assert result =~ "locale=de"
    end
  end

  describe "dispatch order" do
    test "per-call :functions takes precedence over app config" do
      Application.put_env(:localize, :mf2_functions, %{"custom" => ReverseFunction})

      # Per-call should win — uppercase, not reverse
      assert {:ok, "HELLO"} =
               Message.format(
                 "{$val :custom}",
                 %{"val" => "hello"},
                 functions: %{"custom" => UppercaseFunction}
               )
    end

    test "built-in functions take precedence over custom functions of the same name" do
      # :number is built-in — a custom :number should NOT override it
      # because the built-in clause matches first in the pattern match
      Application.put_env(:localize, :mf2_functions, %{"number" => UppercaseFunction})

      assert {:ok, "1,234"} =
               Message.format("{$n :number}", %{"n" => 1234}, locale: :en)
    end

    test "unknown function with no registry entry falls back to to_string" do
      Application.delete_env(:localize, :mf2_functions)

      assert {:ok, "hello"} =
               Message.format("{$val :nonexistent}", %{"val" => "hello"})
    end
  end

  describe "custom function in complex messages" do
    test "works inside a quoted pattern" do
      message = """
      .input {$name :upper}
      {{Hello, {$name}!}}\
      """

      assert {:ok, "Hello, ALICE!"} =
               Message.format(
                 message,
                 %{"name" => "alice"},
                 functions: %{"upper" => UppercaseFunction}
               )
    end
  end
end
