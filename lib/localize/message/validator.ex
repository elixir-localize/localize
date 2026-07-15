defmodule Localize.Message.Validator do
  @moduledoc false

  # MF2 data-model validation (TR35 Part 9, "Data Model Errors"),
  # run over the parsed AST before interpretation:
  #
  #   * Duplicate Declaration — a variable declared more than once,
  #     including declaring a variable after it was implicitly
  #     declared by use in an earlier declaration, and a `.local`
  #     referring to itself.
  #
  #   * Duplicate Option Name — the same identifier on the left of
  #     more than one option in a single expression or markup.
  #
  #   * Duplicate Variant — the same key list (after NFC
  #     normalization of literal keys) on more than one variant.
  #
  # Variant Key Mismatch and Missing Fallback Variant are enforced
  # during match evaluation in `Localize.Message.Interpreter`.

  @type error ::
          {:duplicate_declaration, String.t()}
          | {:duplicate_option_name, String.t()}
          | {:duplicate_variant, String.t()}

  @spec validate(term()) :: :ok | {:error, error()}
  def validate(ast) when is_list(ast) do
    reduce_ok(ast, &validate_node/1)
  end

  def validate(ast) do
    validate_node(ast)
  end

  defp validate_node({:complex, declarations, body}) do
    with :ok <- validate_declarations(declarations),
         :ok <- reduce_ok(declarations, &validate_part_options/1) do
      validate_node(body)
    end
  end

  defp validate_node({:match, _selectors, variants}) do
    with :ok <- validate_variants(variants) do
      reduce_ok(variants, fn {:variant, _keys, pattern} -> validate_node(pattern) end)
    end
  end

  defp validate_node({:quoted_pattern, parts}) do
    reduce_ok(parts, &validate_part_options/1)
  end

  defp validate_node(part) do
    validate_part_options(part)
  end

  # ── Duplicate declarations ───────────────────────────────────────

  defp validate_declarations(declarations) do
    declarations
    |> Enum.reduce_while({MapSet.new(), MapSet.new()}, fn declaration, {declared, referenced} ->
      {name, expression_refs} = declaration_name_and_refs(declaration)

      cond do
        MapSet.member?(declared, name) ->
          {:halt, {:duplicate, name}}

        MapSet.member?(referenced, name) ->
          {:halt, {:duplicate, name}}

        local?(declaration) and MapSet.member?(expression_refs, name) ->
          {:halt, {:duplicate, name}}

        true ->
          {:cont, {MapSet.put(declared, name), MapSet.union(referenced, expression_refs)}}
      end
    end)
    |> case do
      {:duplicate, name} -> {:error, {:duplicate_declaration, name}}
      {_declared, _referenced} -> :ok
    end
  end

  defp declaration_name_and_refs({:input, {:expression, {:variable, name}, func, _attrs}}) do
    {name, expression_refs(nil, func)}
  end

  defp declaration_name_and_refs(
         {:local, {:variable, name}, {:expression, operand, func, _attrs}}
       ) do
    {name, expression_refs(operand, func)}
  end

  defp local?({:local, _variable, _expression}), do: true
  defp local?(_declaration), do: false

  defp expression_refs(operand, func) do
    operand_refs =
      case operand do
        {:variable, name} -> [name]
        _other -> []
      end

    option_refs =
      case func do
        {:function, _name, options} ->
          for {:option, _key, {:variable, name}} <- options, do: name

        _other ->
          []
      end

    MapSet.new(operand_refs ++ option_refs)
  end

  # ── Duplicate option names ───────────────────────────────────────

  defp validate_part_options({:input, expression}) do
    validate_part_options(expression)
  end

  defp validate_part_options({:local, _variable, expression}) do
    validate_part_options(expression)
  end

  defp validate_part_options({:expression, _operand, {:function, _name, options}, _attrs}) do
    check_duplicate_option_names(options)
  end

  defp validate_part_options({markup, _name, options, _attrs})
       when markup in [:markup_open, :markup_close, :markup_standalone] do
    check_duplicate_option_names(options)
  end

  defp validate_part_options(_part) do
    :ok
  end

  defp check_duplicate_option_names(options) do
    names = for {:option, name, _value} <- options, do: name

    case names -- Enum.uniq(names) do
      [] -> :ok
      [duplicate | _rest] -> {:error, {:duplicate_option_name, duplicate}}
    end
  end

  # ── Duplicate variants ───────────────────────────────────────────

  defp validate_variants(variants) do
    key_lists =
      Enum.map(variants, fn {:variant, keys, _pattern} -> Enum.map(keys, &normalize_key/1) end)

    case key_lists -- Enum.uniq(key_lists) do
      [] -> :ok
      [duplicate | _rest] -> {:error, {:duplicate_variant, display_keys(duplicate)}}
    end
  end

  # The catch-all key is kept distinct from a literal `*` key
  # (`|*|`), which is an ordinary literal.
  defp normalize_key(:catchall), do: :catchall
  defp normalize_key({:literal, value}), do: {:key, String.normalize(value, :nfc)}
  defp normalize_key({:number_literal, value}), do: {:key, value}

  defp display_keys(normalized_keys) do
    Enum.map_join(normalized_keys, " ", fn
      :catchall -> "*"
      {:key, value} -> value
    end)
  end

  # ── Helpers ──────────────────────────────────────────────────────

  defp reduce_ok(enumerable, fun) do
    Enum.reduce_while(enumerable, :ok, fn element, :ok ->
      case fun.(element) do
        :ok -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end
end
