defmodule Localize.Message.Namespace do
  @moduledoc """
  Behaviour for MF2 function-namespace handlers.

  A namespace handler owns every function in one custom namespace.
  A reference to `:acme:price` routes to the handler registered for
  the namespace `"acme"`, which then dispatches on the local name
  `"price"`. Registering a single handler for the namespace is the
  alternative to registering each flattened `"acme:price"`,
  `"acme:weight"` name separately through
  `Localize.Message.Function`.

  Namespaced function names are parsed by the MF2 parser (the
  `:namespace:name` syntax) and resolved after the built-in
  functions. Built-in functions are authoritative: a namespace
  handler is consulted only for a namespace that has no built-in
  owner.

  ## Application-level registration

      # config/config.exs
      config :localize, :mf2_namespaces, %{
        "acme" => MyApp.AcmeFunctions
      }

  ## Per-call registration

  Pass a `:namespaces` map in the options to
  `Localize.Message.format/3`; per-call handlers take precedence
  over application-level handlers for the same namespace:

      Localize.Message.format(
        "{$item :acme:price currency=USD}",
        %{"item" => item},
        locale: :en,
        namespaces: %{"acme" => MyApp.AcmeFunctions}
      )

  ## Reserved namespaces

  The single-letter namespaces `l` and `u` are reserved and never
  route to a user handler:

  * `l` is Localize's own namespace (`:l:inflect`, `:l:pronoun`,
    `:l:quantify`), handled by built-in functions.

  * `u` is the CLDR-managed namespace defined by the MF2
    specification for options (and, in a future release, possibly
    functions).

  Registering a handler for a reserved namespace has no effect, and
  a reserved-namespace function that no built-in handles is an
  *Unknown Function* error — which the specification permits, since
  implementations are not required to support every namespace.

  ## Implementing a handler

      defmodule MyApp.AcmeFunctions do
        @behaviour Localize.Message.Namespace

        @impl true
        def format("price", value, func_opts, options) do
          locale = Keyword.get(options, :locale)
          MyApp.Price.to_string(value, locale: locale, currency: func_opts["currency"])
        end

        def format(name, _value, _func_opts, _options) do
          {:error, {:unknown_function, ":acme:" <> name}}
        end
      end

  """

  @doc """
  Formats `value` for the namespaced function whose local name is
  `name`.

  ### Arguments

  * `name` is the local function name within the namespace (the
    part after the colon — `"price"` for `:acme:price`).

  * `value` is the resolved operand from the MF2 expression.

  * `func_opts` is a map of the MF2 function options with string
    keys (for example `%{"currency" => "USD"}`); values are strings
    unless written as a number literal.

  * `options` is the interpreter's keyword list, which includes at
    least `:locale` and `:bindings`.

  ### Returns

  * `{:ok, formatted_string}` on success.

  * `{:error, reason}` on failure, where `reason` is a string, or
    `{:error, {:unknown_function, name}}` when the handler does not
    implement the requested local name.

  """
  @callback format(
              name :: String.t(),
              value :: term(),
              func_opts :: map(),
              options :: Keyword.t()
            ) ::
              {:ok, String.t()} | {:error, String.t() | {:unknown_function, String.t()}}
end
