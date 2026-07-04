defmodule Localize.Message.Sigils do
  @moduledoc """
  Implements sigils for ICU MessageFormat 2 messages.

  Two sigils are provided:

  * `~M` — validates and canonicalises an MF2 message at compile time.
    Useful for static messages that need a stable canonical form (for
    example, as keys in a translation table or seed data).

  * `~t` — compile-time translation sigil. Combines Gettext lookup with
    MF2 interpolation. Elixir-style `\#{expr}` interpolations become
    MF2 `{$name}` placeholders with bindings derived automatically from
    the interpolated expression. Requires the calling module to opt in
    via `use Localize.Message.Sigils, backend: MyApp.Gettext`.

  ## Compile-time validation

  Both sigils parse the message at compile time. A syntax error fails
  compilation and the raised `CompileError` points at the exact line
  and column of the error *inside the sigil body*, adjusted to the
  sigil's source location so editors can jump directly to the
  offending character (including inside multi-line heredoc sigils).

  ## Using `~t`

      defmodule MyAppWeb.HomeLive do
        use Localize.Message.Sigils,
          backend: MyApp.Gettext,
          sigils: [domain: "messages"]

        def render(assigns) do
          ~H\"""
          <h1>{~t"Hello, \#{@user.name}!"}</h1>
          \"""
        end
      end

  At compile time, `~t"Hello, \#{@user.name}!"` becomes:

      Gettext.Macros.dpgettext_with_backend(
        MyApp.Gettext,
        "messages",
        nil,
        "Hello, {$user_name}!",
        %{user_name: @user.name}
      )

  The msgid stored in the `.po` file is the MF2-canonical form with
  `{$name}` placeholders, so translators can use MF2 features
  (selectors, formatters, markup) per-locale.

  ## Gettext backend requirements

  The configured backend MUST use MF2-aware interpolation:

      defmodule MyApp.Gettext do
        use Gettext.Backend,
          otp_app: :my_app,
          interpolation: Localize.Gettext.Interpolation
      end

  Without this, `{$name}` placeholders are returned literally because
  the default Gettext interpolation only recognises `%{name}`.

  ## Binding key derivation

  Binding names are derived from the interpolated expression:

  * `\#{name}` — variable → `name`.

  * `\#{@count}` — Phoenix assign → `count`.

  * `\#{fruit.name}` — dot access → `fruit_name`.

  * `\#{String.upcase(x)}` — remote call → `string_upcase`.

  * `\#{key = expr}` — explicit key. Always overrides automatic
    derivation. Use this for collisions or complex expressions.

  Identical expressions interpolated twice share a single binding.
  Different expressions that derive the same key raise a compile error.

  """

  @doc ~S"""
  Handles the sigil `~M` for ICU MessageFormat 2 message strings.

  It returns a canonically formatted string without interpolations and
  without escape characters, except for the escaping of the closing
  sigil character itself.

  A canonically formatted string is pretty-printed by default returning
  a potentially multi-line string. This is intended to produce a result
  which is easier to comprehend for translators.

  ### Modifiers

  * `p` (default) — pretty-print the message with indentation.

  * `u` — return a non-pretty-printed (compact) string.

  ### Examples

      iex> import Localize.Message.Sigils
      iex> ~M(An ICU message)
      "An ICU message"

  """
  defmacro sigil_M({:<<>>, meta, [message]}, modifiers) when is_binary(message) do
    options = Localize.Message.Sigils.options(modifiers)

    canonical_message =
      compile_time_parse_or_raise!(message, options, __CALLER__, meta, "~M")

    quote do
      unquote(canonical_message)
    end
  end

  @doc false
  defmacro sigil_m({:<<>>, meta, [message]}, modifiers) when is_binary(message) do
    options = Localize.Message.Sigils.options(modifiers)
    message = Macro.unescape_string(message)

    canonical_message =
      compile_time_parse_or_raise!(message, options, __CALLER__, meta, "~m")

    quote do
      unquote(canonical_message)
    end
  end

  defmacro sigil_m({:<<>>, meta, pieces}, modifiers) do
    options = Localize.Message.Sigils.options(modifiers)
    message = {:<<>>, meta, unescape_tokens(pieces)}

    quote do
      Localize.Message.canonical_message!(unquote(message), unquote(options))
    end
  end

  @doc ~S"""
  Handles the sigil `~t` for compile-time MF2 translation.

  Rewrites Elixir `#{expr}` interpolations as MF2 `{$name}` placeholders
  with bindings derived from the interpolated expressions. The resulting
  msgid is canonicalised and routed through `Gettext`, which performs
  both the translation lookup and the MF2 interpolation (via the
  configured `Localize.Gettext.Interpolation` module).

  The calling module must opt in with:

      use Localize.Message.Sigils, backend: MyApp.Gettext

  Modifiers are reserved for a future release and are rejected at
  compile time.

  See the `Localize.Message.Sigils` moduledoc for binding-derivation
  rules and a full example.
  """
  defmacro sigil_t({:<<>>, meta, pieces}, modifiers) do
    unless modifiers == [] do
      raise CompileError,
        file: __CALLER__.file,
        line: caller_line(meta, __CALLER__),
        description:
          "modifiers are not yet supported on ~t sigils; got #{inspect(List.to_string(modifiers))}"
    end

    config = fetch_config!(__CALLER__, meta)
    {msgid, bindings} = extract_interpolations!(pieces, __CALLER__, meta)

    canonical =
      compile_time_parse_or_raise!(msgid, [pretty: false], __CALLER__, meta, "~t")

    build_translate_ast(canonical, bindings, config)
  end

  @doc false
  def options([pretty]) when pretty in [?u, ?U] do
    [pretty: false]
  end

  def options(_modifiers) do
    [pretty: true]
  end

  @doc """
  Configures the calling module to use the `~t` sigil.

  ### Options

  * `:backend` — the Gettext backend module. Required.

  * `:sigils` — a keyword list of sigil-level options:

      * `:domain` — default Gettext domain. The default is `:default`,
        which resolves to the backend's configured default domain.

      * `:context` — default Gettext message context. The default is `nil`.

  ### Examples

      use Localize.Message.Sigils,
        backend: MyApp.Gettext,
        sigils: [domain: "messages"]

  """
  defmacro __using__(opts) do
    backend =
      case Keyword.fetch(opts, :backend) do
        {:ok, backend} ->
          backend

        :error ->
          raise CompileError,
            file: __CALLER__.file,
            line: __CALLER__.line,
            description:
              "use Localize.Message.Sigils requires a :backend option naming a Gettext backend module"
      end

    sigil_opts = Keyword.get(opts, :sigils, [])
    domain = Keyword.get(sigil_opts, :domain, :default)
    context = Keyword.get(sigil_opts, :context, nil)

    config = %{backend: backend, domain: domain, context: context}

    quote do
      @__localize_message_sigils_config__ unquote(Macro.escape(config))
      require Gettext.Macros
      import Localize.Message.Sigils
    end
  end

  # Parse + canonicalise at compile time. On success, return the
  # canonical string. On failure, raise a `CompileError` whose `:line`
  # points at the actual error location inside the sigil body (sigil
  # start line + MF2 error line - 1) so IDEs jump to the right spot.
  @doc false
  def compile_time_parse_or_raise!(message, options, caller, meta, sigil_name \\ "~M") do
    Localize.Message.canonical_message!(message, options)
  rescue
    error in Localize.ParseError ->
      reraise_as_compile_error(error, caller, meta, sigil_name)
  end

  @spec reraise_as_compile_error(
          Localize.ParseError.t(),
          Macro.Env.t(),
          keyword(),
          String.t()
        ) :: no_return()
  defp reraise_as_compile_error(%Localize.ParseError{} = error, caller, meta, sigil_name) do
    error_line =
      case error.line do
        nil -> caller_line(meta, caller)
        n when is_integer(n) -> caller_line(meta, caller) + n - 1
      end

    column = error.column || 1

    raise CompileError,
      file: caller.file,
      line: error_line,
      description:
        "invalid MF2 message in #{sigil_name} sigil at column #{column}: #{Exception.message(error)}"
  end

  @doc false
  def caller_line(meta, caller) do
    Keyword.get(meta, :line, caller.line)
  end

  defp unescape_tokens(tokens) do
    Enum.map(tokens, fn
      token when is_binary(token) -> Macro.unescape_string(token)
      other -> other
    end)
  end

  # --- ~t helpers ---------------------------------------------------------

  @doc false
  def fetch_config!(caller, meta) do
    case Module.get_attribute(caller.module, :__localize_message_sigils_config__) do
      nil ->
        raise CompileError,
          file: caller.file,
          line: caller_line(meta, caller),
          description:
            "~t sigil used without `use Localize.Message.Sigils, backend: …`. " <>
              "Add the `use` statement to module #{inspect(caller.module)} to configure a Gettext backend."

      config ->
        config
    end
  end

  # Walk the sigil pieces (a mix of literal binaries and `#{expr}`
  # interpolation AST), replace each interpolation with a `{$name}`
  # MF2 placeholder, and accumulate `{key, value_ast}` bindings in
  # source order.
  @doc false
  def extract_interpolations!(pieces, caller, meta) do
    {ids_rev, bindings_rev, _seen} =
      Enum.reduce(pieces, {[], [], %{}}, fn
        piece, {ids, bindings, seen} when is_binary(piece) ->
          {[Macro.unescape_string(piece) | ids], bindings, seen}

        {:"::", _, [{{:., _, [Kernel, :to_string]}, _, [expr]}, {:binary, _, _}]},
        {ids, bindings, seen} ->
          accumulate_interpolation(expr, ids, bindings, seen, caller, meta)

        other, {_ids, _bindings, _seen} ->
          raise CompileError,
            file: caller.file,
            line: caller_line(meta, caller),
            description: "unsupported expression in ~t sigil: #{Macro.to_string(other)}"
      end)

    msgid = ids_rev |> Enum.reverse() |> IO.iodata_to_binary()
    {msgid, Enum.reverse(bindings_rev)}
  end

  defp accumulate_interpolation(expr, ids, bindings, seen, caller, meta) do
    {key, value_ast} = derive_binding!(expr, caller, meta)
    placeholder = "{$" <> Atom.to_string(key) <> "}"

    normalized_ast = strip_meta(value_ast)
    seen = check_duplicate_binding!(seen, key, normalized_ast, caller, meta)
    bindings = put_new_binding(bindings, key, value_ast)

    {[placeholder | ids], bindings, seen}
  end

  defp check_duplicate_binding!(seen, key, normalized_ast, caller, meta) do
    case Map.fetch(seen, key) do
      :error ->
        Map.put(seen, key, normalized_ast)

      {:ok, existing_ast} when existing_ast == normalized_ast ->
        seen

      {:ok, _existing_ast} ->
        raise CompileError,
          file: caller.file,
          line: caller_line(meta, caller),
          description:
            "binding `#{key}` is derived from two different expressions in the ~t sigil. " <>
              "Use `#{key}1 = expr1` and `#{key}2 = expr2` to give them distinct names."
    end
  end

  defp put_new_binding(bindings, key, value_ast) do
    if Enum.any?(bindings, fn {existing_key, _} -> existing_key == key end) do
      bindings
    else
      [{key, value_ast} | bindings]
    end
  end

  # Explicit `key = expr` always wins.
  defp derive_binding!({:=, _, [{key, _, ctx}, value_expr]}, _caller, _meta)
       when is_atom(key) and (is_atom(ctx) or is_nil(ctx)) do
    {key, value_expr}
  end

  # Phoenix assign: @name → name.
  defp derive_binding!({:@, _, [{name, _, ctx}]} = expr, _caller, _meta)
       when is_atom(name) and (is_atom(ctx) or is_nil(ctx)) do
    {name, expr}
  end

  # HEEx rewrites `@foo` to `assigns.foo` before the t/1 macro sees it.
  # Drop the `assigns` prefix so `#{@user.name}` and `#{@count}` derive
  # the same names a developer would naturally write.
  #
  # Single-level: assigns.foo → foo
  defp derive_binding!(
         {{:., _, [{:assigns, _, ctx}, key]}, _, []} = expr,
         _caller,
         _meta
       )
       when is_atom(key) and (is_atom(ctx) or is_nil(ctx)) do
    {key, expr}
  end

  # Multi-level chain rooted at `assigns` (HEEx-injected from @assign).
  # E.g. assigns.user.address.city → user_address_city.
  # Matches when the receiver is itself a call AST (i.e. another dot).
  defp derive_binding!(
         {{:., _, [{{:., _, [_, _]}, _, []} = parent, key]}, _, []} = expr,
         caller,
         meta
       )
       when is_atom(key) do
    case strip_assigns_prefix(parent) do
      {:ok, parts} ->
        all = parts ++ [key]
        joined = Enum.map_join(all, "_", &Atom.to_string/1)
        {String.to_atom(joined), expr}

      :error ->
        raise CompileError,
          file: caller.file,
          line: caller_line(meta, caller),
          description:
            "cannot derive a binding name for `#{Macro.to_string(expr)}` " <>
              "(nested dot access not rooted at `assigns`). " <>
              "Use `key = expr` to name the binding explicitly."
    end
  end

  # Dot access on a simple parent: parent.child → parent_child.
  defp derive_binding!(
         {{:., _, [{parent, _, parent_ctx}, key]}, _, []} = expr,
         _caller,
         _meta
       )
       when is_atom(parent) and is_atom(key) and (is_atom(parent_ctx) or is_nil(parent_ctx)) do
    {:"#{parent}_#{key}", expr}
  end

  # Dot access on an explicit `@assign.field` (sigil source path).
  # Derives the same flat key as `assigns.parent.key` does in HEEx.
  defp derive_binding!(
         {{:., _, [{:@, _, [{parent, _, _}]}, key]}, _, []} = expr,
         _caller,
         _meta
       )
       when is_atom(parent) and is_atom(key) do
    {:"#{parent}_#{key}", expr}
  end

  # Remote call on an alias: Mod.fun(...) → mod_fun.
  defp derive_binding!(
         {{:., _, [{:__aliases__, _, parts}, fun]}, _, _args} = expr,
         _caller,
         _meta
       )
       when is_atom(fun) and is_list(parts) do
    mod_name = parts |> List.last() |> Atom.to_string() |> Macro.underscore()
    {:"#{mod_name}_#{fun}", expr}
  end

  # Remote call on a resolved module atom: Mod.fun(...) → mod_fun.
  defp derive_binding!({{:., _, [mod, fun]}, _, _args} = expr, _caller, _meta)
       when is_atom(mod) and is_atom(fun) do
    mod_name =
      mod
      |> Atom.to_string()
      |> String.split(".")
      |> List.last()
      |> Macro.underscore()

    {:"#{mod_name}_#{fun}", expr}
  end

  # Simple variable.
  defp derive_binding!({name, _, ctx} = expr, _caller, _meta)
       when is_atom(name) and (is_atom(ctx) or is_nil(ctx)) do
    {name, expr}
  end

  defp derive_binding!(expr, caller, meta) do
    raise CompileError,
      file: caller.file,
      line: caller_line(meta, caller),
      description:
        "cannot derive a binding name for `#{Macro.to_string(expr)}` in ~t sigil. " <>
          "Use `key = expr` to name the binding explicitly."
  end

  # Walk an AST chain rooted at the `assigns` variable (HEEx's
  # expansion of `@`). Returns {:ok, parts} where parts is the list of
  # keys traversed after `assigns` in order, or :error when the chain
  # isn't rooted at `assigns`.
  defp strip_assigns_prefix({:assigns, _, ctx}) when is_atom(ctx) or is_nil(ctx) do
    {:ok, []}
  end

  defp strip_assigns_prefix({{:., _, [parent, key]}, _, []}) when is_atom(key) do
    case strip_assigns_prefix(parent) do
      {:ok, parts} -> {:ok, parts ++ [key]}
      :error -> :error
    end
  end

  defp strip_assigns_prefix(_), do: :error

  defp strip_meta(ast) do
    Macro.prewalk(ast, fn
      {form, _meta, args} -> {form, [], args}
      other -> other
    end)
  end

  defp build_translate_ast(canonical_msgid, bindings, config) do
    %{backend: backend, domain: domain, context: context} = config

    bindings_map_ast =
      {:%{}, [], Enum.map(bindings, fn {key, value_ast} -> {key, value_ast} end)}

    quote do
      Gettext.Macros.dpgettext_with_backend(
        unquote(backend),
        unquote(domain),
        unquote(context),
        unquote(canonical_msgid),
        unquote(bindings_map_ast)
      )
    end
  end
end
