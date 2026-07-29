defmodule Localize.Message do
  @moduledoc """
  Implements [ICU MessageFormat 2](https://unicode.org/reports/tr35/tr35-messageFormat.html)
  with functions to parse and interpolate messages.

  """
  alias Localize.Message.{Interpreter, Parser, Print}

  import Kernel, except: [to_string: 1]

  @type message :: binary()
  @type bindings :: list() | map()
  @type options :: Keyword.t()

  @typedoc """
  The payload of a `{:format_error, payload}` return: either
  unbalanced markup in the message, or a formatter failure with the
  underlying exception or reason.

  """
  @type format_error_payload ::
          {:unbalanced_markup, :unclosed | {:mismatched_close, String.t()}}
          | {:formatter_failed, Exception.t() | String.t()}

  @doc """
  Format an MF2 message into a string.

  The ICU MessageFormat 2 uses message patterns with variable-element
  placeholders enclosed in {curly braces}. The argument syntax can
  include formatting details via annotation functions.

  ### Arguments

  * `message` is an MF2 message string.

  * `bindings` is a map or keyword list of arguments that
    are used to replace placeholders in the message.

  * `options` is a keyword list of options.

  ### Options

  * `:locale` is any valid locale name or a `t:Localize.LanguageTag` struct.

  * `:trim` determines if the message is trimmed
    of whitespace before formatting. The default is
    `false`.

  * `:backend` determines which formatting engine to use.
    Accepts `:nif` or `:elixir`. When set to `:nif`, the ICU NIF
    is used if available, otherwise falls back to the pure-Elixir
    interpreter. The default is `:elixir`.

  * `:functions` is a map of `%{String.t() => module()}` that
    registers custom MF2 formatting functions for this call.
    Each module must implement the `Localize.Message.Function`
    behaviour. Per-call functions take precedence over
    application-level functions registered via
    `config :localize, :mf2_functions`. See
    `Localize.Message.Function` for details.

  ### Returns

  * `{:ok, formatted_message}` on success.

  * `{:error, exception}` where `exception` is a `Localize.BindError`
    for unbound variables or a `Localize.FormatError` for formatting
    failures.

  ### Examples

      iex> Localize.Message.format("{{Hello {$name}!}}", %{"name" => "World"})
      {:ok, "Hello World!"}

  """

  @type backend :: :nif | :elixir

  @spec format(String.t(), bindings(), options()) ::
          {:ok, String.t()} | {:error, Exception.t()}

  def format(message, bindings \\ %{}, options \\ []) when is_binary(message) do
    case Localize.Backend.resolve(options) do
      :nif -> format_nif(message, bindings, Keyword.delete(options, :backend))
      :elixir -> format_elixir(message, bindings, Keyword.delete(options, :backend))
    end
  end

  defp format_elixir(message, bindings, options) do
    # Validate the locale up front so an invalid `:locale` option is
    # reported on the Elixir backend just as it is on the NIF backend,
    # even for messages that never reach a locale-sensitive function.
    with {:ok, message} <- maybe_trim(message, options[:trim]),
         {:ok, _language_tag} <- validate_locale_option(options),
         {:ok, parsed} <- parse_and_validate(message, :format) do
      format_options =
        options
        |> Keyword.put_new(:locale, Localize.get_locale())

      case Interpreter.format_list(parsed, bindings, format_options) do
        {:ok, iolist, _bound, []} ->
          {:ok, :erlang.iolist_to_binary(iolist)}

        {:error, _iolist, _bound, unbound} ->
          {:error, Localize.BindError.exception(unbound: unbound)}

        {:format_error, payload} ->
          {:error, format_error_from_payload(message, :format, payload)}
      end
    end
  end

  defp format_nif(message, bindings, options) do
    with {:ok, message} <- maybe_trim(message, options[:trim]),
         {:ok, locale_string} <- resolve_locale_string(options) do
      bindings_map = normalize_bindings(bindings)

      case check_unbound_variables(message, bindings_map) do
        {:error, _} = error ->
          error

        :ok ->
          json_binary = IO.iodata_to_binary(:json.encode(bindings_map))
          nif_result = Localize.Nif.mf2_format(message, locale_string, json_binary)
          handle_nif_format(nif_result, message, bindings, options)
      end
    end
  end

  defp handle_nif_format({:ok, ""}, message, bindings, options) do
    # ICU MF2 (tech preview) may return empty strings for
    # messages with declarations. Fall back to the Elixir
    # interpreter for a correct result.
    format_elixir(message, bindings, options)
  end

  defp handle_nif_format({:ok, formatted}, _message, _bindings, _options) do
    {:ok, formatted}
  end

  defp handle_nif_format({:error, detail}, message, _bindings, _options) do
    {:error,
     Localize.ParseError.exception(
       input: message,
       reason: :invalid_message_format,
       detail: detail
     )}
  end

  @dialyzer {:nowarn_function, check_unbound_variables: 2}
  defp check_unbound_variables(message, bindings_map) do
    case Parser.parse(message) do
      {:ok, ast} ->
        required = extract_required_variables(ast)
        provided = MapSet.new(Map.keys(bindings_map))
        unbound = MapSet.difference(required, provided) |> MapSet.to_list()

        if unbound == [] do
          :ok
        else
          {:error, Localize.BindError.exception(unbound: unbound)}
        end

      {:error, _reason} ->
        # Let the NIF handle parse errors
        :ok
    end
  end

  defp extract_required_variables(ast) do
    {variables, locals} = collect_variables(ast, MapSet.new(), MapSet.new())
    MapSet.difference(variables, locals)
  end

  defp collect_variables(list, variables, locals) when is_list(list) do
    Enum.reduce(list, {variables, locals}, fn element, {vars, lcls} ->
      collect_variables(element, vars, lcls)
    end)
  end

  defp collect_variables({:complex, declarations, pattern}, variables, locals) do
    {variables, locals} = collect_variables(declarations, variables, locals)
    collect_variables(pattern, variables, locals)
  end

  defp collect_variables({:local, {:variable, name}, expression}, variables, locals) do
    {variables, locals} = collect_variables(expression, variables, locals)
    {variables, MapSet.put(locals, name)}
  end

  defp collect_variables({:input, expression}, variables, locals) do
    collect_variables(expression, variables, locals)
  end

  defp collect_variables({:quoted_pattern, parts}, variables, locals) do
    collect_variables(parts, variables, locals)
  end

  defp collect_variables({:expression, operand, function, _attributes}, variables, locals) do
    variables = collect_operand_variables(operand, variables)
    collect_function_variables(function, variables, locals)
  end

  defp collect_variables({:text, _}, variables, locals), do: {variables, locals}
  defp collect_variables({:markup, _, _, _}, variables, locals), do: {variables, locals}
  defp collect_variables(_, variables, locals), do: {variables, locals}

  defp collect_operand_variables({:variable, name}, variables) do
    MapSet.put(variables, name)
  end

  defp collect_operand_variables(_, variables), do: variables

  defp collect_function_variables(nil, variables, locals), do: {variables, locals}

  defp collect_function_variables({:function, _name, func_options}, variables, locals) do
    Enum.reduce(func_options, {variables, locals}, fn
      {:option, _key, {:variable, name}}, {vars, lcls} ->
        {MapSet.put(vars, name), lcls}

      _, acc ->
        acc
    end)
  end

  defp validate_locale_option(options) do
    options
    |> Keyword.get(:locale, Localize.get_locale())
    |> Localize.validate_locale()
  end

  # The NIF backend validates the locale through the same canonical
  # path as the Elixir backend (`Localize.validate_locale/1`) and hands
  # ICU the canonical BCP 47 string, so both backends resolve aliases,
  # likely subtags and `-u-` extensions identically.
  defp resolve_locale_string(options) do
    locale = Keyword.get(options, :locale, Localize.get_locale())

    with {:ok, language_tag} <- Localize.validate_locale(locale) do
      {:ok, Localize.LanguageTag.to_string(language_tag)}
    end
  end

  defp normalize_bindings(bindings) when is_map(bindings) do
    Map.new(bindings, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
  end

  defp normalize_bindings(bindings) when is_list(bindings) do
    Map.new(bindings, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
  end

  defp normalize_bindings(bindings), do: bindings

  @doc """
  Formats a message and returns the result or raises on error.

  Same as `format/3` but returns the formatted string directly
  or raises an exception.

  ### Arguments

  * `message` is an MF2 message string.

  * `bindings` is a map or keyword list of arguments.

  * `options` is a keyword list of options.

  ### Options

  * See `format/3` for the supported options.

  ### Returns

  * The formatted string.

  ### Examples

      iex> Localize.Message.format!("{{Hello {$name}!}}", %{"name" => "World"})
      "Hello World!"

  """
  @spec format!(String.t(), bindings(), options()) :: String.t() | no_return

  def format!(message, bindings \\ %{}, options \\ []) when is_binary(message) do
    case format(message, bindings, options) do
      {:ok, binary} ->
        binary

      {:error, exception} ->
        raise exception
    end
  end

  @doc """
  Format an MF2 message into an iolist.

  ### Arguments

  * `message` is an MF2 message string.

  * `bindings` is a map or keyword list of arguments that
    are used to replace placeholders in the message.

  * `options` is a keyword list of options.

  ### Options

  * `:locale` is any valid locale name or a language tag struct.

  * `:trim` determines if the message is trimmed
    of whitespace before formatting. The default is
    `false`.

  ### Returns

  * `{:ok, iolist, bound, unbound}` on success.

  * `{:error, iolist, bound, unbound}` when bindings are missing.

  * `{:format_error, reason}` on format error.

  ### Examples

      iex> Localize.Message.format_to_iolist("{{Hello {$name}!}}", %{"name" => "World"})
      {:ok, ["Hello ", "World", "!"], ["name"], []}

  """
  @spec format_to_iolist(String.t(), bindings(), options()) ::
          {:ok, list(), list(), list()}
          | {:error, list(), list(), list()}
          | {:error, Localize.ParseError.t()}
          | {:format_error, format_error_payload()}

  def format_to_iolist(message, bindings \\ %{}, options \\ []) when is_binary(message) do
    with {:ok, message} <- maybe_trim(message, options[:trim]),
         {:ok, parsed} <- parse_and_validate(message, :format_to_iolist) do
      Interpreter.format_list(parsed, bindings, options)
    end
  end

  @doc """
  Formats a message into a list of text and markup nodes preserving
  markup structure.

  Unlike `format/3`, which strips markup tags from the output, this
  function returns a nested tree of `{:text, String.t()}` and
  `{:markup, name, options, children}` tuples. This is the foundation
  for HTML/HEEX renderers in companion packages.

  The caller is responsible for turning markup nodes into actual
  output (HTML elements, function components, etc.). Text nodes are
  returned as raw strings — escaping is the renderer's responsibility.

  ### Arguments

  * `message` is an MF2 message in binary form.

  * `bindings` is a map or keyword list of variable bindings.
    The default is `%{}`.

  * `options` is a keyword list of options. The default is `[]`.

  ### Options

  * `:locale` is a locale name or a `t:Localize.LanguageTag.t/0`.
    The default is `Localize.get_locale/0`.

  * `:trim` determines if the message is trimmed of whitespace
    before formatting. The default is `false`.

  * `:functions` is a map of custom MF2 function modules.
    See `Localize.Message.Function`.

  ### Returns

  * `{:ok, nodes}` on success, where `nodes` is a list of
    `safe_node()` tuples.

  * `{:error, exception}` on parse or format error, including
    unbalanced markup or unbound variables.

  ### Examples

      iex> Localize.Message.format_to_safe_list(
      ...>   "Hello {$name}, click {#link href=|/home|}here{/link}!",
      ...>   %{"name" => "Kip"}
      ...> )
      {:ok, [
        {:text, "Hello Kip, click "},
        {:markup, "link", %{"href" => "/home"}, [{:text, "here"}]},
        {:text, "!"}
      ]}

      iex> Localize.Message.format_to_safe_list("Just text")
      {:ok, [{:text, "Just text"}]}

      iex> Localize.Message.format_to_safe_list("{#br/}")
      {:ok, [{:markup, "br", %{}, []}]}

  """
  @type safe_node ::
          {:text, String.t()}
          | {:markup, String.t(), %{String.t() => term()}, [safe_node()]}

  @spec format_to_safe_list(String.t(), bindings(), options()) ::
          {:ok, [safe_node()]} | {:error, Exception.t()}

  def format_to_safe_list(message, bindings \\ %{}, options \\ []) when is_binary(message) do
    with {:ok, message} <- maybe_trim(message, options[:trim]),
         {:ok, parsed} <- parse_and_validate(message, :format_to_safe_list) do
      case Interpreter.format_structured(parsed, bindings, options) do
        {:ok, nodes, _bound, _unbound} ->
          {:ok, nodes}

        {:error, _nodes, _bound, unbound} ->
          {:error, Localize.BindError.exception(unbound: unbound)}

        {:format_error, payload} ->
          {:error, format_error_from_payload(message, :format, payload)}
      end
    else
      {:error, %Localize.ParseError{}} = error ->
        error
    end
  end

  # `Parser.parse/1` checks syntax only; the TR35 data-model rules are a
  # separate pass (see `Localize.Message.Validator`). Every entry point
  # that formats or serializes a message composes the two here, so a
  # syntax error is reported before a data-model one. Tooling that must
  # accept invalid input — `to_tokens/2` and the highlighters built on
  # it — deliberately calls `Parser.parse/1` alone.
  defp parse_and_validate(message, function) do
    with {:ok, ast} <- Parser.parse(message) do
      case Localize.Message.Validator.validate(ast) do
        :ok ->
          {:ok, ast}

        {:error, payload} ->
          {:error, format_error_from_payload(message, function, {:data_model, payload})}
      end
    end
  end

  defp format_error_from_payload(message, function, {:unbalanced_markup, :unclosed}) do
    Localize.FormatError.exception(
      value: message,
      function: function,
      reason: :unbalanced_markup
    )
  end

  defp format_error_from_payload(
         message,
         function,
         {:unbalanced_markup, {:mismatched_close, name}}
       ) do
    Localize.FormatError.exception(
      value: message,
      function: function,
      reason: :mismatched_close,
      detail: inspect(name)
    )
  end

  defp format_error_from_payload(
         message,
         function,
         {:formatter_failed, %{__exception__: true} = exception}
       ) do
    Localize.FormatError.exception(
      value: message,
      function: function,
      reason: :formatter_failed,
      cause: exception
    )
  end

  defp format_error_from_payload(message, function, {:formatter_failed, detail})
       when is_binary(detail) do
    Localize.FormatError.exception(
      value: message,
      function: function,
      reason: :formatter_failed,
      detail: detail
    )
  end

  defp format_error_from_payload(message, function, {:data_model, {reason, detail}})
       when reason in [
              :duplicate_declaration,
              :duplicate_option_name,
              :duplicate_variant,
              :missing_selector_annotation,
              :variant_key_mismatch,
              :missing_fallback_variant
            ] do
    Localize.FormatError.exception(
      value: message,
      function: function,
      reason: reason,
      detail: detail
    )
  end

  defp format_error_from_payload(message, function, {:unknown_function, name}) do
    Localize.FormatError.exception(
      value: message,
      function: function,
      reason: :unknown_function,
      detail: name
    )
  end

  @doc """
  Same as `format_to_safe_list/3` but raises on error.

  ### Arguments

  * `message` is an MF2 message string.

  * `bindings` is a map of variable bindings.

  * `options` is a keyword list of options.

  ### Options

  * See `format_to_safe_list/3` for the supported options.

  ### Returns

  * A list of `safe_node()` tuples.

  * Raises an exception on parse or format error, including
    unbalanced markup or unbound variables.

  ### Examples

      iex> Localize.Message.format_to_safe_list!("Hello {$name}!", %{"name" => "World"})
      [text: "Hello World!"]

  """
  @spec format_to_safe_list!(String.t(), bindings(), options()) :: [safe_node()]

  def format_to_safe_list!(message, bindings \\ %{}, options \\ []) when is_binary(message) do
    case format_to_safe_list(message, bindings, options) do
      {:ok, nodes} -> nodes
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Formats a message into a canonical form.

  This allows for messages to be compared directly, or using
  `jaro_distance/3`.

  ### Arguments

  * `message` is an MF2 message in binary form.

  * `options` is a keyword list of options. The default is `[]`.

  ### Options

  * `:trim` determines if the message is trimmed
    of whitespace before formatting. The default is `true`.

  ### Returns

  * `{:ok, canonical_message}` as a string.

  * `{:error, reason}` on parse error.

  ### Examples

      iex> Localize.Message.canonical_message("{{Hello {$name}!}}")
      {:ok, "{{Hello {$name}!}}"}

  """
  @spec canonical_message(String.t(), Keyword.t()) ::
          {:ok, String.t()} | {:error, Localize.ParseError.t()}

  def canonical_message(message, options \\ []) do
    options = Keyword.put_new(options, :trim, true)

    with {:ok, message} <- maybe_trim(message, options[:trim]),
         {:ok, ast} <- parse_and_validate(message, :canonical_message) do
      {:ok, Print.to_string(ast, options)}
    end
  end

  @doc """
  Formats a message into a canonical form or raises if the message
  cannot be parsed.

  ### Arguments

  * `message` is an MF2 message in binary form.

  * `options` is a keyword list of options. See `canonical_message/2`.

  ### Returns

  * The canonical message as a string.

  ### Examples

      iex> Localize.Message.canonical_message!("{{Hello {$name}!}}")
      "{{Hello {$name}!}}"

  """
  @spec canonical_message!(String.t(), Keyword.t()) :: String.t() | no_return

  def canonical_message!(message, options \\ []) do
    case canonical_message(message, options) do
      {:ok, message} -> message
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Parses an MF2 message and returns a classified token stream for
  syntax highlighting.

  Each token is a `{class, text}` tuple where `class` is one of the
  atoms documented in `Localize.Message.Highlighter`. Concatenating
  every token's text yields the canonical MF2 message.

  Use this when you want to produce your own rendered output. For
  HTML or ANSI output, prefer `to_html/2` or `to_ansi/2`.

  ### Arguments

  * `message` is an MF2 message in binary form.

  * `options` is a keyword list. The `:trim` option (default `true`)
    strips leading and trailing whitespace before parsing.

  ### Returns

  * `{:ok, tokens}` where `tokens` is a list of `{class, text}`
    tuples.

  * `{:error, reason}` if the message cannot be parsed.

  ### Examples

      iex> {:ok, tokens} = Localize.Message.to_tokens("Hello {$name}!")
      iex> Enum.map(tokens, &elem(&1, 0))
      [:text, :punctuation_bracket, :variable, :punctuation_bracket, :text]

  """
  @spec to_tokens(String.t(), Keyword.t()) ::
          {:ok, [Localize.Message.Highlighter.token()]} | {:error, Localize.ParseError.t()}

  def to_tokens(message, options \\ []) do
    options = Keyword.put_new(options, :trim, true)

    with {:ok, message} <- maybe_trim(message, options[:trim]),
         {:ok, ast} <- Parser.parse(message) do
      {:ok, Localize.Message.Highlighter.to_tokens(ast)}
    end
  end

  @doc """
  Parses an MF2 message and returns it formatted as HTML with
  per-token `<span>` wrappers for syntax highlighting.

  ### Arguments

  * `message` is an MF2 message in binary form.

  * `options` is a keyword list.

  ### Options

  * `:trim` — whitespace trim before parse (default `true`).

  * `:standalone` — wraps the output in a `<pre><code>` block
    (default `false`).

  * `:wrapper_tag`, `:wrapper_class`, `:span_tag`, `:class_prefix` —
    see `Localize.Message.Formatter.HTML` for details.

  ### Returns

  * `{:ok, html}` on success.

  * `{:error, reason}` if the message cannot be parsed.

  ### Examples

      iex> {:ok, html} = Localize.Message.to_html("Hello {$name}!")
      iex> String.contains?(html, ~s(<span class="mf2-variable">$name</span>))
      true

  """
  @spec to_html(String.t(), Keyword.t()) ::
          {:ok, String.t()} | {:error, Localize.ParseError.t()}

  def to_html(message, options \\ []) do
    with {:ok, tokens} <- to_tokens(message, options) do
      {:ok, Localize.Message.Formatter.HTML.render(tokens, options)}
    end
  end

  @doc """
  Parses an MF2 message and returns it formatted with ANSI colour
  codes for terminal display.

  ### Arguments

  * `message` is an MF2 message in binary form.

  * `options` is a keyword list.

  ### Options

  * `:trim` — whitespace trim before parse (default `true`).

  * `:palette` — a map overriding the default class-to-colour
    mapping. See `Localize.Message.Formatter.ANSI`.

  ### Returns

  * `{:ok, ansi_string}` on success.

  * `{:error, reason}` if the message cannot be parsed.

  ### Examples

      iex> {:ok, ansi} = Localize.Message.to_ansi("Hello {$name}!")
      iex> String.contains?(ansi, "\\e[")
      true

  """
  @spec to_ansi(String.t(), Keyword.t()) ::
          {:ok, String.t()} | {:error, Localize.ParseError.t()}

  def to_ansi(message, options \\ []) do
    with {:ok, tokens} <- to_tokens(message, options) do
      {:ok, Localize.Message.Formatter.ANSI.render(tokens, options)}
    end
  end

  @doc """
  Returns the Jaro distance between two messages.

  This allows for fuzzy matching of messages which can be helpful
  when a message string is changed but the semantics remain the same.

  ### Arguments

  * `message1` is an MF2 message in binary form.

  * `message2` is an MF2 message in binary form.

  * `options` is a keyword list of options. The default is `[]`.

  ### Options

  * `:trim` determines if the message is trimmed
    of whitespace before formatting. The default is `false`.

  ### Returns

  * `{:ok, distance}` where `distance` is a float between 0.0 and 1.0.

  * `{:error, reason}` on parse error.

  ### Examples

      iex> Localize.Message.jaro_distance("{{Hello}}", "{{Hello}}")
      {:ok, 1.0}

  """
  @spec jaro_distance(String.t(), String.t(), Keyword.t()) ::
          {:ok, float()} | {:error, Localize.ParseError.t()}

  def jaro_distance(message1, message2, options \\ []) do
    with {:ok, message1} <- maybe_trim(message1, options[:trim]),
         {:ok, message2} <- maybe_trim(message2, options[:trim]),
         {:ok, message1_ast} <- Parser.parse(message1),
         {:ok, message2_ast} <- Parser.parse(message2) do
      canonical_message1 = Print.to_string(message1_ast)
      canonical_message2 = Print.to_string(message2_ast)
      {:ok, String.jaro_distance(canonical_message1, canonical_message2)}
    end
  end

  @doc """
  Returns the Jaro distance between two messages or raises.

  Same as `jaro_distance/3` but returns the distance directly.

  ### Arguments

  * `message1` is an MF2 message in binary form.

  * `message2` is an MF2 message in binary form.

  * `options` is a keyword list of options.

  ### Returns

  * A float distance between 0.0 and 1.0.

  ### Examples

      iex> Localize.Message.jaro_distance!("{{Hello}}", "{{Hello}}")
      1.0

  """
  @spec jaro_distance!(String.t(), String.t(), Keyword.t()) :: float() | no_return

  def jaro_distance!(message1, message2, options \\ []) do
    case jaro_distance(message1, message2, options) do
      {:ok, distance} -> distance
      {:error, exception} -> raise exception
    end
  end

  @doc false
  def default_options do
    [trim: false]
  end

  defp maybe_trim(message, true) do
    {:ok, String.trim(message)}
  end

  defp maybe_trim(message, _) do
    {:ok, message}
  end
end
