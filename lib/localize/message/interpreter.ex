defmodule Localize.Message.Interpreter do
  @moduledoc """
  Interprets a MessageFormat 2 AST and produces formatted output.

  The AST is produced by `Localize.Message.Parser` and uses tuples like
  `{:text, "..."}`, `{:expression, operand, function, attrs}`,
  `{:complex, declarations, body}`, `{:match, selectors, variants}`, etc.

  """

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
  @spec format_list(term(), map() | list(), Keyword.t()) ::
          {:ok, list(), list(), list()}
          | {:error, list(), list(), list()}
          | {:format_error, String.t()}
  def format_list(ast, bindings \\ %{}, options \\ [])

  def format_list(ast, bindings, options) when is_list(bindings) do
    format_list(ast, Map.new(bindings), options)
  end

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

      {bindings, bound, selector_meta} ->
        case body do
          {:quoted_pattern, parts} ->
            case format_pattern(parts, bindings, options) do
              {:ok, iolist, more_bound, unbound} ->
                {:ok, iolist, bound ++ more_bound, unbound}

              {:error, iolist, more_bound, unbound} ->
                {:error, iolist, bound ++ more_bound, unbound}

              {:format_error, _} = err ->
                err
            end

          {:match, selectors, variants} ->
            evaluate_match(selectors, variants, bindings, options, bound, selector_meta)
        end
    end
  end

  defp do_format_list({:quoted_pattern, parts}, bindings, options) do
    format_pattern(parts, bindings, options)
  end

  defp do_format_list({:match, selectors, variants}, bindings, options) do
    evaluate_match(selectors, variants, bindings, options, [], %{})
  end

  # ── Declaration resolution ───────────────────────────────────

  defp resolve_declarations(declarations, bindings, options) do
    Enum.reduce_while(declarations, {bindings, [], %{}}, fn decl,
                                                            {bindings_acc, bound_acc, sel_meta} ->
      case decl do
        {:input, {:expression, {:variable, name}, func, _attrs}} ->
          case resolve_variable(name, bindings_acc) do
            {:ok, value} ->
              case apply_function(value, func, Keyword.put(options, :bindings, bindings_acc)) do
                {:ok, formatted} ->
                  sel_value = selector_value(value, func)
                  sel_meta = Map.put(sel_meta, name, {sel_value, func})
                  bindings_acc = Map.put(bindings_acc, name, formatted)
                  {:cont, {bindings_acc, [name | bound_acc], sel_meta}}

                {:error, reason} ->
                  {:halt, {:format_error, format_error_reason(reason)}}
              end

            :error ->
              {:cont, {bindings_acc, bound_acc, sel_meta}}
          end

        {:local, {:variable, name}, {:expression, operand, func, _attrs}} ->
          case resolve_operand(operand, bindings_acc) do
            {:ok, value, _} ->
              case apply_function(value, func, Keyword.put(options, :bindings, bindings_acc)) do
                {:ok, formatted} ->
                  sel_value = selector_value(value, func)
                  sel_meta = Map.put(sel_meta, name, {sel_value, func})
                  bindings_acc = Map.put(bindings_acc, name, formatted)
                  {:cont, {bindings_acc, [name | bound_acc], sel_meta}}

                {:error, reason} ->
                  {:halt, {:format_error, format_error_reason(reason)}}
              end

            {:unbound, _} ->
              {:cont, {bindings_acc, bound_acc, sel_meta}}
          end
      end
    end)
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

  defp format_part({:text, text}, _bindings, _options) do
    {:ok, text, []}
  end

  defp format_part({:escape, char}, _bindings, _options) do
    {:ok, char, []}
  end

  defp format_part({:expression, operand, func, _attrs}, bindings, options) do
    format_expression(operand, func, bindings, options)
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
        case apply_function(value, func, Keyword.put(options, :bindings, bindings)) do
          {:ok, formatted} -> {:ok, formatted, bound_names}
          {:error, reason} -> {:format_error, format_error_reason(reason)}
        end

      {:unbound, name} ->
        {:unbound, name}
    end
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

  defp apply_function(value, nil, _options) do
    {:ok, to_string_value(value)}
  end

  defp apply_function(value, {:function, name, func_options}, options) do
    bindings = Keyword.get(options, :bindings, %{})
    func_opts = resolve_func_options(func_options, bindings)
    format_with_function(name, value, func_opts, options)
  end

  # ── Number formatting ──────────────────────────────────────────

  defp format_with_function("number", value, func_opts, options) do
    with {:ok, number} <- ensure_number(value),
         {:ok, localize_opts} <- build_localize_options(options, func_opts) do
      Localize.Number.to_string(number, localize_opts)
    end
  end

  defp format_with_function("integer", value, func_opts, options) do
    with {:ok, number} <- ensure_number(value),
         {:ok, localize_opts} <- build_localize_options(options, func_opts) do
      Localize.Number.to_string(trunc(number), localize_opts)
    end
  end

  defp format_with_function("percent", value, func_opts, options) do
    with {:ok, number} <- ensure_number(value),
         {:ok, localize_opts} <- build_localize_options(options, func_opts) do
      localize_opts = Keyword.put(localize_opts, :format, :percent)
      Localize.Number.to_string(number, localize_opts)
    end
  end

  defp format_with_function("currency", value, func_opts, options) do
    with {:ok, number} <- ensure_number(value),
         {:ok, localize_opts} <- build_localize_options(options, func_opts) do
      localize_opts = map_currency_options(localize_opts, func_opts)
      Localize.Number.to_string(number, localize_opts)
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
      case func_opts[:unit] do
        nil ->
          {:error, "the :unit function requires a `unit` option"}

        name ->
          with {:ok, unit} <- Localize.Unit.new(number, name) do
            localize_opts = resolve_locale_options(options)
            localize_opts = map_unit_options(localize_opts, func_opts)
            Localize.Unit.to_string(unit, localize_opts)
          end
      end
    end
  end

  # ── Fallback formatting ────────────────────────────────────────

  defp format_with_function(_name, value, _func_opts, _options) do
    {:ok, to_string_value(value)}
  end

  # ── Match evaluation ───────────────────────────────────────────

  defp evaluate_match(selectors, variants, bindings, options, bound, selector_meta) do
    selector_info =
      Enum.map(selectors, fn {:variable, name} ->
        formatted =
          case resolve_variable(name, bindings) do
            {:ok, value} -> value
            :error -> nil
          end

        {original_value, func} =
          case Map.get(selector_meta, name) do
            {orig, func} -> {orig, func}
            nil -> {formatted, nil}
          end

        %{name: name, formatted: formatted, original: original_value, func: func}
      end)

    selector_names = Enum.map(selector_info, & &1.name)

    case find_best_variant(selector_info, variants, options) do
      {:ok, {:variant, _keys, {:quoted_pattern, parts}}} ->
        case format_pattern(parts, bindings, options) do
          {:ok, iolist, more_bound, unbound} ->
            {:ok, iolist, bound ++ selector_names ++ more_bound, unbound}

          {:error, iolist, more_bound, unbound} ->
            {:error, iolist, bound ++ selector_names ++ more_bound, unbound}

          {:format_error, _} = err ->
            err
        end

      :error ->
        {:error, [], bound ++ selector_names, ["no matching variant"]}
    end
  end

  defp find_best_variant(selector_info, variants, options) do
    sorted =
      variants
      |> Enum.filter(fn {:variant, keys, _} ->
        match_keys?(selector_info, keys, options)
      end)
      |> Enum.sort_by(fn {:variant, keys, _} ->
        Enum.count(keys, &(&1 == :catchall))
      end)

    case sorted do
      [best | _] -> {:ok, best}
      [] -> :error
    end
  end

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

  defp selector_value(value, _func), do: value

  # ── Plural category resolution ────────────────────────────────

  defp plural_match_type(nil), do: nil

  defp plural_match_type({:function, name, func_options}) when name in ["number", "integer"] do
    select_opt =
      Enum.find_value(func_options, fn
        {:option, "select", {:literal, value}} -> value
        _ -> nil
      end)

    case select_opt do
      "exact" -> :exact
      "ordinal" -> :Ordinal
      _ -> :Cardinal
    end
  end

  defp plural_match_type(_), do: nil

  defp resolve_plural_category(value, plural_type, options) when is_number(value) do
    locale = Keyword.get(options, :locale)

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

  defp build_localize_options(options, func_opts) do
    localize_opts = resolve_locale_options(options)

    with {:ok, localize_opts} <- map_func_options(localize_opts, func_opts) do
      {:ok, localize_opts}
    end
  end

  defp map_func_options(localize_opts, func_opts) do
    min_fd = get_integer_option(func_opts, :minimumFractionDigits)
    max_fd = get_integer_option(func_opts, :maximumFractionDigits)
    use_grouping = Map.get(func_opts, :useGrouping)

    localize_opts =
      localize_opts
      |> map_fraction_digits(min_fd, max_fd, use_grouping)
      |> map_use_grouping(use_grouping)

    map_numbering_system(localize_opts, func_opts)
  end

  defp map_fraction_digits(localize_opts, nil, nil, _use_grouping) do
    localize_opts
  end

  defp map_fraction_digits(localize_opts, min_fd, nil, _use_grouping) do
    Keyword.put(localize_opts, :fractional_digits, min_fd)
  end

  defp map_fraction_digits(localize_opts, min_fd, max_fd, use_grouping) do
    min_fd = min_fd || 0
    grouping = if use_grouping == "never", do: "", else: "#,#"
    required = String.duplicate("0", min_fd)
    optional = String.duplicate("#", max(max_fd - min_fd, 0))
    decimal = if min_fd > 0 or max_fd > 0, do: ".", else: ""
    format = "#{grouping}#0#{decimal}#{required}#{optional}"
    Keyword.put(localize_opts, :format, format)
  end

  defp map_use_grouping(localize_opts, use_grouping) do
    case use_grouping do
      "never" ->
        if Keyword.has_key?(localize_opts, :format) do
          localize_opts
        else
          Keyword.put(localize_opts, :format, "##0.#")
        end

      "min2" ->
        Keyword.put(localize_opts, :minimum_grouping_digits, 2)

      _ ->
        localize_opts
    end
  end

  defp map_numbering_system(localize_opts, func_opts) do
    case Map.get(func_opts, :numberingSystem) do
      nil ->
        {:ok, localize_opts}

      system ->
        case safe_string_to_atom(system) do
          {:ok, atom} -> {:ok, Keyword.put(localize_opts, :number_system, atom)}
          {:error, :not_existing} -> {:error, "unknown numbering system #{inspect(system)}"}
        end
    end
  end

  defp map_currency_options(localize_opts, func_opts) do
    localize_opts = Keyword.put(localize_opts, :format, :currency)

    localize_opts =
      if currency = func_opts[:currency] do
        Keyword.put(localize_opts, :currency, currency)
      else
        localize_opts
      end

    localize_opts =
      case func_opts[:currencyDisplay] do
        "narrowSymbol" -> Keyword.put(localize_opts, :currency_symbol, :narrow)
        "code" -> Keyword.put(localize_opts, :currency_symbol, :iso)
        _other -> localize_opts
      end

    case func_opts[:currencySign] do
      "accounting" -> Keyword.put(localize_opts, :format, :accounting)
      _other -> localize_opts
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
      "long" -> Keyword.put(localize_opts, :style, :long)
      "short" -> Keyword.put(localize_opts, :style, :short)
      "narrow" -> Keyword.put(localize_opts, :style, :narrow)
      _other -> localize_opts
    end
  end

  # ── Type coercion and validation ───────────────────────────────

  defp ensure_number(value) when is_number(value), do: {:ok, value}

  defp ensure_number(value) when is_binary(value) do
    case parse_number(value) do
      num when is_number(num) -> {:ok, num}
      _ -> {:error, "cannot parse #{inspect(value)} as a number."}
    end
  end

  defp ensure_number(value) do
    {:error,
     "cannot format #{inspect(value)} as a number. " <>
       "Expected a number or a numeric string."}
  end

  defp ensure_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} ->
        {:ok, date}

      {:error, _} ->
        case NaiveDateTime.from_iso8601(value) do
          {:ok, ndt} ->
            {:ok, NaiveDateTime.to_date(ndt)}

          {:error, _} ->
            case DateTime.from_iso8601(value) do
              {:ok, dt, _offset} ->
                {:ok, DateTime.to_date(dt)}

              {:error, _} ->
                {:error,
                 "cannot parse #{inspect(value)} as a date. " <>
                   "Expected an ISO 8601 date string."}
            end
        end
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

  defp ensure_datetime(value) when is_binary(value) do
    case NaiveDateTime.from_iso8601(value) do
      {:ok, ndt} ->
        {:ok, ndt}

      {:error, _} ->
        case DateTime.from_iso8601(value) do
          {:ok, dt, _offset} ->
            {:ok, dt}

          {:error, _} ->
            case Date.from_iso8601(value) do
              {:ok, date} ->
                {:ok, NaiveDateTime.new!(date, ~T[00:00:00])}

              {:error, _} ->
                {:error,
                 "cannot parse #{inspect(value)} as a datetime. " <>
                   "Expected an ISO 8601 datetime string."}
            end
        end
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

  defp resolve_func_options(func_options, bindings) do
    Enum.reduce(func_options, %{}, fn
      {:option, name, {:literal, value}}, acc ->
        Map.put(acc, option_key(name), value)

      {:option, name, {:number_literal, value}}, acc ->
        Map.put(acc, option_key(name), parse_number(value))

      {:option, name, {:variable, var_name}}, acc ->
        case resolve_variable(var_name, bindings) do
          {:ok, value} -> Map.put(acc, option_key(name), value)
          :error -> Map.put(acc, option_key(name), nil)
        end
    end)
  end

  defp resolve_locale_options(options) do
    locale = Keyword.get(options, :locale)
    opts = if locale, do: [locale: locale], else: []
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

  defp format_error_reason({_module, message}) when is_binary(message), do: message
  defp format_error_reason(reason) when is_binary(reason), do: reason

  defp option_key(name) do
    case safe_string_to_atom(name) do
      {:ok, atom} -> atom
      {:error, :not_existing} -> name
    end
  end

  defp get_integer_option(func_opts, key) do
    case Map.get(func_opts, key) do
      nil ->
        nil

      value when is_integer(value) ->
        value

      value when is_float(value) ->
        round(value)

      value when is_binary(value) ->
        case Integer.parse(value) do
          {int, ""} -> int
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp atom_key_exists?(name) do
    match?({:ok, _}, safe_string_to_atom(name))
  end

  defp safe_string_to_atom(name) do
    {:ok, String.to_existing_atom(name)}
  rescue
    ArgumentError -> {:error, :not_existing}
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
end
