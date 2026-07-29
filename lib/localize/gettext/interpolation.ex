defmodule Localize.Gettext.Interpolation do
  require Logger
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

  @doc """
  Sentinel bindings that cause `runtime_interpolate/2` and
  `do_interpolate/2` to return the translated msgid unchanged,
  bypassing MF2 evaluation entirely.

  Used by `Localize.HTML.t/1` (and any caller that needs the raw
  translated MF2 source so it can run `format_to_safe_list/3` itself
  for markup-aware rendering). Not intended for direct use by
  application code.

  ### Returns

  * The sentinel map `%{__localize_skip_interpolation__: true}`.

  ### Examples

      iex> Localize.Gettext.Interpolation.skip_interpolation_sentinel()
      %{__localize_skip_interpolation__: true}

  """
  @spec skip_interpolation_sentinel() :: %{__localize_skip_interpolation__: true}
  def skip_interpolation_sentinel, do: %{__localize_skip_interpolation__: true}

  @impl Gettext.Interpolation
  def runtime_interpolate(message, %{__localize_skip_interpolation__: _})
      when is_binary(message) do
    {:ok, message}
  end

  def runtime_interpolate(message, bindings) when is_binary(message) do
    string_bindings = normalize_gettext_bindings(bindings)

    case Localize.Message.format(message, string_bindings) do
      {:ok, formatted} ->
        {:ok, formatted}

      {:error, %Localize.BindError{unbound: unbound}} ->
        missing = Enum.map(unbound, &safe_to_atom/1)
        {:missing_bindings, message, missing}

      {:error, %Localize.ParseError{} = error} ->
        # A gettext string that isn't valid MF2 shouldn't crash the
        # caller. Pass it through unchanged (matches gettext's own
        # "fall back to the msgid" pattern for missing translations)
        # and log a warning so devs can spot mis-authored messages.
        Logger.warning(
          "Localize.Gettext.Interpolation: returning message unchanged, " <>
            "not valid MF2: #{Exception.message(error)}"
        )

        {:ok, message}

      {:error, exception} when is_exception(exception) ->
        Logger.warning(
          "Localize.Gettext.Interpolation: returning message unchanged, " <>
            "format failed: #{Exception.message(exception)}"
        )

        {:ok, message}
    end
  end

  @impl Gettext.Interpolation
  defmacro compile_interpolate(_translation_type, message, bindings) do
    message = expand_to_binary!(message, __CALLER__)

    # Syntax first, then the TR35 data-model rules, so a mis-authored
    # msgid fails the build rather than surfacing at runtime. Parsing and
    # validation are separate passes — see `Localize.Message.Validator`.
    with {:ok, parsed} <- Localize.Message.Parser.parse(message),
         :ok <- Localize.Message.Validator.validate(parsed) do
      quote do
        case unquote(bindings) do
          %{__localize_skip_interpolation__: _} ->
            {:ok, unquote(message)}

          regular_bindings ->
            Localize.Gettext.Interpolation.do_interpolate(
              unquote(Macro.escape(parsed)),
              regular_bindings
            )
        end
      end
    else
      {:error, exception} when is_exception(exception) ->
        raise ArgumentError, "could not parse MF2 message: #{Exception.message(exception)}"

      {:error, {reason, detail}} ->
        raise ArgumentError,
              "invalid MF2 message #{inspect(message)}: #{reason} (#{detail})"
    end
  end

  @impl Gettext.Interpolation
  def message_format do
    "icu-format"
  end

  @doc false
  @spec do_interpolate(term(), map()) ::
          {:ok, String.t()}
          | {:missing_bindings, String.t(), [atom() | String.t()]}
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

  # Return the existing atom for the binding name when it exists; fall
  # back to the binary itself otherwise. Used to build the
  # `:missing_bindings` report for messages that reference an unbound
  # variable. The previous fallback to `String.to_atom/1` was an
  # atom-table DOS vector when binding names came from MF2 messages
  # outside the developer's vocabulary.
  defp safe_to_atom(name) when is_binary(name),
    do: Helpers.existing_atom(name) || name

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
