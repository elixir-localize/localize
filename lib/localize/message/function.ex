defmodule Localize.Message.Function do
  @moduledoc """
  Behaviour for custom MF2 formatting functions.

  Implement this behaviour to add domain-specific formatting
  functions to `Localize.Message.format/3`. Custom functions can
  be registered in two ways:

  ## Per-call registration

  Pass a `:functions` map in the options to `Localize.Message.format/3`:

      Localize.Message.format(
        "{$name :personName format=long}",
        %{"name" => person},
        locale: :en,
        functions: %{"personName" => MyApp.PersonNameFunction}
      )

  ## Application-level registration

      # config/config.exs
      config :localize, :mf2_functions, %{
        "personName" => MyApp.PersonNameFunction,
        "money"      => MyApp.MoneyFunction
      }

  Application-level functions are available to all
  `Localize.Message.format/3` calls without passing `:functions`
  on every call. Per-call functions take precedence over
  application-level functions of the same name, which in turn
  take precedence over built-in functions.

  ## Implementing a custom function

      defmodule MyApp.PersonNameFunction do
        @behaviour Localize.Message.Function

        @impl true
        def format(value, func_opts, options) do
          locale = Keyword.get(options, :locale)

          # MF2 function options arrive as strings from untrusted message
          # input. Map them through an explicit case rather than calling
          # `String.to_atom/1` on raw values, which would grow the atom
          # table on every distinct attacker-supplied string.
          format =
            case func_opts["format"] do
              "short" -> :short
              "long" -> :long
              "full" -> :full
              _ -> :medium
            end

          MyApp.PersonName.to_string(value, locale: locale, format: format)
        end
      end

  The `format/3` callback receives:

  * `value` — the resolved operand from the MF2 expression.

  * `func_opts` — a map of MF2 function options parsed from the
    expression (e.g. `%{"format" => "long", "formality" => "formal"}`).
    Keys and values are strings.

  * `options` — the interpreter's keyword list, which includes at
    least `:locale` and `:bindings`.

  """

  @doc """
  Formats `value` using the MF2 function options and interpreter
  options.

  ### Arguments

  * `value` is the resolved operand from the MF2 expression.

  * `func_opts` is a map of string key/value pairs from the MF2
    function options (e.g. `%{"format" => "long"}`).

  * `options` is the interpreter's keyword list (contains at least
    `:locale`).

  ### Returns

  * `{:ok, formatted_string}` on success.

  * `{:error, reason}` on failure, where `reason` is a string
    describing the error.

  """
  @callback format(value :: term(), func_opts :: map(), options :: Keyword.t()) ::
              {:ok, String.t()} | {:error, String.t()}
end
