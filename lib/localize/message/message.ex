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
    with {:ok, message} <- maybe_trim(message, options[:trim]),
         {:ok, parsed} <- Parser.parse(message) do
      format_options =
        options
        |> Keyword.put_new(:locale, Localize.get_locale())

      case Interpreter.format_list(parsed, bindings, format_options) do
        {:ok, iolist, _bound, []} ->
          {:ok, :erlang.iolist_to_binary(iolist)}

        {:error, _iolist, _bound, unbound} ->
          {:error, Localize.BindError.exception(unbound: unbound)}

        {:format_error, reason} ->
          {:error, Localize.FormatError.exception(reason: reason)}
      end
    end
  end

  defp format_nif(message, bindings, options) do
    with {:ok, message} <- maybe_trim(message, options[:trim]) do
      locale_string = resolve_locale_string(options)
      bindings_map = normalize_bindings(bindings)

      case check_unbound_variables(message, bindings_map) do
        {:error, _} = error ->
          error

        :ok ->
          json_binary = IO.iodata_to_binary(:json.encode(bindings_map))

          case Localize.Nif.mf2_format(message, locale_string, json_binary) do
            {:ok, ""} ->
              # ICU MF2 (tech preview) may return empty strings for
              # messages with declarations. Fall back to the Elixir
              # interpreter for a correct result.
              format_elixir(message, bindings, options)

            {:ok, formatted} ->
              {:ok, formatted}

            {:error, reason} ->
              {:error, Localize.ParseError.exception(input: message, reason: reason)}
          end
      end
    end
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

  defp resolve_locale_string(options) do
    locale = Keyword.get(options, :locale, Localize.get_locale())
    locale_to_string(locale)
  end

  defp locale_to_string(name) when is_binary(name), do: name
  defp locale_to_string(name) when is_atom(name), do: Atom.to_string(name)
  defp locale_to_string(%{language: language}), do: Kernel.to_string(language)

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

  * `options` is a keyword list of options. See `format/3`.

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
          | {:error, String.t()}
          | {:format_error, String.t()}

  def format_to_iolist(message, bindings \\ %{}, options \\ []) when is_binary(message) do
    with {:ok, message} <- maybe_trim(message, options[:trim]),
         {:ok, parsed} <- Parser.parse(message) do
      Interpreter.format_list(parsed, bindings, options)
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
          {:ok, String.t()} | {:error, String.t()}

  def canonical_message(message, options \\ []) do
    options = Keyword.put_new(options, :trim, true)

    with {:ok, message} <- maybe_trim(message, options[:trim]),
         {:ok, ast} <- Parser.parse(message) do
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
      {:error, reason} -> raise Localize.ParseError, input: message, reason: reason
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
          {:ok, float()} | {:error, String.t()}

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
      {:error, reason} -> raise Localize.ParseError, input: nil, reason: reason
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
