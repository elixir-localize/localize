defmodule Localize.Credo.ErrorTuple do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      An error is returned as `{:error, exception}`: an exception struct
      that is machine readable and gives a localized message. An error
      built with an atom or a string, such as `{:error, :invalid_date}`,
      is neither.

      Matching an atom another library returns, such as
      `{:error, :incompatible_calendars} -> ...` from `Date.convert/2`, is
      not reported: only an error tuple that is built is.

      A site that must build an atom, because a contract outside this
      library requires one, says so with
      `# credo:disable-for-next-line Localize.Credo.ErrorTuple` and a
      comment giving the reason.
      """
    ]

  # The forms whose first argument is a pattern or a head, not a value
  # that is built.
  @heads [:def, :defp, :defmacro, :defmacrop]

  @doc false
  @impl true
  def run(%SourceFile{} = source_file, params) do
    ctx = Context.build(source_file, params, __MODULE__)

    source_file
    |> SourceFile.source()
    |> Code.string_to_quoted(
      columns: true,
      literal_encoder: &{:ok, {:__block__, &2, [&1]}},
      file: source_file.filename
    )
    |> issues(ctx)
  end

  defp issues({:ok, ast}, ctx) do
    {_ast, ctx} = Macro.prewalk(ast, ctx, &walk/2)
    ctx.issues
  end

  defp issues({:error, _reason}, ctx), do: ctx.issues

  # The patterns and heads are dropped, so the walk sees only what is
  # built.
  defp walk({:->, meta, [_patterns, body]}, ctx), do: {{:->, meta, [[], body]}, ctx}
  defp walk({:=, meta, [_pattern, value]}, ctx), do: {{:=, meta, [nil, value]}, ctx}
  defp walk({:<-, meta, [_pattern, value]}, ctx), do: {{:<-, meta, [nil, value]}, ctx}

  defp walk({head, meta, [_head, body]}, ctx) when head in @heads,
    do: {{head, meta, [nil, body]}, ctx}

  defp walk(
         {:__block__, meta, [{{:__block__, _, [:error]}, {:__block__, _, [reason]}}]} = ast,
         ctx
       )
       when is_atom(reason) or is_binary(reason) do
    {ast, put_issue(ctx, issue_for(ctx, meta, reason))}
  end

  defp walk(ast, ctx), do: {ast, ctx}

  defp issue_for(ctx, meta, reason) do
    format_issue(
      ctx,
      message:
        "Return `{:error, exception}`, not `{:error, #{inspect(reason)}}`: " <>
          "an error is an exception struct.",
      trigger: "{:error, #{inspect(reason)}}",
      line_no: meta[:line],
      column: meta[:column]
    )
  end
end
