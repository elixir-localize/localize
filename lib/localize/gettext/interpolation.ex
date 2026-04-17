defmodule Localize.Gettext.Interpolation do
  alias Localize.Utils.Helpers

  @moduledoc """
  Gettext interpolation module for ICU MessageFormat 2 (MF2) messages.

  Implements the `Gettext.Interpolation` behaviour so that MF2 messages
  can be used in Gettext `.po`/`.pot` files. At compile time, messages
  are parsed into an AST for efficient runtime formatting. At runtime,
  bindings are interpolated using `Localize.Message`.

  ### Defining a Gettext module with MF2 interpolation

  ```elixir
  defmodule MyApp.Gettext do
    use Gettext.Backend,
      otp_app: :my_app,
      interpolation: Localize.Gettext.Interpolation
  end
  ```

  Now Gettext macros will parse and format MF2 messages:

      import MyApp.Gettext

      gettext("{{Hello {$name}!}}", %{name: "World"})
      #=> "Hello World!"

  ### Options

  The `use` macro accepts the following options:

  * `:locale` - a default locale to use for formatting. When not set,
    the locale is resolved from `Gettext.get_locale/1` at runtime.

  """

  @behaviour Gettext.Interpolation

  @impl Gettext.Interpolation
  def runtime_interpolate(message, bindings) when is_binary(message) do
    string_bindings = normalize_gettext_bindings(bindings)

    case Localize.Message.format(message, string_bindings) do
      {:ok, formatted} ->
        {:ok, formatted}

      {:error, %Localize.BindError{unbound: unbound}} ->
        missing = Enum.map(unbound, &safe_to_atom/1)
        {:missing_bindings, message, missing}

      {:error, exception} when is_exception(exception) ->
        raise exception
    end
  end

  @impl Gettext.Interpolation
  defmacro compile_interpolate(_translation_type, message, bindings) do
    message = expand_to_binary!(message, __CALLER__)

    case Localize.Message.Parser.parse(message) do
      {:ok, parsed} ->
        quote do
          Localize.Gettext.Interpolation.do_interpolate(
            unquote(Macro.escape(parsed)),
            unquote(bindings)
          )
        end

      {:error, %_{} = exception} ->
        raise ArgumentError, "could not parse MF2 message: #{Exception.message(exception)}"

      {:error, reason} ->
        raise ArgumentError, "could not parse MF2 message: #{inspect(reason)}"
    end
  end

  @impl Gettext.Interpolation
  def message_format do
    "icu-format"
  end

  @doc false
  @spec do_interpolate(term(), map()) ::
          {:ok, String.t()}
          | {:missing_bindings, String.t(), [atom()]}
  def do_interpolate(parsed_ast, bindings) do
    string_bindings = normalize_gettext_bindings(bindings)

    case Localize.Message.Interpreter.format_list(parsed_ast, string_bindings) do
      {:ok, iolist, _bound, []} ->
        {:ok, :erlang.iolist_to_binary(iolist)}

      {:error, iolist, _bound, unbound} ->
        missing = Enum.map(unbound, &safe_to_atom/1)
        {:missing_bindings, :erlang.iolist_to_binary(iolist), missing}
    end
  end

  # Gettext passes bindings as `%{atom_key => value}` but MF2 uses
  # string keys. Convert atom keys to strings for the formatter.
  defp normalize_gettext_bindings(bindings) when is_map(bindings) do
    Map.new(bindings, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), value}
      {key, value} -> {key, value}
    end)
  end

  defp normalize_gettext_bindings(bindings) when is_list(bindings) do
    Map.new(bindings, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), value}
      {key, value} -> {key, value}
    end)
  end

  defp safe_to_atom(name) when is_binary(name),
    do: Helpers.existing_atom(name) || String.to_atom(name)

  defp safe_to_atom(name) when is_atom(name), do: name

  @doc false
  @spec expand_to_binary!(term(), Macro.Env.t()) :: binary() | no_return()
  def expand_to_binary!(term, env) do
    case Macro.expand(term, env) do
      term when is_binary(term) ->
        term

      {:<<>>, _, pieces} = term ->
        if Enum.all?(pieces, &is_binary/1) do
          Enum.join(pieces)
        else
          raise_not_binary!(term)
        end

      other ->
        raise_not_binary!(other)
    end
  end

  @dialyzer {:nowarn_function, raise_not_binary!: 1}
  defp raise_not_binary!(term) do
    raise ArgumentError, """
    Localize.Gettext.Interpolation macros expect translation keys to expand \
    to strings at compile-time, but the given term doesn't. This is what the \
    macro received:

      #{inspect(term)}

    Dynamic translations should be avoided as they limit the ability to extract \
    translations from your source code. If you need dynamic lookup, use \
    Localize.Message.format/3 directly:

      message = "{{Hello {$name}!}}"
      Localize.Message.format(message, %{"name" => "World"})

    """
  end
end
