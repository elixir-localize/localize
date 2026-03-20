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

  * `:formatter_backend` determines which formatting engine to use.
    Accepts `:default`, `:nif`, or `:elixir`.
    When set to `:default`, the ICU NIF is used if available, otherwise
    the pure-Elixir interpreter is used. When set to `:nif`, the NIF
    is required and a `RuntimeError` is raised if it is not available.
    When set to `:elixir`, the pure-Elixir interpreter is always used.
    The default is `:default`.

  ### Returns

  * `{:ok, formatted_message}` on success.

  * `{:error, {module, reason}}` on failure.

  ### Examples

      iex> Localize.Message.format("{{Hello {$name}!}}", %{"name" => "World"})
      {:ok, "Hello World!"}

  """

  @type formatter_backend :: :default | :nif | :elixir

  @spec format(String.t(), bindings(), options()) ::
          {:ok, String.t()} | {:error, {module(), String.t()}}

  def format(message, bindings \\ %{}, options \\ []) when is_binary(message) do
    {formatter, options} = resolve_formatter_backend(options)

    case formatter do
      :nif -> format_nif(message, bindings, options)
      :elixir -> format_elixir(message, bindings, options)
    end
  end

  defp format_elixir(message, bindings, options) do
    with {:ok, message} <- maybe_trim(message, options[:trim]),
         {:ok, parsed} <- Parser.parse(message) do
      format_options =
        options
        |> Keyword.put_new(:locale, Keyword.get(options, :locale))

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

      case Localize.Nif.mf2_format(message, locale_string, bindings_map) do
        {:ok, formatted} ->
          {:ok, formatted}

        {:error, reason} ->
          {:error, Localize.ParseError.exception(input: message, reason: reason)}
      end
    end
  end

  defp resolve_formatter_backend(options) do
    {fb, rest} = Keyword.pop(options, :formatter_backend, :default)

    case fb do
      :nif ->
        unless Localize.Nif.available?() do
          raise RuntimeError,
                "NIF formatter backend requested but not available. " <>
                  "Compile with LOCALIZE_NIF=true or set " <>
                  "`config :localize, :nif, true` in config.exs."
        end

        {:nif, rest}

      :elixir ->
        {:elixir, rest}

      :default ->
        if Localize.Nif.available?() do
          {:nif, rest}
        else
          {:elixir, rest}
        end
    end
  end

  defp resolve_locale_string(options) do
    case Keyword.get(options, :locale) do
      nil ->
        "en"

      name when is_binary(name) ->
        name

      name when is_atom(name) ->
        Atom.to_string(name)

      %{language: language} ->
        Kernel.to_string(language)
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

      {:error, %{__exception__: true} = exception} ->
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
