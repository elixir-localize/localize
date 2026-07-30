defmodule Localize.Message.Validator do
  @moduledoc """
  Validates a parsed MF2 message against the data-model rules of
  TR35 Part 9, "Data Model Errors".

  `Localize.Message.Parser.parse/1` checks *syntax* only, so a
  syntactically valid message can still be semantically invalid — most
  commonly a `.local` declaration that reads the variable it declares.
  Parsing and validation are kept separate so tooling that must accept
  invalid input, such as a syntax highlighter, can parse without
  validating; everything that formats or serializes a message runs both:

      with {:ok, ast} <- Localize.Message.Parser.parse(message),
           :ok <- Localize.Message.Validator.validate(ast) do
        # syntax errors surface first, then data-model errors
      end

  """

  @doc """
  Validates a parsed MF2 message against the TR35 data-model rules.

  The rules checked are:

  * **Duplicate Declaration** — a variable declared more than once,
    including declaring a variable after it was implicitly declared by
    use in an earlier declaration, and a `.local` referring to itself.

  * **Duplicate Option Name** — the same identifier on the left of more
    than one option in a single expression or markup.

  * **Duplicate Variant** — the same key list (after NFC normalization
    of literal keys) on more than one variant.

  * **Missing Selector Annotation** — a selector that does not resolve,
    directly or transitively, to a declaration carrying a function.

  * **Variant Key Mismatch** — a variant whose key count differs from
    the number of selectors.

  * **Missing Fallback Variant** — a matcher with no variant whose keys
    are all `*`.

  ### Arguments

  * `ast` is a parsed message as returned by
    `Localize.Message.Parser.parse/1`.

  ### Returns

  * `:ok` if the message satisfies every data-model rule.

  * `{:error, {reason, detail}}` for the first violation found, where
    `detail` names the offending variable, option, or key list.

  ### Examples

      iex> {:ok, ast} = Localize.Message.Parser.parse(".input {$n :number}\\n.match $n\\n* {{ok}}")
      iex> Localize.Message.Validator.validate(ast)
      :ok

      iex> {:ok, ast} = Localize.Message.Parser.parse(".local $n = {$n :number}\\n.match $n\\n* {{no}}")
      iex> Localize.Message.Validator.validate(ast)
      {:error, {:duplicate_declaration, "n"}}

  """
  @type error ::
          {:duplicate_declaration, String.t()}
          | {:duplicate_option_name, String.t()}
          | {:duplicate_variant, String.t()}
          | {:missing_selector_annotation, String.t()}
          | {:variant_key_mismatch, String.t()}
          | {:missing_fallback_variant, String.t()}

  @spec validate(term()) :: :ok | {:error, error()}
  def validate(ast) when is_list(ast) do
    reduce_ok(ast, &validate_node(&1, []))
  end

  def validate(ast) do
    validate_node(ast, [])
  end

  # Declarations are carried down so a matcher can check that each of
  # its selectors resolves to an annotated declaration.
  defp validate_node({:complex, declarations, body}, _outer) do
    with :ok <- validate_declarations(declarations),
         :ok <- reduce_ok(declarations, &validate_part_options/1) do
      validate_node(body, declarations)
    end
  end

  defp validate_node({:match, selectors, variants}, declarations) do
    with :ok <- validate_selector_annotations(selectors, declarations),
         :ok <- validate_variant_arity(selectors, variants),
         :ok <- validate_fallback_variant(variants),
         :ok <- validate_variants(variants) do
      reduce_ok(variants, fn {:variant, _keys, pattern} ->
        validate_node(pattern, declarations)
      end)
    end
  end

  defp validate_node({:quoted_pattern, parts}, _declarations) do
    reduce_ok(parts, &validate_part_options/1)
  end

  defp validate_node(part, _declarations) do
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

  # ── Missing selector annotation ───────────────────────────────────
  #
  # A selector must resolve to a declaration carrying a function, either
  # directly (`.input {$n :number}`) or transitively through a chain of
  # unannotated locals (`.local $m = {$n}` where `$n` is annotated).
  # A selector with no declaration at all is likewise unannotated.

  defp validate_selector_annotations(selectors, declarations) do
    annotated = annotated_names(declarations)

    selectors
    |> Enum.find(fn {:variable, name} -> not MapSet.member?(annotated, name) end)
    |> case do
      nil -> :ok
      {:variable, name} -> {:error, {:missing_selector_annotation, name}}
    end
  end

  defp annotated_names(declarations) do
    Enum.reduce(declarations, MapSet.new(), &annotated_name/2)
  end

  defp annotated_name(
         {:input, {:expression, {:variable, name}, {:function, _name, _options}, _attrs}},
         annotated
       ) do
    MapSet.put(annotated, name)
  end

  defp annotated_name(
         {:local, {:variable, name}, {:expression, _operand, {:function, _n, _o}, _attrs}},
         annotated
       ) do
    MapSet.put(annotated, name)
  end

  # An unannotated local inherits its operand's annotation.
  defp annotated_name(
         {:local, {:variable, name}, {:expression, {:variable, source}, nil, _attrs}},
         annotated
       ) do
    if MapSet.member?(annotated, source), do: MapSet.put(annotated, name), else: annotated
  end

  defp annotated_name(_unannotated, annotated), do: annotated

  # ── Variant key arity and fallback ────────────────────────────────

  defp validate_variant_arity(selectors, variants) do
    expected = length(selectors)

    variants
    |> Enum.find(fn {:variant, keys, _pattern} -> length(keys) != expected end)
    |> case do
      nil ->
        :ok

      {:variant, keys, _pattern} ->
        {:error, {:variant_key_mismatch, display_keys(Enum.map(keys, &normalize_key/1))}}
    end
  end

  defp validate_fallback_variant(variants) do
    if Enum.any?(variants, fn {:variant, keys, _pattern} ->
         keys != [] and Enum.all?(keys, &(&1 == :catchall))
       end) do
      :ok
    else
      {:error, {:missing_fallback_variant, "*"}}
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
