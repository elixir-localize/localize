defmodule Localize.Credo.ExistingAtom do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      A public function matches a value it is given against data it has
      read, or validates it — it does not ask the VM whether an atom of
      that name exists. `Helpers.existing_atom/1`,
      `String.to_existing_atom/1` and `:erlang.binary_to_existing_atom/2`
      answer for the whole VM: the atom exists once something has read
      the data that holds it, and not before, so a lookup gated on them
      answers differently on a fresh VM than on one that has already
      formatted a date. `"en-US"` took the world's hour cycle,
      `"ussystem"` was an unknown measurement system and `"TA"` had no
      currency, each until some other call had loaded the data (#70).

      Only a `def` or a `defmacro` is read, because a public function is
      where the caller's value arrives. A private helper may probe a map
      it already holds — `Map.get(rules, existing_atom(name))` is sound
      when `rules` is the map whose keys interned the atoms — and a key
      composed from validated atoms is sound anywhere.

      The sound idioms are to read the data and match the value against
      its keys as strings, as `Localize.validate_measurement_system/1`
      does; to route the value through a validator that does so, as
      `Localize.Currency.territory_currencies/1` does with
      `Localize.validate_territory/1`; or to take the value as the atom
      the data already has. A public function that must probe the VM
      says why with `# credo:disable-for-next-line
      Localize.Credo.ExistingAtom`.

      Credo's `Warning.UnsafeToAtom` covers `String.to_atom/1` and its
      kin, which create atoms; this check covers the calls that only
      look for one.
      """
    ]

  # The forms whose first argument is a head, not a call. A public
  # definition's body is read and its head is not, so a function named
  # `existing_atom/1` is not reported by its own head; a private
  # definition is not read at all, because the rule is about the value a
  # public function is given.
  @public [:def, :defmacro]
  @private [:defp, :defmacrop]

  # The attributes that declare a type rather than make a call, so that
  # `@spec existing_atom(String.t()) :: atom() | nil` is not a call.
  @declarations [:spec, :type, :typep, :opaque, :callback, :macrocallback]

  # The calls that ask the VM for an atom rather than make one, as the
  # alias they are called through and the function name. A bare
  # `existing_atom/1` is an imported call and is matched separately.
  @probes [
    {[:Helpers], :existing_atom},
    {[:Localize, :Utils, :Helpers], :existing_atom},
    {[:String], :to_existing_atom},
    {[:List], :to_existing_atom},
    {:erlang, :binary_to_existing_atom},
    {:erlang, :list_to_existing_atom}
  ]

  @doc false
  @impl true
  def run(%SourceFile{} = source_file, params) do
    ctx = Context.build(source_file, params, __MODULE__)

    source_file
    |> SourceFile.source()
    |> Code.string_to_quoted(columns: true, file: source_file.filename)
    |> issues(ctx)
  end

  defp issues({:ok, ast}, ctx) do
    {_ast, ctx} = Macro.prewalk(ast, ctx, &walk/2)
    ctx.issues
  end

  defp issues({:error, _reason}, ctx) do
    ctx.issues
  end

  defp walk({head, meta, [_head, body]}, ctx) when head in @public do
    {{head, meta, [nil, body]}, ctx}
  end

  defp walk({head, meta, [_head, _body]}, ctx) when head in @private do
    {{head, meta, [nil, nil]}, ctx}
  end

  defp walk({:@, meta, [{declaration, _meta, _args}]}, ctx) when declaration in @declarations do
    {{:@, meta, [nil]}, ctx}
  end

  # A remote call, in call form `Helpers.existing_atom(value)`, in pipe form
  # `value |> Helpers.existing_atom()`, or captured `&Helpers.existing_atom/1`.
  defp walk({{:., _dot_meta, [target, function]}, meta, args} = ast, ctx)
       when is_atom(function) and is_list(args) do
    if probe?(target, function) do
      {ast, put_issue(ctx, issue_for(ctx, meta, call_name(target, function)))}
    else
      {ast, ctx}
    end
  end

  defp walk({:existing_atom, meta, [_value]} = ast, ctx) do
    {ast, put_issue(ctx, issue_for(ctx, meta, "existing_atom"))}
  end

  defp walk(ast, ctx) do
    {ast, ctx}
  end

  defp probe?({:__aliases__, _meta, aliases}, function) do
    {aliases, function} in @probes
  end

  defp probe?(:erlang, function) do
    {:erlang, function} in @probes
  end

  defp probe?(_target, _function) do
    false
  end

  defp call_name({:__aliases__, _meta, aliases}, function) do
    Enum.map_join(aliases, ".", &Atom.to_string/1) <> "." <> Atom.to_string(function)
  end

  defp call_name(:erlang, function) do
    ":erlang." <> Atom.to_string(function)
  end

  defp issue_for(ctx, meta, name) do
    format_issue(
      ctx,
      message:
        "Match the value against data read first, or validate it, rather than ask the VM " <>
          "for its atom with `#{name}`.",
      trigger: name,
      line_no: meta[:line],
      column: meta[:column]
    )
  end
end
