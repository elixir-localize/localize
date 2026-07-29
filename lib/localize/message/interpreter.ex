defmodule Localize.Message.Interpreter do
  # Interprets a MessageFormat 2 AST and produces formatted output.
  #
  # The AST is produced by `Localize.Message.Parser` and uses tuples like
  # `{:text, "..."}`, `{:expression, operand, function, attrs}`,
  # `{:complex, declarations, body}`, `{:match, selectors, variants}`, etc.
  #
  # ## Supported MF2 Functions
  #
  # The following functions are available in MF2 expressions:
  #
  # ### Stable (per MF2 specification)
  #
  # * `:number` — format a number using locale-aware decimal formatting.
  #
  # * `:integer` — format a number as an integer (truncates fractional part).
  #
  # * `:string` — format a value as a string (identity for strings).
  #
  # * `:currency` — format a number as a currency amount. Requires a
  #   `currency` option (ISO 4217 code).
  #
  # * `:percent` — format a number as a percentage.
  #
  # ### Draft
  #
  # * `:date` — format a date using CLDR date patterns.
  #
  # * `:time` — format a time using CLDR time patterns.
  #
  # * `:datetime` — format a datetime using CLDR datetime patterns.
  #
  # * `:unit` — format a number with a unit of measure.
  #
  # ### Localize extensions (not in the MF2 specification)
  #
  # * `:list` — format a list operand as a locale-aware
  #   conjunction or disjunction by delegating to
  #   `Localize.List.to_string/2`. Each element is itself
  #   formatted via `Localize.Chars`, so a list of dates,
  #   numbers, units, etc. picks up the message's locale and
  #   any forwarded options. Accepts a `style` (or `type`)
  #   option whose value is one of `"and"`, `"and-short"`,
  #   `"and-narrow"`, `"or"`, `"or-short"`, `"or-narrow"`,
  #   `"unit"`, `"unit-short"`, `"unit-narrow"`. The default
  #   is `"and"` (the CLDR `:standard` list style).
  #
  # ## Custom function registry
  #
  # When a function name is not matched by any built-in function
  # above, the interpreter looks for a custom function module in
  # two places (in order of precedence):
  #
  # 1. The per-call `:functions` option on `Localize.Message.format/3`.
  # 2. The application-level `config :localize, :mf2_functions` map.
  #
  # Custom function modules must implement the
  # `Localize.Message.Function` behaviour. See that module's
  # documentation for details and examples.
  #
  # If no custom function is found, the interpreter falls back to
  # `Kernel.to_string/1` on the operand value.
  @moduledoc false

  # MF2 `signDisplay` values mapped to the `:sign_display` option of
  # `Localize.Number.to_string/2`.
  @mf2_sign_displays %{
    "auto" => :auto,
    "always" => :always,
    "exceptZero" => :except_zero,
    "negative" => :negative,
    "never" => :never
  }

  # MF2 `trailingZeroDisplay` and `roundingPriority` values mapped to
  # the corresponding `Localize.Number.to_string/2` options.
  @mf2_trailing_zero_displays %{
    "auto" => :auto,
    "stripIfInteger" => :strip_if_integer
  }

  @mf2_rounding_priorities %{
    "auto" => :auto,
    "morePrecision" => :more_precision,
    "lessPrecision" => :less_precision
  }

  # ── Public API ─────────────────────────────────────────────────

  @doc """
  Formats a parsed MF2 AST with the given bindings.

  ### Arguments

  * `ast` is a parsed MF2 message AST as returned by
    `Localize.Message.Parser.parse/1`.

  * `bindings` is a map or keyword list of variable bindings.
    String keys are NFC-normalized to match parser output.

  * `options` is a keyword list of options including `:locale`.

  ### Returns

  * `{:ok, iolist, bound, unbound}` on success, where `bound` is
    the list of variable names that were resolved and `unbound` is
    empty.

  * `{:error, iolist, bound, unbound}` when one or more variables
    could not be resolved. The `iolist` contains a partial result.

  """
  @typedoc """
  Structured payload carried inside a `{:format_error, payload}` tuple.

  * `{:unbalanced_markup, sub}` where `sub` is `:unclosed` or
    `{:mismatched_close, name}` — markup nesting violation.

  * `{:formatter_failed, term()}` — a function formatter raised or
    returned an error. The term is the original exception or string
    detail produced by the formatter.

  """
  @type format_error_payload ::
          {:unbalanced_markup, :unclosed | {:mismatched_close, String.t()}}
          | {:formatter_failed, Exception.t() | String.t()}
          | {:data_model, Localize.Message.Validator.error()}
          | {:unknown_function, String.t()}

  @spec format_list(term(), map() | list(), Keyword.t()) ::
          {:ok, list(), list(), list()}
          | {:error, list(), list(), list()}
          | {:format_error, format_error_payload()}
  def format_list(ast, bindings \\ %{}, options \\ [])

  def format_list(ast, bindings, options) when is_list(bindings) do
    format_list(ast, Map.new(bindings), options)
  end

  # Data-model validation is the caller's job: `Localize.Message`
  # composes `Parser.parse/1` with `Validator.validate/1` before it gets
  # here, so this accepts an already-validated AST — including the
  # hand-built fragments the interpreter is expected to tolerate.
  def format_list(ast, bindings, options) when is_map(bindings) do
    bindings = normalize_binding_keys(bindings)
    do_format_list(ast, bindings, options)
  end

  # ── Top-level AST dispatch ────────────────────────────────────

  defp do_format_list([{:complex, _, _} = complex], bindings, options) do
    do_format_list(complex, bindings, options)
  end

  defp do_format_list([{:match, _, _} = match], bindings, options) do
    do_format_list(match, bindings, options)
  end

  defp do_format_list([{:quoted_pattern, _} = qp], bindings, options) do
    do_format_list(qp, bindings, options)
  end

  defp do_format_list(ast, bindings, options) when is_list(ast) do
    case format_pattern(ast, bindings, options) do
      {:ok, iolist, bound, unbound} -> {:ok, iolist, bound, unbound}
      {:error, _, _, _} = err -> err
      {:format_error, _} = err -> err
    end
  end

  defp do_format_list({:complex, declarations, body}, bindings, options) do
    case resolve_declarations(declarations, bindings, options) do
      {:format_error, _} = err ->
        err

      {:unbound_declaration, var_name} ->
        {:error, [], [], [var_name]}

      {bindings, bound, selector_meta} ->
        options = Keyword.put(options, :declaration_meta, selector_meta)
        format_complex_body(body, bindings, options, bound, selector_meta)
    end
  end

  defp do_format_list({:quoted_pattern, parts}, bindings, options) do
    format_pattern(parts, bindings, options)
  end

  defp do_format_list({:match, selectors, variants}, bindings, options) do
    evaluate_match(selectors, variants, bindings, options, [], %{})
  end

  defp format_complex_body({:quoted_pattern, parts}, bindings, options, bound, _selector_meta) do
    case format_pattern(parts, bindings, options) do
      {:ok, iolist, more_bound, unbound} ->
        {:ok, iolist, bound ++ more_bound, unbound}

      {:error, iolist, more_bound, unbound} ->
        {:error, iolist, bound ++ more_bound, unbound}

      {:format_error, _} = err ->
        err
    end
  end

  defp format_complex_body({:match, selectors, variants}, bindings, options, bound, sel_meta) do
    evaluate_match(selectors, variants, bindings, options, bound, sel_meta)
  end

  # ── Declaration resolution ───────────────────────────────────

  defp resolve_declarations(declarations, bindings, options) do
    Enum.reduce_while(declarations, {bindings, [], %{}}, fn declaration, accumulator ->
      resolve_declaration(declaration, accumulator, options)
    end)
  end

  defp resolve_declaration(
         {:input, {:expression, {:variable, name}, func, _attrs}},
         {bindings_acc, bound_acc, sel_meta} = accumulator,
         options
       ) do
    case resolve_variable(name, bindings_acc) do
      {:ok, value} ->
        func = normalize_function(func)
        bind_declaration(name, value, func, func, accumulator, options)

      :error ->
        {:cont, {bindings_acc, bound_acc, sel_meta}}
    end
  end

  defp resolve_declaration(
         {:local, {:variable, name}, {:expression, operand, func, _attrs}},
         {bindings_acc, bound_acc, sel_meta} = accumulator,
         options
       ) do
    case resolve_operand(operand, bindings_acc) do
      {:ok, value, _} ->
        func = normalize_function(func)

        case operand_select_conflict(operand, func, sel_meta) do
          :ok ->
            selector_func = merge_test_function(func, operand, sel_meta)
            bind_declaration(name, value, func, selector_func, accumulator, options)

          {:error, reason} ->
            {:halt, {:format_error, {:formatter_failed, reason}}}
        end

      {:unbound, _} ->
        {:cont, {bindings_acc, bound_acc, sel_meta}}
    end
  end

  # The WG `:test:*` functions read unset options from the resolved
  # value of a variable operand (a re-annotation such as
  # `.local $y = {$x :test:select}` inherits $x's decimalPlaces).
  # Options set directly on the expression take precedence.
  defp merge_test_function({:function, name, options} = func, {:variable, operand_name}, sel_meta)
       when name in ["test:select", "test:function", "test:format"] do
    case Map.get(sel_meta, operand_name) do
      {_value, {:function, operand_name_string, operand_options}}
      when operand_name_string in ["test:select", "test:function", "test:format"] ->
        merged = Enum.uniq_by(options ++ operand_options, fn {:option, key, _value} -> key end)
        {:function, name, merged}

      _other ->
        func
    end
  end

  defp merge_test_function(func, _operand, _sel_meta) do
    func
  end

  # TR35: "if the `select` option is set by an implementation-defined
  # type used as an operand, a Bad Option error is emitted and the
  # resolved value MUST NOT support selection" — re-annotating a
  # variable whose declaration carried a `select` option cannot carry
  # that option through the resolved operand.
  defp operand_select_conflict({:variable, operand_name}, {:function, name, _options}, sel_meta)
       when name in ["number", "integer", "offset", "percent"] do
    case Map.get(sel_meta, operand_name) do
      {_value, {:function, _declared_name, declared_options}} ->
        if Enum.any?(declared_options, &match?({:option, "select", _}, &1)) do
          {:error,
           "the select option of :#{name} cannot be set through the resolved value " <>
             "of the operand ${#{operand_name}}"}
        else
          :ok
        end

      _other ->
        :ok
    end
  end

  defp operand_select_conflict(_operand, _func, _sel_meta) do
    :ok
  end

  defp bind_declaration(
         name,
         value,
         func,
         selector_func,
         {bindings_acc, bound_acc, sel_meta},
         options
       ) do
    case apply_function(value, func, Keyword.put(options, :bindings, bindings_acc)) do
      {:ok, formatted} ->
        sel_value = selector_value(value, func)
        sel_meta = Map.put(sel_meta, name, {sel_value, selector_func})
        bindings_acc = Map.put(bindings_acc, name, formatted)
        {:cont, {bindings_acc, [name | bound_acc], sel_meta}}

      {:unbound, var_name} ->
        {:halt, {:unbound_declaration, var_name}}

      {:error, {:unknown_function, _} = payload} ->
        {:halt, {:format_error, payload}}

      {:error, reason} ->
        {:halt, {:format_error, {:formatter_failed, reason}}}
    end
  end

  # ── Pattern formatting ──────────────────────────────────────────

  defp format_pattern(parts, bindings, options) do
    result =
      Enum.reduce_while(parts, {[], [], []}, fn part, {io_acc, bound_acc, unbound_acc} ->
        case format_part(part, bindings, options) do
          {:ok, result, new_bound} ->
            {:cont, {[result | io_acc], new_bound ++ bound_acc, unbound_acc}}

          {:unbound, var_name} ->
            {:cont, {io_acc, bound_acc, [var_name | unbound_acc]}}

          {:format_error, reason} ->
            {:halt, {:format_error, reason}}
        end
      end)

    case result do
      {:format_error, reason} ->
        {:format_error, reason}

      {iolist, bound, unbound} ->
        iolist = iolist |> Enum.reverse()

        case unbound do
          [] -> {:ok, iolist, Enum.uniq(bound), []}
          _ -> {:error, iolist, Enum.uniq(bound), Enum.uniq(unbound)}
        end
    end
  end

  # ── Structured formatting (preserves markup as nested nodes) ────

  @doc """
  Format an AST into a list of `safe_node()` tuples that preserve
  markup structure as nested regions.

  Unlike `format_list/3` which drops markup, this function produces
  a flat list of `{:text, String.t()}` and `{:markup, name, options,
  children}` tuples. This is the foundation for HTML/HEEX renderers
  in companion packages.

  ### Returns

  * `{:ok, nodes, bound, unbound}` on success.

  * `{:error, nodes, bound, unbound}` when one or more variables
    could not be resolved (partial result in `nodes`).

  * `{:format_error, reason}` on formatting error (including
    unbalanced markup).

  """
  @spec format_structured(term(), map() | list(), Keyword.t()) ::
          {:ok, list(), list(), list()}
          | {:error, list(), list(), list()}
          | {:format_error, format_error_payload()}
  def format_structured(ast, bindings \\ %{}, options \\ [])

  def format_structured(ast, bindings, options) when is_list(bindings) do
    format_structured(ast, Map.new(bindings), options)
  end

  def format_structured(ast, bindings, options) when is_map(bindings) do
    bindings = normalize_binding_keys(bindings)
    do_format_structured(ast, bindings, options)
  end

  defp do_format_structured([{:complex, _, _} = complex], bindings, options) do
    do_format_structured(complex, bindings, options)
  end

  defp do_format_structured([{:match, _, _} = match], bindings, options) do
    do_format_structured(match, bindings, options)
  end

  defp do_format_structured([{:quoted_pattern, _} = qp], bindings, options) do
    do_format_structured(qp, bindings, options)
  end

  defp do_format_structured(ast, bindings, options) when is_list(ast) do
    structured_pattern(ast, bindings, options, [])
  end

  defp do_format_structured({:complex, declarations, body}, bindings, options) do
    case resolve_declarations(declarations, bindings, options) do
      {:format_error, _} = err ->
        err

      {:unbound_declaration, var_name} ->
        {:error, [], [], [var_name]}

      {bindings, bound, selector_meta} ->
        options = Keyword.put(options, :declaration_meta, selector_meta)

        case body do
          {:quoted_pattern, parts} ->
            structured_pattern(parts, bindings, options, bound)

          {:match, selectors, variants} ->
            structured_match(selectors, variants, bindings, options, bound, selector_meta)
        end
    end
  end

  defp do_format_structured({:quoted_pattern, parts}, bindings, options) do
    structured_pattern(parts, bindings, options, [])
  end

  defp do_format_structured({:match, selectors, variants}, bindings, options) do
    structured_match(selectors, variants, bindings, options, [], %{})
  end

  # MF2 selector resolution: per-selector formatted/original/function
  # fallbacks plus each variant-formatting outcome.
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp structured_match(selectors, variants, bindings, options, bound, selector_meta) do
    {selector_info, unbound_selectors} = resolve_selector_info(selectors, bindings, selector_meta)
    selector_names = for info <- selector_info, not info.unbound, do: info.name

    with :ok <- selectable_selectors(selector_info) do
      structured_matched_variant(
        selector_info,
        variants,
        bindings,
        options,
        {bound, selector_names, unbound_selectors}
      )
    end
  end

  defp structured_matched_variant(selector_info, variants, bindings, options, names) do
    {bound, selector_names, unbound_selectors} = names

    case find_best_variant(selector_info, variants, options) do
      {:ok, {:variant, _keys, {:quoted_pattern, parts}}} ->
        case structured_pattern(parts, bindings, options, bound ++ selector_names) do
          {:ok, nodes, more_bound, unbound} ->
            match_result(nodes, more_bound, unbound ++ unbound_selectors)

          {:error, nodes, more_bound, unbound} ->
            {:error, nodes, Enum.uniq(more_bound), Enum.uniq(unbound ++ unbound_selectors)}

          {:format_error, _} = err ->
            err
        end

      :error ->
        {:error, [], Enum.uniq(bound ++ selector_names),
         ["no matching variant" | unbound_selectors]}
    end
  end

  # TR35 Bad Selector: functions whose resolved values do not support
  # selection cannot be used as `.match` selectors, and a `:test:*`
  # selector with fails=select|always fails selection by design.
  defp selectable_selectors(selector_info) do
    Enum.find_value(selector_info, :ok, fn
      %{func: {:function, name, _options}}
      when name in ["currency", "unit", "date", "time", "datetime", "test:format"] ->
        {:format_error, {:formatter_failed, "the :#{name} function does not support selection"}}

      %{func: {:function, name, options}} when name in ["test:select", "test:function"] ->
        case raw_option_value(options, "fails") do
          fails when fails in ["select", "always"] ->
            {:format_error,
             {:formatter_failed, "the :#{name} selector failed to select (fails=#{fails})"}}

          _other ->
            nil
        end

      _info ->
        nil
    end)
  end

  defp raw_option_value(options, name) do
    Enum.find_value(options, fn
      {:option, ^name, {:literal, value}} -> value
      {:option, ^name, {:number_literal, value}} -> value
      _other -> nil
    end)
  end

  # Resolves each `.match` selector variable against the current
  # bindings. Selectors that cannot be resolved are reported in the
  # second element so the caller can surface an unresolved-variable
  # error alongside the fallback variant, as MF2 requires.
  defp resolve_selector_info(selectors, bindings, selector_meta) do
    selector_info =
      Enum.map(selectors, fn {:variable, name} ->
        {formatted, unbound?} =
          case resolve_variable(name, bindings) do
            {:ok, value} -> {value, false}
            :error -> {nil, true}
          end

        {original_value, func} =
          case Map.get(selector_meta, name) do
            {orig, func} -> {orig, func}
            nil -> {formatted, nil}
          end

        %{
          name: name,
          formatted: formatted,
          original: original_value,
          func: func,
          unbound: unbound?
        }
      end)

    unbound = for info <- selector_info, info.unbound, do: info.name
    {selector_info, unbound}
  end

  defp match_result(output, bound, []), do: {:ok, output, Enum.uniq(bound), []}

  defp match_result(output, bound, unbound),
    do: {:error, output, Enum.uniq(bound), Enum.uniq(unbound)}

  # Walk the parts list pairing markup open/close tags into nested nodes.
  # The stack holds in-progress markup frames: each frame is
  # {name, options, accumulated_children, bound_acc, unbound_acc}.
  defp structured_pattern(parts, bindings, options, bound_initial) do
    do_structured_pattern(parts, bindings, options, [], [], bound_initial, [])
  end

  defp do_structured_pattern([], _bindings, _options, [_ | _], _acc, _bound, _unbound) do
    # Stack non-empty at end of pattern = unbalanced open markup
    {:format_error, {:unbalanced_markup, :unclosed}}
  end

  defp do_structured_pattern([], _bindings, _options, [], acc, bound, unbound) do
    nodes = acc |> Enum.reverse() |> merge_adjacent_text()

    case unbound do
      [] -> {:ok, nodes, Enum.uniq(bound), []}
      _ -> {:error, nodes, Enum.uniq(bound), Enum.uniq(unbound)}
    end
  end

  defp do_structured_pattern([part | rest], bindings, options, stack, acc, bound, unbound) do
    case structured_part(part, bindings, options) do
      {:text, text, new_bound} ->
        do_structured_pattern(
          rest,
          bindings,
          options,
          stack,
          [{:text, text} | acc],
          new_bound ++ bound,
          unbound
        )

      {:standalone, name, resolved_options, new_bound} ->
        do_structured_pattern(
          rest,
          bindings,
          options,
          stack,
          [{:markup, name, resolved_options, []} | acc],
          new_bound ++ bound,
          unbound
        )

      {:open, name, resolved_options, new_bound} ->
        # Push current acc onto the stack and start a new children list.
        frame = {name, resolved_options, acc}

        do_structured_pattern(
          rest,
          bindings,
          options,
          [frame | stack],
          [],
          new_bound ++ bound,
          unbound
        )

      {:close, name, _new_bound} ->
        case stack do
          [{^name, opts, parent_acc} | rest_stack] ->
            children = acc |> Enum.reverse() |> merge_adjacent_text()
            node = {:markup, name, opts, children}

            do_structured_pattern(
              rest,
              bindings,
              options,
              rest_stack,
              [node | parent_acc],
              bound,
              unbound
            )

          _ ->
            {:format_error, {:unbalanced_markup, {:mismatched_close, name}}}
        end

      {:unbound, var_name} ->
        do_structured_pattern(rest, bindings, options, stack, acc, bound, [var_name | unbound])

      {:format_error, _} = err ->
        err
    end
  end

  defp structured_part({:text, text}, _bindings, _options) do
    {:text, text, []}
  end

  defp structured_part({:escape, char}, _bindings, _options) do
    {:text, char, []}
  end

  defp structured_part({:expression, operand, func, attrs}, bindings, options) do
    case format_expression(operand, func, bindings, options) do
      {:ok, formatted, bound_names} ->
        bidi_mode = Keyword.get(options, :bidi, :none)
        dir_override = extract_dir_attribute(attrs)
        wrapped = apply_bidi_isolation(formatted, bidi_mode, dir_override, options)
        {:text, IO.iodata_to_binary(wrapped), bound_names}

      {:unbound, name} ->
        {:unbound, name}

      {:format_error, _} = err ->
        err
    end
  end

  defp structured_part({:markup_open, name, opts, _attrs}, bindings, _options) do
    {resolved, bound} = resolve_markup_options(opts, bindings)
    {:open, name, resolved, bound}
  end

  defp structured_part({:markup_close, name, _opts, _attrs}, _bindings, _options) do
    {:close, name, []}
  end

  defp structured_part({:markup_standalone, name, opts, _attrs}, bindings, _options) do
    {resolved, bound} = resolve_markup_options(opts, bindings)
    {:standalone, name, resolved, bound}
  end

  defp resolve_markup_options(opts, bindings) do
    Enum.reduce(opts, {%{}, []}, fn
      {:option, name, {:literal, value}}, {acc, bound} ->
        {Map.put(acc, name, value), bound}

      {:option, name, {:number_literal, value}}, {acc, bound} ->
        {Map.put(acc, name, parse_number(value)), bound}

      {:option, name, {:variable, var_name}}, {acc, bound} ->
        case resolve_variable(var_name, bindings) do
          {:ok, value} -> {Map.put(acc, name, value), [var_name | bound]}
          :error -> {acc, bound}
        end
    end)
  end

  # Coalesce consecutive {:text, _} nodes into one. Expression
  # interpolation produces a {:text, _} node, and adjacent static
  # text also produces one — combining them keeps the output tidy.
  defp merge_adjacent_text(nodes) do
    Enum.reduce(nodes, [], fn
      {:text, t1}, [{:text, t2} | rest] -> [{:text, t2 <> t1} | rest]
      node, acc -> [node | acc]
    end)
    |> Enum.reverse()
  end

  defp format_part({:text, text}, _bindings, _options) do
    {:ok, text, []}
  end

  defp format_part({:escape, char}, _bindings, _options) do
    {:ok, char, []}
  end

  defp format_part({:expression, operand, func, attrs}, bindings, options) do
    case format_expression(operand, func, bindings, options) do
      {:ok, formatted, bound_names} ->
        bidi_mode = Keyword.get(options, :bidi, :none)
        dir_override = extract_dir_attribute(attrs)
        wrapped = apply_bidi_isolation(formatted, bidi_mode, dir_override, options)
        {:ok, wrapped, bound_names}

      other ->
        other
    end
  end

  defp format_part({:markup_open, _name, _options, _attrs}, _bindings, _options_kw) do
    {:ok, "", []}
  end

  defp format_part({:markup_close, _name, _options, _attrs}, _bindings, _options_kw) do
    {:ok, "", []}
  end

  defp format_part({:markup_standalone, _name, _options, _attrs}, _bindings, _options_kw) do
    {:ok, "", []}
  end

  # ── Expression formatting ───────────────────────────────────────

  defp format_expression(operand, func, bindings, options) do
    case resolve_operand(operand, bindings) do
      {:ok, value, bound_names} ->
        {value, func} = reannotate_from_declaration(operand, value, func, options)

        case apply_function(value, func, Keyword.put(options, :bindings, bindings)) do
          {:ok, formatted} -> {:ok, formatted, bound_names}
          {:unbound, var_name} -> {:unbound, var_name}
          {:error, {:unknown_function, _} = payload} -> {:format_error, payload}
          {:error, reason} -> {:format_error, {:formatter_failed, reason}}
        end

      {:unbound, name} ->
        {:unbound, name}
    end
  end

  # A pattern expression that re-annotates a declared variable
  # operates on the declaration's original (unformatted) value —
  # not the formatted string the declaration bound — and a numeric
  # function inherits unset options from a numeric declaration, so
  # `.local $x = {41 :integer signDisplay=always}` rendered with
  # `{$x :offset add=1}` produces "+42".
  defp reannotate_from_declaration({:variable, name}, value, {:function, _, _} = func, options) do
    case options |> Keyword.get(:declaration_meta, %{}) |> Map.get(name) do
      {original, declared_func} ->
        {original, merge_declared_options(normalize_function(func), declared_func)}

      nil ->
        {value, func}
    end
  end

  defp reannotate_from_declaration(_operand, value, func, _options) do
    {value, func}
  end

  defp merge_declared_options(
         {:function, name, options},
         {:function, declared_name, declared_options}
       )
       when name in ["number", "integer", "offset", "percent", "currency"] and
              declared_name in ["number", "integer", "offset", "percent", "currency"] do
    merged = Enum.uniq_by(options ++ declared_options, fn {:option, key, _value} -> key end)
    {:function, name, merged}
  end

  defp merge_declared_options(func, _declared_func) do
    func
  end

  defp resolve_operand(nil, _bindings) do
    {:ok, nil, []}
  end

  defp resolve_operand({:variable, name}, bindings) do
    case resolve_variable(name, bindings) do
      {:ok, value} -> {:ok, value, [name]}
      :error -> {:unbound, name}
    end
  end

  defp resolve_operand({:literal, value}, _bindings) do
    {:ok, value, []}
  end

  defp resolve_operand({:number_literal, value}, _bindings) do
    {:ok, value, []}
  end

  # ── Function dispatch ──────────────────────────────────────────

  defp apply_function(value, nil, options) when is_number(value) do
    # An unannotated placeholder with a numeric operand formats with
    # the locale-aware default, as if annotated with `:number`.
    Localize.Number.to_string(value, resolve_locale_options(options))
  end

  defp apply_function(%Decimal{} = value, nil, options) do
    Localize.Number.to_string(value, resolve_locale_options(options))
  end

  defp apply_function(value, nil, _options) do
    {:ok, to_string_value(value)}
  end

  defp apply_function(value, {:function, raw_name, func_options}, options) do
    bindings = Keyword.get(options, :bindings, %{})
    name = function_name(raw_name)

    case validate_select_option(name, func_options) do
      :ok ->
        case resolve_func_options(func_options, bindings) do
          {:ok, func_opts} -> format_with_function(name, value, func_opts, options)
          {:unbound, var_name} -> {:unbound, var_name}
        end

      {:error, _} = error ->
        error
    end
  end

  # The parser represents a namespaced function name (`:ns:name`) as
  # `{:namespace, ns, name}`; everywhere downstream works with the
  # flat "ns:name" string form.
  defp function_name({:namespace, namespace, name}), do: namespace <> ":" <> name
  defp function_name(name) when is_binary(name), do: name

  defp normalize_function({:function, raw_name, options}) do
    {:function, function_name(raw_name), options}
  end

  defp normalize_function(func), do: func

  # TR35: "The option value of the `select` option MUST be set by a
  # literal" — a variable-valued `select` is a Bad Option error, since
  # the set of variant keys is tied to the selection mode chosen.
  defp validate_select_option(name, func_options)
       when name in ["number", "integer", "offset", "percent"] do
    Enum.find_value(func_options, :ok, fn
      {:option, "select", {:variable, _var_name}} ->
        {:error, "the select option of :#{name} must be set by a literal value"}

      _other ->
        nil
    end)
  end

  defp validate_select_option(_name, _func_options) do
    :ok
  end

  # ── Number formatting ──────────────────────────────────────────
  #
  # MF2 function stability levels (per Unicode MessageFormat 2.0):
  #
  #   Stable:  :number, :integer, :string, :currency, :percent
  #   Draft:   :date, :time, :datetime, :unit
  #
  # Stable functions have fixed signatures and behaviour across
  # MF2 specification versions. Draft functions may change in
  # future specification releases.

  defp format_with_function("number", value, func_opts, options) do
    with {:ok, number} <- ensure_number(value),
         {:ok, options_struct} <- build_number_options(options, func_opts) do
      format_number_result(number, options_struct, func_opts)
    end
  end

  defp format_with_function("integer", value, func_opts, options) do
    with {:ok, number} <- ensure_number(value),
         {:ok, options_struct} <- build_number_options(options, func_opts) do
      format_number_result(trunc(number), options_struct, func_opts)
    end
  end

  defp format_with_function("offset", value, func_opts, options) do
    with {:ok, number} <- ensure_number(value),
         {:ok, adjustment} <- offset_adjustment(func_opts),
         {:ok, options_struct} <- build_number_options(options, func_opts) do
      format_number_result(apply_offset(number, adjustment), options_struct, func_opts)
    end
  end

  defp format_with_function("percent", value, func_opts, options) do
    with {:ok, number} <- ensure_number(value),
         {:ok, options_struct} <- build_number_options(options, func_opts, format: :percent) do
      format_number_result(number, options_struct, func_opts)
    end
  end

  defp format_with_function("currency", value, func_opts, options) do
    with {:ok, number} <- ensure_number(value),
         {:ok, options_struct} <- build_currency_options(options, func_opts) do
      format_number_result(number, options_struct, func_opts)
    end
  end

  # ── String formatting ──────────────────────────────────────────

  defp format_with_function("string", value, _func_opts, _options) do
    {:ok, to_string_value(value)}
  end

  # ── Date/time formatting ───────────────────────────────────────

  defp format_with_function("date", value, func_opts, options) do
    with {:ok, value} <- ensure_date(value) do
      localize_opts = resolve_locale_options(options)
      localize_opts = map_date_options(localize_opts, func_opts, :format)
      Localize.Date.to_string(value, localize_opts)
    end
  end

  defp format_with_function("time", %Time{} = value, func_opts, options) do
    localize_opts = resolve_locale_options(options)
    localize_opts = map_time_options(localize_opts, func_opts, :format)
    Localize.Time.to_string(value, localize_opts)
  end

  defp format_with_function("time", value, func_opts, options) do
    with {:ok, value} <- ensure_datetime(value) do
      localize_opts = resolve_locale_options(options)
      localize_opts = map_time_options(localize_opts, func_opts, :format)
      Localize.Time.to_string(value, localize_opts)
    end
  end

  defp format_with_function("datetime", value, func_opts, options) do
    with {:ok, value} <- ensure_datetime(value) do
      localize_opts = resolve_locale_options(options)
      localize_opts = map_datetime_options(localize_opts, func_opts)
      Localize.DateTime.to_string(value, localize_opts)
    end
  end

  # ── Unit formatting ────────────────────────────────────────────

  defp format_with_function("unit", %Localize.Unit{} = unit_struct, func_opts, options) do
    unit_result =
      if func_opts[:unit] do
        Localize.Unit.new(Map.get(unit_struct, :value), func_opts[:unit])
      else
        {:ok, unit_struct}
      end

    with {:ok, unit} <- unit_result do
      localize_opts = resolve_locale_options(options)
      localize_opts = map_unit_options(localize_opts, func_opts)
      Localize.Unit.to_string(unit, localize_opts)
    end
  end

  defp format_with_function("unit", value, func_opts, options) do
    with {:ok, number} <- ensure_number(value) do
      format_number_as_unit(number, func_opts[:unit], func_opts, options)
    end
  end

  # ── List formatting ────────────────────────────────────────────

  defp format_with_function("list", value, func_opts, options) when is_list(value) do
    localize_opts = resolve_locale_options(options)
    localize_opts = map_list_options(localize_opts, func_opts)
    Localize.List.to_string(value, localize_opts)
  end

  defp format_with_function("list", value, _func_opts, _options) do
    {:error, "the :list function requires a list operand, got #{inspect(value)}"}
  end

  # ── MF2 WG test registry functions ───────────────────────────────
  #
  # The `:test:function`, `:test:format` and `:test:select` functions
  # are defined by the MessageFormat working group solely so its
  # conformance suite can exercise selection and formatting mechanics.
  # Operand: a number or number-literal string. Options:
  # `decimalPlaces` (0 or 1) and `fails` (never | select | format |
  # always). Formatting truncates toward zero to the requested number
  # of decimal places. Deviation: this implementation resolves
  # declarations eagerly, so `:test:select` formats like
  # `:test:function` instead of emitting a not-formattable error, and
  # its `fails=format` mode is ignored — selection is its only
  # observable behaviour in the suite.

  defp format_with_function(name, value, func_opts, _options)
       when name in ["test:function", "test:format", "test:select"] do
    with {:ok, number} <- ensure_number(value),
         {:ok, decimal_places} <- test_decimal_places(func_opts),
         {:ok, fails} <- test_fails(func_opts) do
      if name != "test:select" and fails in ["format", "always"] do
        {:error, "the :#{name} function failed to format (fails=#{fails})"}
      else
        {:ok, test_format_number(number, decimal_places)}
      end
    end
  end

  # ── Custom function registry ─────────────────────────────────────
  #
  # When a function name is not matched by any built-in clause
  # above, look for a custom function module in two places:
  #
  #   1. The per-call `:functions` option (takes precedence).
  #   2. The application-level `:mf2_functions` config.
  #
  # If found, the module must implement the
  # `Localize.Message.Function` behaviour. If no custom function
  # is registered for the name, the reference is an Unknown
  # Function resolution error per TR35.

  defp format_with_function(name, value, func_opts, options) do
    case resolve_custom_function(name, options) do
      {:ok, module} ->
        module.format(value, func_opts, options)

      :not_found ->
        # TR35 resolution error: a function that cannot be resolved
        # is an Unknown Function error, not a pass-through format of
        # the operand.
        {:error, {:unknown_function, ":" <> name}}
    end
  end

  defp format_number_as_unit(_number, nil, _func_opts, _options) do
    {:error, "the :unit function requires a `unit` option"}
  end

  defp format_number_as_unit(number, unit_name, func_opts, options) do
    with {:ok, unit} <- Localize.Unit.new(number, unit_name) do
      localize_opts = resolve_locale_options(options)
      localize_opts = map_unit_options(localize_opts, func_opts)
      Localize.Unit.to_string(unit, localize_opts)
    end
  end

  defp test_decimal_places(func_opts) do
    case func_opts[:decimalPlaces] || func_opts["decimalPlaces"] do
      nil ->
        {:ok, 0}

      value when value in [0, 1] ->
        {:ok, value}

      value ->
        {:error,
         "the decimalPlaces option of the :test functions must be 0 or 1, got #{inspect(value)}"}
    end
  end

  defp test_fails(func_opts) do
    case func_opts[:fails] || func_opts["fails"] do
      nil ->
        {:ok, "never"}

      value when value in ["never", "select", "format", "always"] ->
        {:ok, value}

      value ->
        {:error,
         "the fails option of the :test functions must be one of never, select, format or always, got #{inspect(value)}"}
    end
  end

  defp test_format_number(number, decimal_places) do
    float = to_float(number)
    sign = if float < 0, do: "-", else: ""
    magnitude = abs(float)
    integer_part = trunc(magnitude)

    case decimal_places do
      0 ->
        sign <> Integer.to_string(integer_part)

      1 ->
        tenths = trunc(magnitude * 10) - integer_part * 10
        sign <> Integer.to_string(integer_part) <> "." <> Integer.to_string(tenths)
    end
  end

  defp to_float(%Decimal{} = number), do: Decimal.to_float(number)
  defp to_float(number) when is_number(number), do: number * 1.0

  # Formats a resolved numeric value honouring the MF2 `signDisplay`
  # option (auto | always | exceptZero | negative | never) by mapping
  # it to the `:sign_display` option of `Localize.Number.to_string/2`.
  # All sign handling — pattern selection, plus-sign placement, zero
  # and NaN semantics — is done by the number formatter, never here.
  defp format_number_result(number, options_struct, func_opts) do
    with {:ok, sign_display} <- sign_display_option(func_opts) do
      options_struct = %{options_struct | sign_display: sign_display}
      Localize.Number.to_string(number, set_number_pattern(options_struct, number))
    end
  end

  defp sign_display_option(func_opts) do
    case func_opts[:signDisplay] || func_opts["signDisplay"] do
      nil ->
        {:ok, nil}

      value when is_map_key(@mf2_sign_displays, value) ->
        {:ok, Map.fetch!(@mf2_sign_displays, value)}

      value ->
        {:error,
         "the signDisplay option must be one of auto, always, exceptZero, negative " <>
           "or never, got #{inspect(value)}"}
    end
  end

  # TR35 MF2 `minimumIntegerDigits` is a digit size option with a
  # default of 1. Zero is rejected: the underlying ECMA-402 range is
  # 1..21 and a zero minimum would let the integer part vanish.
  defp minimum_integer_digits_option(func_opts) do
    case digit_size_option(func_opts, :minimumIntegerDigits) do
      {:ok, nil} ->
        {:ok, nil}

      {:ok, value} when value >= 1 ->
        {:ok, value}

      {:ok, value} ->
        {:error, "the minimumIntegerDigits option must be a positive integer, got #{value}"}

      error ->
        error
    end
  end

  # TR35 MF2 `minimumSignificantDigits` / `maximumSignificantDigits`
  # are digit size options; the ECMA-402 range they map onto is 1..21,
  # so an explicit zero is a bad option value.
  defp significant_digits_option(func_opts, key) do
    case digit_size_option(func_opts, key) do
      {:ok, 0} -> {:error, "the #{key} option must be a positive integer, got 0"}
      other -> other
    end
  end

  defp trailing_zero_display_option(func_opts) do
    case func_opts[:trailingZeroDisplay] || func_opts["trailingZeroDisplay"] do
      nil ->
        {:ok, nil}

      value when is_map_key(@mf2_trailing_zero_displays, value) ->
        {:ok, Map.fetch!(@mf2_trailing_zero_displays, value)}

      value ->
        {:error,
         "the trailingZeroDisplay option must be auto or stripIfInteger, got #{inspect(value)}"}
    end
  end

  defp rounding_priority_option(func_opts) do
    case func_opts[:roundingPriority] || func_opts["roundingPriority"] do
      nil ->
        {:ok, nil}

      value when is_map_key(@mf2_rounding_priorities, value) ->
        {:ok, Map.fetch!(@mf2_rounding_priorities, value)}

      value ->
        {:error,
         "the roundingPriority option must be one of auto, morePrecision or lessPrecision, " <>
           "got #{inspect(value)}"}
    end
  end

  defp resolve_custom_function(name, options) do
    per_call = Keyword.get(options, :functions, %{})

    case Map.get(per_call, name) do
      nil ->
        app_functions = Application.get_env(:localize, :mf2_functions, %{})

        case Map.get(app_functions, name) do
          nil -> :not_found
          module -> {:ok, module}
        end

      module ->
        {:ok, module}
    end
  end

  # ── Match evaluation ───────────────────────────────────────────

  # MF2 match evaluation: per-selector formatted/original/function
  # fallbacks plus each variant-formatting outcome.
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp evaluate_match(selectors, variants, bindings, options, bound, selector_meta) do
    {selector_info, unbound_selectors} = resolve_selector_info(selectors, bindings, selector_meta)
    selector_names = for info <- selector_info, not info.unbound, do: info.name

    with :ok <- selectable_selectors(selector_info) do
      evaluate_matched_variant(
        selector_info,
        variants,
        bindings,
        options,
        {bound, selector_names, unbound_selectors}
      )
    end
  end

  defp evaluate_matched_variant(selector_info, variants, bindings, options, names) do
    {bound, selector_names, unbound_selectors} = names

    case find_best_variant(selector_info, variants, options) do
      {:ok, {:variant, _keys, {:quoted_pattern, parts}}} ->
        case format_pattern(parts, bindings, options) do
          {:ok, iolist, more_bound, unbound} ->
            match_result(
              iolist,
              bound ++ selector_names ++ more_bound,
              unbound ++ unbound_selectors
            )

          {:error, iolist, more_bound, unbound} ->
            {:error, iolist, Enum.uniq(bound ++ selector_names ++ more_bound),
             Enum.uniq(unbound ++ unbound_selectors)}

          {:format_error, _} = err ->
            err
        end

      :error ->
        {:error, [], Enum.uniq(bound ++ selector_names),
         ["no matching variant" | unbound_selectors]}
    end
  end

  defp find_best_variant(selector_info, variants, options) do
    sorted =
      variants
      |> Enum.filter(fn {:variant, keys, _} ->
        match_keys?(selector_info, keys, options)
      end)
      |> Enum.sort_by(fn {:variant, keys, _} ->
        {Enum.count(keys, &(&1 == :catchall)), test_select_penalty(selector_info, keys)}
      end)

    case sorted do
      [best | _] -> {:ok, best}
      [] -> :error
    end
  end

  # WG `:test:select` key preference: among matching keys, `1.0`
  # is better than `1`. Zero penalty for a `1.0` key on a test
  # selector position, so those variants sort first.
  defp test_select_penalty(selector_info, keys) do
    selector_info
    |> Enum.zip(keys)
    |> Enum.count(fn
      {%{func: {:function, name, _options}}, key}
      when name in ["test:select", "test:function"] ->
        key_literal(key) != "1.0"

      _pair ->
        false
    end)
  end

  defp key_literal({:literal, value}), do: value
  defp key_literal({:number_literal, value}), do: value
  defp key_literal(:catchall), do: "*"

  defp match_keys?(selector_info, keys, options) do
    if length(selector_info) != length(keys) do
      false
    else
      Enum.zip(selector_info, keys)
      |> Enum.all?(fn
        {_info, :catchall} -> true
        {info, key} -> match_selector?(info, key, options)
      end)
    end
  end

  # WG `:test:select` / `:test:function` selection: the value matches
  # only when it is exactly 1 — key `1` always, key `1.0` only when
  # decimalPlaces=1. Any other value matches only the catch-all.
  defp match_selector?(%{func: {:function, name, options}} = info, key, _options_kw)
       when name in ["test:select", "test:function"] do
    value =
      case info.original do
        binary when is_binary(binary) -> parse_number(binary)
        other -> other
      end

    decimal_places = raw_option_value(options, "decimalPlaces")

    cond do
      not (is_number(value) and value == 1) -> false
      decimal_places == "1" -> key_literal(key) in ["1.0", "1"]
      true -> key_literal(key) == "1"
    end
  end

  defp match_selector?(info, {:number_literal, key_str}, _options) do
    match_value?(info.original, parse_number(key_str))
  end

  defp match_selector?(info, {:literal, key_str}, options) do
    if match_value?(info.original, key_str) do
      true
    else
      case plural_match_type(info.func) do
        nil ->
          false

        :exact ->
          false

        plural_type ->
          category = resolve_plural_category(info.original, plural_type, options)
          category != nil and Atom.to_string(category) == key_str
      end
    end
  end

  # ── Selector helpers ───────────────────────────────────────────

  defp selector_value(value, {:function, "integer", _}) when is_number(value) do
    trunc(value)
  end

  defp selector_value(value, {:function, "integer", _}) when is_binary(value) do
    case parse_number(value) do
      num when is_number(num) -> trunc(num)
      _ -> value
    end
  end

  defp selector_value(value, {:function, "offset", func_options}) when is_number(value) do
    offset_selector_value(value, func_options)
  end

  defp selector_value(value, {:function, "offset", func_options}) when is_binary(value) do
    case parse_number(value) do
      num when is_number(num) -> offset_selector_value(num, func_options)
      _ -> value
    end
  end

  defp selector_value(value, {:function, "percent", _}) when is_number(value) do
    integerize(value * 100)
  end

  defp selector_value(value, {:function, "percent", _} = func) when is_binary(value) do
    case parse_number(value) do
      num when is_number(num) -> selector_value(num, func)
      _ -> value
    end
  end

  defp selector_value(value, _func), do: value

  defp offset_selector_value(number, func_options) do
    with {:ok, func_opts} <- resolve_func_options(func_options, %{}),
         {:ok, adjustment} <- offset_adjustment(func_opts) do
      number + adjustment
    else
      _other -> number
    end
  end

  # The MF2 `:offset` function requires exactly one of the `add` or
  # `subtract` options, each a digit size option (a non-negative
  # integer). See "The `:offset` function" in tr35-messageFormat.md.

  defp offset_adjustment(func_opts) do
    add = func_opts[:add] || func_opts["add"]
    subtract = func_opts[:subtract] || func_opts["subtract"]
    resolve_offset_adjustment(add, subtract)
  end

  defp resolve_offset_adjustment(add, nil) when is_integer(add) and add >= 0 do
    {:ok, add}
  end

  defp resolve_offset_adjustment(nil, subtract) when is_integer(subtract) and subtract >= 0 do
    {:ok, -subtract}
  end

  defp resolve_offset_adjustment(nil, nil) do
    {:error, "the :offset function requires one of the `add` or `subtract` options"}
  end

  defp resolve_offset_adjustment(add, subtract) do
    {:error,
     "the :offset function requires exactly one of `add` or `subtract` " <>
       "as a non-negative integer, got add=#{inspect(add)} subtract=#{inspect(subtract)}"}
  end

  defp apply_offset(%Decimal{} = number, adjustment), do: Decimal.add(number, adjustment)
  defp apply_offset(number, adjustment), do: number + adjustment

  # The MF2 `:percent` function multiplies its operand by 100 at the
  # start of selection. The default fraction digits are zero, so an
  # exactly-integral scaled value selects as an integer.

  defp integerize(value) when is_float(value) do
    truncated = trunc(value)

    if truncated == value do
      truncated
    else
      value
    end
  end

  defp integerize(value), do: value

  # ── Plural category resolution ────────────────────────────────

  defp plural_match_type(nil), do: nil

  defp plural_match_type({:function, name, func_options})
       when name in ["number", "integer", "offset", "percent"] do
    select_opt =
      Enum.find_value(func_options, fn
        {:option, "select", {:literal, value}} -> value
        _ -> nil
      end)

    case select_opt do
      "exact" -> :exact
      "ordinal" -> :ordinal
      _ -> :cardinal
    end
  end

  defp plural_match_type(_), do: nil

  defp resolve_plural_category(value, plural_type, options) when is_number(value) do
    locale = Keyword.get(options, :locale) || Localize.get_locale()

    plural_options =
      [locale: locale, type: plural_type]
      |> maybe_add_backend(options)

    Localize.Number.PluralRule.plural_type(value, plural_options)
  end

  defp resolve_plural_category(value, plural_type, options) when is_binary(value) do
    case parse_number(value) do
      num when is_number(num) -> resolve_plural_category(num, plural_type, options)
      _ -> nil
    end
  end

  defp resolve_plural_category(_, _, _), do: nil

  # ── Value comparison ───────────────────────────────────────────

  defp match_value?(value, key) when is_integer(value) and is_integer(key) do
    value == key
  end

  defp match_value?(value, key) when is_float(value) and is_float(key) do
    value == key
  end

  defp match_value?(value, key) when is_number(value) and is_number(key) do
    value == key
  end

  defp match_value?(value, key) when is_binary(value) and is_binary(key) do
    value == key
  end

  defp match_value?(value, key) when is_number(value) and is_binary(key) do
    to_string_value(value) == key
  end

  defp match_value?(value, key) when is_binary(value) and is_number(key) do
    value == to_string_value(key)
  end

  defp match_value?(value, key) do
    to_string_value(value) == to_string_value(key)
  end

  # ── Number option mapping ──────────────────────────────────────

  alias Localize.Number.Format.Options, as: NumberOptions
  alias Localize.Utils.Helpers

  defp set_number_pattern(options_struct, number) when is_number(number) and number < 0 do
    %{options_struct | pattern: :negative}
  end

  defp set_number_pattern(options_struct, %Decimal{sign: sign}) when sign < 0 do
    %{options_struct | pattern: :negative}
  end

  defp set_number_pattern(options_struct, _number) do
    %{options_struct | pattern: :positive}
  end

  defp build_number_options(options, func_opts, overrides \\ []) do
    with {:ok, locale} <- resolve_locale(options),
         {:ok, number_system} <- resolve_number_system(locale, func_opts),
         {:ok, symbols} <- number_symbols_with_fallback(locale, number_system),
         {:ok, min_fd} <- digit_size_option(func_opts, :minimumFractionDigits),
         {:ok, max_fd} <- digit_size_option(func_opts, :maximumFractionDigits),
         {:ok, min_sd} <- significant_digits_option(func_opts, :minimumSignificantDigits),
         {:ok, max_sd} <- significant_digits_option(func_opts, :maximumSignificantDigits),
         {:ok, min_id} <- minimum_integer_digits_option(func_opts),
         {:ok, trailing_zero} <- trailing_zero_display_option(func_opts),
         {:ok, rounding_priority} <- rounding_priority_option(func_opts) do
      use_grouping = Map.get(func_opts, :useGrouping)

      {format, minimum_grouping_digits} =
        resolve_format_and_grouping(use_grouping, overrides)

      pattern = Keyword.get(overrides, :pattern, :positive)

      raw_format = Keyword.get(overrides, :format, format)

      # An algorithmic numbering system (`hans`, `roman`, …) defines no
      # decimal patterns — plain `:number`/`:integer` formatting uses the
      # system's RBNF rules, matching `Localize.Number.to_string/2` and
      # ICU. Grouping options don't apply to rule-based output. Explicit
      # format overrides (`:percent`) degrade to the default system's
      # pattern, as in `Localize.Number.Format.Options.resolve_format/3`.
      resolved_format =
        if Keyword.get(overrides, :format) == nil and algorithmic_system?(number_system) do
          :standard
        else
          resolve_number_format(raw_format, locale, number_system)
        end

      options_struct = %NumberOptions{
        locale: locale,
        number_system: number_system,
        format: resolved_format,
        symbols: symbols,
        rounding_mode: :half_even,
        min_fractional_digits: min_fd,
        max_fractional_digits: max_fd,
        minimum_integer_digits: min_id,
        minimum_significant_digits: min_sd,
        maximum_significant_digits: max_sd,
        trailing_zero_display: trailing_zero,
        rounding_priority: rounding_priority,
        minimum_grouping_digits: minimum_grouping_digits,
        pattern: pattern,
        currency: Keyword.get(overrides, :currency),
        currency_symbol: Keyword.get(overrides, :currency_symbol),
        currency_digits: :accounting
      }

      {:ok, options_struct}
    end
  end

  defp algorithmic_system?(system_name) do
    Map.has_key?(Localize.Number.System.algorithmic_systems(), system_name)
  end

  defp resolve_number_format(format, _locale, _number_system) when is_binary(format) do
    format
  end

  defp resolve_number_format(format_atom, locale, number_system) when is_atom(format_atom) do
    case formats_with_fallback(locale, number_system) do
      {:ok, formats} ->
        case Map.get(formats, format_atom) do
          nil -> "#,##0.###"
          resolved -> resolved
        end

      _ ->
        "#,##0.###"
    end
  end

  # The MF2 `numberingSystem` option may name a system the locale carries
  # no symbol or format data for (any CLDR system is honoured, matching
  # Intl/ICU). `Symbol.number_symbols_for/2` and `Format.formats_for/2`
  # fall back to the locale's default-system data themselves — digit
  # transliteration still uses the requested system.
  defp number_symbols_with_fallback(locale, number_system) do
    Localize.Number.Symbol.number_symbols_for(locale, number_system)
  end

  defp formats_with_fallback(locale, number_system) do
    Localize.Number.Format.formats_for(locale, number_system)
  end

  defp build_currency_options(options, func_opts) do
    currency_code = func_opts[:currency]
    currency_sign = func_opts[:currencySign]

    format =
      case currency_sign do
        "accounting" -> :accounting
        _ -> :currency
      end

    currency_symbol =
      case func_opts[:currencyDisplay] do
        "narrowSymbol" -> :narrow
        "code" -> :iso
        _ -> nil
      end

    with {:ok, locale} <- resolve_locale(options),
         {:ok, number_system} <- resolve_number_system(locale, func_opts),
         {:ok, symbols} <- number_symbols_with_fallback(locale, number_system),
         {:ok, format_string} <- resolve_currency_format(locale, number_system, format),
         {:ok, currency_struct} <- resolve_currency_struct(currency_code, locale),
         {:ok, min_fd} <- digit_size_option(func_opts, :minimumFractionDigits),
         {:ok, max_fd} <- digit_size_option(func_opts, :maximumFractionDigits),
         {:ok, min_sd} <- significant_digits_option(func_opts, :minimumSignificantDigits),
         {:ok, max_sd} <- significant_digits_option(func_opts, :maximumSignificantDigits),
         {:ok, min_id} <- minimum_integer_digits_option(func_opts),
         {:ok, trailing_zero} <- trailing_zero_display_option(func_opts),
         {:ok, rounding_priority} <- rounding_priority_option(func_opts) do
      actual_symbol = resolve_currency_symbol(currency_struct, currency_symbol)

      # Default fractional digits from currency when not explicitly set
      default_fd = currency_struct.digits

      options_struct = %NumberOptions{
        locale: locale,
        number_system: number_system,
        format: format_string,
        symbols: symbols,
        rounding_mode: :half_even,
        fractional_digits: if(min_fd == nil and max_fd == nil, do: default_fd, else: nil),
        min_fractional_digits: min_fd,
        max_fractional_digits: max_fd,
        minimum_integer_digits: min_id,
        minimum_significant_digits: min_sd,
        maximum_significant_digits: max_sd,
        trailing_zero_display: trailing_zero,
        rounding_priority: rounding_priority,
        minimum_grouping_digits: nil,
        pattern: :positive,
        currency: currency_struct,
        currency_symbol: actual_symbol,
        currency_spacing: resolve_currency_spacing(locale, number_system),
        currency_digits: :accounting
      }

      {:ok, options_struct}
    end
  end

  defp resolve_locale(options) do
    locale = Keyword.get(options, :locale, Localize.get_locale())
    Localize.validate_locale(locale)
  end

  defp resolve_number_system(locale, func_opts) do
    case Map.get(func_opts, :numberingSystem) do
      nil ->
        Localize.Number.System.number_system_from_locale(locale)

      system when is_binary(system) or is_atom(system) ->
        # `system_name_from/2` accepts strings or atoms and validates
        # against the full numbering system table. We deliberately
        # avoid `String.to_existing_atom/1` here because the atom
        # may not yet have been created on this BEAM instance —
        # numbering system atoms are created lazily when the
        # supplemental data is first read.
        #
        # The MF2 `numberingSystem` option matches Intl/ICU semantics:
        # any numbering system in the CLDR inventory is honoured even
        # when the locale does not list it, so `numberingSystem=thai`
        # renders Thai digits in an `en` locale. Genuinely unknown
        # system names are still an error.
        case Localize.Number.System.system_name_from(system, locale) do
          {:ok, _} = ok ->
            ok

          {:error, _exception} ->
            {:error, "unknown numbering system #{inspect(system)}"}
        end
    end
  end

  defp resolve_format_and_grouping(use_grouping, overrides) do
    base_format = Keyword.get(overrides, :format)

    cond do
      # Explicit format override (like :percent)
      base_format != nil and is_atom(base_format) ->
        {base_format, nil}

      # useGrouping=never
      use_grouping == "never" ->
        {"##0.###", nil}

      # useGrouping=min2
      use_grouping == "min2" ->
        {:standard, 2}

      # Default
      true ->
        {:standard, nil}
    end
  end

  defp resolve_currency_format(locale, number_system, format_atom) do
    with {:ok, formats} <- formats_with_fallback(locale, number_system) do
      case Map.get(formats, format_atom) do
        nil -> {:ok, Map.get(formats, :currency) || "¤#,##0.00"}
        format -> {:ok, format}
      end
    end
  end

  defp resolve_currency_struct(nil, _locale) do
    {:error, "currency option is required for :currency format"}
  end

  defp resolve_currency_struct(currency_code, locale) when is_binary(currency_code) do
    with {:ok, code} <- Localize.Currency.validate_currency(currency_code) do
      locale_id =
        case locale do
          %Localize.LanguageTag{cldr_locale_id: id} when not is_nil(id) -> id
          _ -> :en
        end

      Localize.Currency.currency_for_code(code, locale: locale_id)
    end
  end

  defp resolve_currency_struct(currency_code, locale) when is_atom(currency_code) do
    resolve_currency_struct(Atom.to_string(currency_code), locale)
  end

  @dialyzer {:nowarn_function, resolve_currency_symbol: 2}
  defp resolve_currency_symbol(currency_struct, nil) do
    currency_struct.symbol
  end

  defp resolve_currency_symbol(currency_struct, :narrow) do
    currency_struct.narrow_symbol || currency_struct.symbol
  end

  defp resolve_currency_symbol(currency_struct, :iso) do
    to_string(currency_struct.code)
  end

  defp resolve_currency_spacing(locale, number_system) do
    case Localize.Number.Format.currency_spacing(locale, number_system) do
      {:error, _} ->
        case Localize.Number.System.number_system_from_locale(locale) do
          {:ok, default_system} when default_system != number_system ->
            Localize.Number.Format.currency_spacing(locale, default_system)

          _ ->
            nil
        end

      spacing ->
        spacing
    end
  end

  # ── Date/time option mapping ───────────────────────────────────

  defp map_date_options(localize_opts, func_opts, format_key) do
    style =
      func_opts[:style] || func_opts[:length] || func_opts[:dateStyle] || func_opts[:dateLength]

    if style do
      Keyword.put(localize_opts, format_key, parse_date_style(style))
    else
      localize_opts
    end
  end

  defp map_time_options(localize_opts, func_opts, format_key) do
    style =
      func_opts[:style] || func_opts[:precision] || func_opts[:timeStyle] ||
        func_opts[:timePrecision]

    if style do
      Keyword.put(localize_opts, format_key, parse_time_style(style))
    else
      localize_opts
    end
  end

  defp map_datetime_options(localize_opts, func_opts) do
    if style = func_opts[:style] do
      parsed = parse_date_style(style)
      localize_opts |> Keyword.put(:date_format, parsed) |> Keyword.put(:time_format, parsed)
    else
      localize_opts
      |> map_date_options(func_opts, :date_format)
      |> map_time_options(func_opts, :time_format)
    end
  end

  defp parse_date_style(style) when is_binary(style) do
    case style do
      "short" -> :short
      "medium" -> :medium
      "long" -> :long
      "full" -> :full
      other -> other
    end
  end

  defp parse_time_style(style) when is_binary(style) do
    case style do
      "short" -> :short
      "medium" -> :medium
      "long" -> :long
      "full" -> :full
      "second" -> :medium
      "minute" -> :short
      other -> other
    end
  end

  # ── Unit option mapping ────────────────────────────────────────

  defp map_unit_options(localize_opts, func_opts) do
    case func_opts[:unitDisplay] do
      "long" -> Keyword.put(localize_opts, :format, :long)
      "short" -> Keyword.put(localize_opts, :format, :short)
      "narrow" -> Keyword.put(localize_opts, :format, :narrow)
      _other -> localize_opts
    end
  end

  # ── List option mapping ────────────────────────────────────────
  #
  # Maps the MF2 `:list` function options onto the keyword
  # arguments expected by `Localize.List.to_string/2`. Recognised
  # MF2 option names:
  #
  #   * `style` — short for `:list_style`. Accepts any of the atoms
  #     returned by `Localize.List.known_list_styles/0` (`"and"`,
  #     `"or"`, `"unit"`, etc., plus the `"_short"`/`"_narrow"`
  #     variants). Maps to the corresponding `:standard`/`:or`/
  #     `:unit*` CLDR list style. The shorthands `"and"`, `"or"`,
  #     and `"unit"` are translated to `:standard`, `:or`, and
  #     `:unit` respectively.
  #
  #   * `type` — alias for `style`, accepted for symmetry with
  #     other MF2 functions that use `type` to switch presentation
  #     mode.

  defp map_list_options(localize_opts, func_opts) do
    style = func_opts[:style] || func_opts[:type]
    add_list_style(localize_opts, style)
  end

  defp add_list_style(opts, nil), do: opts
  defp add_list_style(opts, "and"), do: Keyword.put(opts, :list_style, :standard)
  defp add_list_style(opts, "and-short"), do: Keyword.put(opts, :list_style, :standard_short)
  defp add_list_style(opts, "and-narrow"), do: Keyword.put(opts, :list_style, :standard_narrow)
  defp add_list_style(opts, "or"), do: Keyword.put(opts, :list_style, :or)
  defp add_list_style(opts, "or-short"), do: Keyword.put(opts, :list_style, :or_short)
  defp add_list_style(opts, "or-narrow"), do: Keyword.put(opts, :list_style, :or_narrow)
  defp add_list_style(opts, "unit"), do: Keyword.put(opts, :list_style, :unit)
  defp add_list_style(opts, "unit-short"), do: Keyword.put(opts, :list_style, :unit_short)
  defp add_list_style(opts, "unit-narrow"), do: Keyword.put(opts, :list_style, :unit_narrow)

  defp add_list_style(opts, value) when is_binary(value) do
    # Surface unknown MF2 style names as an invalid value so messages
    # with typos or attacker-supplied junk fail loudly rather than
    # silently formatting with the default style. Previously this
    # clause called `String.to_atom/1` on the raw binary, which grew
    # the atom table for every distinct unknown string before the
    # downstream `Localize.List` rejected it.
    #
    # The "invalid" sentinel is an atom that's guaranteed not to be
    # a valid list style; `Localize.List.to_string/2` rejects it via
    # its existing `InvalidValueError` path.
    Keyword.put(opts, :list_style, :__invalid_mf2_list_style__)
  end

  # ── Type coercion and validation ───────────────────────────────

  defp ensure_number(value) when is_number(value), do: {:ok, value}
  defp ensure_number(%Decimal{} = value), do: {:ok, value}

  defp ensure_number(value) when is_binary(value) do
    # TR35 Bad Operand: a string operand must match the MF2
    # `number-literal` production — no leading zeros, no leading
    # plus sign, no grouping separators.
    if String.match?(value, ~r/^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][-+]?[0-9]+)?$/) do
      case parse_number(value) do
        num when is_number(num) -> {:ok, num}
        _ -> {:error, "cannot parse #{inspect(value)} as a number."}
      end
    else
      {:error, "#{inspect(value)} is not a valid number-literal operand."}
    end
  end

  defp ensure_number(value) do
    {:error,
     "cannot format #{inspect(value)} as a number. " <>
       "Expected a number or a numeric string."}
  end

  defp ensure_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, date}
      {:error, _} -> date_from_naive_datetime_string(value)
    end
  end

  defp ensure_date(%Date{} = value), do: {:ok, value}
  defp ensure_date(%NaiveDateTime{} = value), do: {:ok, NaiveDateTime.to_date(value)}
  defp ensure_date(%DateTime{} = value), do: {:ok, DateTime.to_date(value)}

  defp ensure_date(value) do
    {:error,
     "cannot format #{inspect(value)} as a date. " <>
       "Expected a Date, NaiveDateTime, DateTime, or ISO 8601 date string."}
  end

  defp date_from_naive_datetime_string(value) do
    case NaiveDateTime.from_iso8601(value) do
      {:ok, ndt} -> {:ok, NaiveDateTime.to_date(ndt)}
      {:error, _} -> date_from_datetime_string(value)
    end
  end

  defp date_from_datetime_string(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} ->
        {:ok, DateTime.to_date(dt)}

      {:error, _} ->
        {:error,
         "cannot parse #{inspect(value)} as a date. " <>
           "Expected an ISO 8601 date string."}
    end
  end

  defp ensure_datetime(value) when is_binary(value) do
    case NaiveDateTime.from_iso8601(value) do
      {:ok, ndt} -> {:ok, ndt}
      {:error, _} -> datetime_from_datetime_string(value)
    end
  end

  defp ensure_datetime(%NaiveDateTime{} = value), do: {:ok, value}
  defp ensure_datetime(%DateTime{} = value), do: {:ok, value}
  defp ensure_datetime(%Date{} = value), do: {:ok, NaiveDateTime.new!(value, ~T[00:00:00])}

  defp ensure_datetime(value) do
    {:error,
     "cannot format #{inspect(value)} as a datetime. " <>
       "Expected a NaiveDateTime, DateTime, Date, or ISO 8601 datetime string."}
  end

  defp datetime_from_datetime_string(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} -> {:ok, dt}
      {:error, _} -> datetime_from_date_string(value)
    end
  end

  defp datetime_from_date_string(value) do
    case Date.from_iso8601(value) do
      {:ok, date} ->
        {:ok, NaiveDateTime.new!(date, ~T[00:00:00])}

      {:error, _} ->
        {:error,
         "cannot parse #{inspect(value)} as a datetime. " <>
           "Expected an ISO 8601 datetime string."}
    end
  end

  # ── Variable and binding helpers ───────────────────────────────

  defp resolve_variable(name, bindings) when is_map(bindings) do
    cond do
      Map.has_key?(bindings, name) ->
        {:ok, Map.get(bindings, name)}

      atom_key_exists?(name) && Map.has_key?(bindings, String.to_existing_atom(name)) ->
        {:ok, Map.get(bindings, String.to_existing_atom(name))}

      true ->
        :error
    end
  end

  defp normalize_binding_keys(bindings) when is_map(bindings) do
    Map.new(bindings, fn
      {key, value} when is_binary(key) ->
        {:unicode.characters_to_nfc_binary(key), value}

      {key, value} ->
        {key, value}
    end)
  end

  # Resolves function option values against the bindings. An option
  # whose value is an unbound variable is an MF2 resolution error
  # (see "Unresolved Variable" in tr35-messageFormat.md), surfaced
  # as `{:unbound, var_name}` so callers report it like an unbound
  # operand rather than silently dropping the option.
  defp resolve_func_options(func_options, bindings) do
    Enum.reduce_while(func_options, {:ok, %{}}, fn
      {:option, name, {:literal, value}}, {:ok, acc} ->
        {:cont, {:ok, Map.put(acc, option_key(name), value)}}

      {:option, name, {:number_literal, value}}, {:ok, acc} ->
        {:cont, {:ok, Map.put(acc, option_key(name), parse_number(value))}}

      {:option, name, {:variable, var_name}}, {:ok, acc} ->
        case resolve_variable(var_name, bindings) do
          {:ok, value} -> {:cont, {:ok, Map.put(acc, option_key(name), value)}}
          :error -> {:halt, {:unbound, var_name}}
        end
    end)
  end

  defp resolve_locale_options(options) do
    locale = Keyword.get(options, :locale, Localize.get_locale())
    opts = [locale: locale]
    maybe_add_backend(opts, options)
  end

  defp maybe_add_backend(opts, options) do
    case Keyword.get(options, :backend) do
      nil ->
        opts

      backend ->
        Keyword.put(opts, :backend, backend)
    end
  end

  # ── General utilities ──────────────────────────────────────────

  defp option_key(name) do
    Helpers.existing_atom(name) || name
  end

  # TR35 Bad Option: a digit size option must be a non-negative
  # integer (the `digit-size-option` production).
  defp digit_size_option(func_opts, key) do
    case Map.get(func_opts, key) do
      nil ->
        {:ok, nil}

      value when is_integer(value) and value >= 0 ->
        {:ok, value}

      value when is_binary(value) ->
        case Integer.parse(value) do
          {int, ""} when int >= 0 -> {:ok, int}
          _ -> digit_size_error(key, value)
        end

      value ->
        digit_size_error(key, value)
    end
  end

  defp digit_size_error(key, value) do
    {:error, "the #{key} option must be a non-negative integer, got #{inspect(value)}"}
  end

  defp atom_key_exists?(name) do
    Helpers.existing_atom(name) != nil
  end

  defp parse_number(str) when is_binary(str) do
    case Integer.parse(str) do
      {int, ""} ->
        int

      {_, _} ->
        case Float.parse(str) do
          {float, ""} -> float
          _ -> str
        end

      :error ->
        case Float.parse(str) do
          {float, ""} -> float
          _ -> str
        end
    end
  end

  defp to_string_value(nil), do: ""
  defp to_string_value(value) when is_binary(value), do: value
  defp to_string_value(value) when is_integer(value), do: Integer.to_string(value)
  defp to_string_value(value) when is_float(value), do: Float.to_string(value)
  defp to_string_value(value), do: Kernel.to_string(value)

  # ── Bidirectional text isolation ─────────────────────────────────

  # Unicode bidi isolate characters
  @lri "\u2066"
  @rli "\u2067"
  @fsi "\u2068"
  @pdi "\u2069"

  # RTL scripts that trigger automatic bidi isolation
  @rtl_scripts ~w(Arab Hebr Thaa Syrc Mand Samr Nkoo Tfng Adlm)a

  defp extract_dir_attribute(attrs) do
    Enum.find_value(attrs, nil, fn
      {:attribute, {:namespace, "u", "dir"}, {:literal, dir}} -> dir
      {:attribute, "u:dir", {:literal, dir}} -> dir
      _ -> nil
    end)
  end

  defp apply_bidi_isolation(value, :none, nil, _options), do: value

  defp apply_bidi_isolation(value, _mode, dir, _options) when dir != nil do
    {open, close} = bidi_marks_for_dir(dir)
    [open, value, close]
  end

  defp apply_bidi_isolation(value, :isolate, _dir, _options) do
    [@fsi, value, @pdi]
  end

  defp apply_bidi_isolation(value, :auto, _dir, options) do
    if locale_is_rtl?(options) do
      [@fsi, value, @pdi]
    else
      value
    end
  end

  defp bidi_marks_for_dir("ltr"), do: {@lri, @pdi}
  defp bidi_marks_for_dir("rtl"), do: {@rli, @pdi}
  defp bidi_marks_for_dir("auto"), do: {@fsi, @pdi}
  defp bidi_marks_for_dir(_), do: {@fsi, @pdi}

  defp locale_is_rtl?(options) do
    locale = Keyword.get(options, :locale)

    case locale do
      nil ->
        false

      locale ->
        with {:ok, tag} <- Localize.validate_locale(locale),
             {:ok, expanded} <- Localize.LanguageTag.add_likely_subtags(tag) do
          expanded.script in @rtl_scripts
        else
          _ -> false
        end
    end
  end
end
