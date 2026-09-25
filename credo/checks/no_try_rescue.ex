defmodule Localize.Credo.NoTryRescue do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [allowed_try_after: []],
    explanations: [
      check: """
      Localize returns `{:ok, value}` or `{:error, exception}`; it does not
      raise and rescue. A `try`, and a function body's `rescue`, `catch`,
      `else` or `after`, are reported, with two agreed exceptions:

      * A `rescue` of `ArgumentError` whose only expression is a call to
        `String.to_existing_atom/1` or `:erlang.binary_to_existing_atom/1,2`
        on a variable or literal — the one conversion with no form that
        returns an error.

      * A `try`/`after` in a function listed in `:allowed_try_after`, whose
        cleanup is part of its documented behaviour.

      A call that raises on bad data and has no variant returning a tagged
      tuple runs through `Localize.Utils.Helpers.run_isolated/1`, and a test
      restores state with `on_exit/1`.
      """,
      params: [
        allowed_try_after:
          "The functions, as `{module, name, arity}` tuples, whose `try`/`after` is agreed."
      ]
    ]

  @definitions [:def, :defp, :defmacro, :defmacrop]
  @try_clauses [:rescue, :catch, :else, :after]

  @doc false
  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    context = Context.build(source_file, params, __MODULE__, %{scope: []})

    {_ast, context} =
      source_file
      |> SourceFile.ast()
      |> Macro.traverse(context, &enter/2, &leave/2)

    context.issues
  end

  # The enclosing modules and function are kept on `:scope` as the walk
  # enters and leaves them, because `:allowed_try_after` names functions.
  defp enter({:defmodule, _meta, [{:__aliases__, _, parts}, _body]} = ast, context) do
    {ast, %{context | scope: [{:module, parts} | context.scope]}}
  end

  defp enter({kind, meta, [head, body]} = ast, context)
       when kind in @definitions and is_list(body) do
    context = %{context | scope: [function_scope(head) | context.scope]}

    if Enum.any?(@try_clauses, &Keyword.has_key?(body, &1)),
      do: {ast, check_try(context, body, meta, Atom.to_string(kind))},
      else: {ast, context}
  end

  defp enter({:try, meta, [clauses]} = ast, context) when is_list(clauses) do
    {ast, check_try(context, clauses, meta, "try")}
  end

  defp enter(ast, context), do: {ast, context}

  defp leave({:defmodule, _meta, [{:__aliases__, _, _parts}, _body]} = ast, context) do
    {ast, %{context | scope: tl(context.scope)}}
  end

  defp leave({kind, _meta, [_head, body]} = ast, context)
       when kind in @definitions and is_list(body) do
    {ast, %{context | scope: tl(context.scope)}}
  end

  defp leave(ast, context), do: {ast, context}

  defp function_scope({:when, _meta, [head | _guards]}), do: function_scope(head)

  defp function_scope({name, _meta, arguments}) when is_atom(name) and is_list(arguments),
    do: {:function, name, length(arguments)}

  defp function_scope({name, _meta, context}) when is_atom(name) and is_atom(context),
    do: {:function, name, 0}

  defp function_scope(_head), do: {:function, nil, nil}

  defp check_try(context, clauses, meta, trigger) do
    cond do
      existing_atom_rescue?(clauses) ->
        context

      after_only?(clauses) and allowed_try_after?(context) ->
        context

      after_only?(clauses) ->
        put_issue(context, issue(context, meta, trigger, after_message()))

      true ->
        put_issue(context, issue(context, meta, trigger, rescue_message()))
    end
  end

  defp existing_atom_rescue?(do: body, rescue: rescue_clauses) do
    existing_atom_call?(body) and Enum.all?(rescue_clauses, &rescues_argument_error?/1)
  end

  defp existing_atom_rescue?(_clauses), do: false

  defp existing_atom_call?(
         {{:., _, [{:__aliases__, _, [:String]}, :to_existing_atom]}, _, [argument]}
       ),
       do: plain?(argument)

  defp existing_atom_call?({{:., _, [:erlang, :binary_to_existing_atom]}, _, [_ | _] = arguments})
       when length(arguments) <= 2,
       do: Enum.all?(arguments, &plain?/1)

  defp existing_atom_call?(_expression), do: false

  # A variable or a literal, so nothing in the argument itself can raise.
  defp plain?({name, _meta, context}) when is_atom(name) and is_atom(context), do: true
  defp plain?(literal) when is_atom(literal) or is_binary(literal), do: true
  defp plain?(_argument), do: false

  defp rescues_argument_error?({:->, _meta, [[pattern], _body]}), do: argument_error?(pattern)
  defp rescues_argument_error?(_clause), do: false

  defp argument_error?({:__aliases__, _, [:ArgumentError]}), do: true
  defp argument_error?({:in, _, [_variable, {:__aliases__, _, [:ArgumentError]}]}), do: true
  defp argument_error?({:in, _, [_variable, [{:__aliases__, _, [:ArgumentError]}]]}), do: true
  defp argument_error?(_pattern), do: false

  defp after_only?(clauses), do: Enum.sort(Keyword.keys(clauses)) == [:after, :do]

  defp allowed_try_after?(%{scope: scope, params: params}) do
    case List.keyfind(scope, :function, 0) do
      {:function, name, arity} ->
        module =
          for {:module, parts} <- Enum.reverse(scope), part <- parts, do: Atom.to_string(part)

        Enum.any?(params.allowed_try_after, fn {allowed_module, allowed_name, allowed_arity} ->
          Module.split(allowed_module) == module and allowed_name == name and
            allowed_arity == arity
        end)

      nil ->
        false
    end
  end

  defp rescue_message do
    "Return `{:ok, _}` or `{:error, _}` instead of rescuing; run a call that has no " <>
      "tagged variant through `Localize.Utils.Helpers.run_isolated/1`."
  end

  defp after_message do
    "Restore state with `on_exit/1` or straight-line code instead of `try`/`after`."
  end

  defp issue(context, meta, trigger, message) do
    format_issue(context,
      message: message,
      trigger: trigger,
      line_no: meta[:line],
      column: meta[:column]
    )
  end
end
