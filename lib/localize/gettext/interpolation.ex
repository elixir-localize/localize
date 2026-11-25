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
      #=> "Hello \\u2068World\\u2069!"

  ### Gettext's own placeholders

  Ecto, Ash and Phoenix write their messages for Gettext's default interpolation, such as Ecto's `"should be at least %{count} character(s)"`, and an application's `errors.po` translates them in the same syntax. This interpolator reads `%{name}` as the MF2 variable `{$name}`, so those messages interpolate in a backend whose own messages are MF2. See `mf2_source/1`.

  ### Bidirectional isolation

  Messages are formatted with TR35's Default Bidi Strategy, the default of
  `Localize.Message.format/3`: a placeholder that may not have the
  message's direction is wrapped in Unicode bidi isolates (U+2066 to
  U+2069), so that a right-to-left value in a left-to-right message, or
  the reverse, displays correctly.

  """

  @behaviour Gettext.Interpolation

  # Gettext's own placeholder, `%{name}`, as Ecto, Ash and Phoenix write
  # their messages. `@legacy_placeholder` is one whose name MF2 accepts as a
  # variable name; `@any_legacy_placeholder` is any, so one MF2 cannot name
  # is kept as text rather than read as MF2 syntax.
  @legacy_placeholder ~r/%\{([\p{L}_][\p{L}\p{N}_.-]*)\}/u
  @any_legacy_placeholder ~r/%\{[^{}]*\}/u
  @needs_quoting ~r/\A[\s.]/u
  @whole_legacy_placeholder ~r/\A%\{[\p{L}_][\p{L}\p{N}_.-]*\}\z/u

  # A message in MF2's complex form, or a quoted pattern.
  @mf2_shaped ~r/\A\s*(?:\.(?:input|local|match)(?=[\s{$])|\{\{)/u

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
  def runtime_interpolate(message, bindings) when is_binary(message) do
    interpolate(message, bindings, [])
  end

  # The runtime interpolation, with options for `Localize.Message.format/3`:
  # `Localize.Gettext.Interpolation.Plain` formats Localize's own messages
  # with `bidi: :none`.
  @doc false
  @spec interpolate(String.t(), map(), Keyword.t()) ::
          {:ok, String.t()} | {:missing_bindings, String.t(), [atom() | String.t()]}
  def interpolate(message, %{__localize_skip_interpolation__: _}, _format_options) do
    {:ok, mf2_source(message)}
  end

  def interpolate(message, bindings, format_options) do
    string_bindings = normalize_gettext_bindings(bindings)

    case Localize.Message.format(mf2_source(message), string_bindings, format_options) do
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
    __compile_interpolate__(message, bindings, __CALLER__, [])
  end

  # The compile-time interpolation, with options for the interpreter, as
  # for `interpolate/3`.
  @doc false
  @spec __compile_interpolate__(term(), term(), Macro.Env.t(), Keyword.t()) :: Macro.t()
  def __compile_interpolate__(message, bindings, caller, format_options) do
    message =
      message
      |> expand_to_binary!(caller)
      |> mf2_source()

    # Syntax first, then the TR35 data-model rules, so a mis-authored
    # msgid fails the build rather than surfacing at runtime. Parsing and
    # validation are separate passes — see `Localize.Message.Validator`.
    parsed = parsed_message!(message)

    quote do
      case unquote(bindings) do
        %{__localize_skip_interpolation__: _} ->
          {:ok, unquote(message)}

        regular_bindings ->
          Localize.Gettext.Interpolation.do_interpolate(
            unquote(Macro.escape(parsed)),
            regular_bindings,
            unquote(format_options)
          )
      end
    end
  end

  defp parsed_message!(message) do
    case Localize.Message.Parser.parse(message) do
      {:ok, parsed} -> validated_message!(parsed, message)
      {:error, reason} -> raise ArgumentError, mis_authored(message, reason)
    end
  end

  defp validated_message!(parsed, message) do
    case Localize.Message.Validator.validate(parsed) do
      :ok -> parsed
      {:error, reason} -> raise ArgumentError, mis_authored(message, reason)
    end
  end

  defp mis_authored(_message, exception) when is_exception(exception) do
    "could not parse MF2 message: #{Exception.message(exception)}"
  end

  defp mis_authored(message, {reason, detail}) do
    "invalid MF2 message #{inspect(message)}: #{reason} (#{detail})"
  end

  @doc """
  Returns a Gettext message as MF2 source, reading Gettext's own `%{name}` placeholder as the MF2 variable `{$name}`.

  Ecto, Ash and Phoenix write their messages for Gettext's default interpolation, such as Ecto's `"should be at least %{count} character(s)"`, and an application's `errors.po` translates them in the same syntax. In MF2, `%{count}` is the text `%` followed by the literal `count`, so without this such a message would format as `"should be at least %count character(s)"`. `Localize.Message.format/3` keeps MF2's reading; this interpolator, which serves Gettext, reads Gettext's.

  * A message in MF2's complex form, or a quoted pattern `{{…}}`, has each `%{name}` replaced by `{$name}`.

  * Any other message with a `%{name}` placeholder is read as Gettext text: its `\\`, `{` and `}` are escaped and its placeholders become variables. It is written as a simple message, or quoted as a pattern `{{…}}` where it begins with whitespace or `.`, which a simple message cannot, so its text is kept exactly. A placeholder whose name MF2 cannot take as a variable name, such as `%{1x}`, is kept as text.

  * A message with no `%{name}` placeholder, or one that is not valid UTF-8, is returned as it is.

  The variables are formatted as the MF2 messages of the backend are, with bidi isolation by default.

  ### Arguments

  * `message` is a Gettext msgid or msgstr.

  ### Returns

  * The message as MF2 source.

  ### Examples

      iex> Localize.Gettext.Interpolation.mf2_source("should be at least %{count} character(s)")
      "should be at least {$count} character(s)"

      iex> Localize.Gettext.Interpolation.mf2_source("{{Hello {$name}!}}")
      "{{Hello {$name}!}}"

      iex> Localize.Gettext.Interpolation.mf2_source("must be one of {a, b}: %{value}")
      "must be one of \\\\{a, b\\\\}: {$value}"

      iex> Localize.Gettext.Interpolation.mf2_source(".po file %{name} is missing")
      "{{.po file {$name} is missing}}"

  """
  @spec mf2_source(String.t()) :: String.t()
  def mf2_source(message) when is_binary(message) do
    cond do
      # A message that is not UTF-8, as from a catalog in another charset,
      # is left for the formatter to refuse, which returns it unchanged.
      not String.valid?(message) ->
        message

      not Regex.match?(@any_legacy_placeholder, message) ->
        message

      Regex.match?(@mf2_shaped, message) ->
        Regex.replace(@legacy_placeholder, message, "{$\\1}")

      true ->
        quote_legacy(message)
    end
  end

  @doc false
  # A message read wholly as Gettext text, whatever it holds: for
  # `Localize.Gettext.Migration`, which converts a msgid with no
  # placeholder that is not valid MF2 as the text it was written as.
  @spec __gettext_text__(String.t()) :: String.t()
  def __gettext_text__(message) when is_binary(message) do
    if String.valid?(message) do
      quote_legacy(message)
    else
      message
    end
  end

  # A message in Gettext's syntax as MF2: the text escaped, each placeholder
  # a variable. A simple message drops leading whitespace and cannot begin
  # with `.`, so such a pattern is quoted.
  defp quote_legacy(message) do
    pattern =
      @any_legacy_placeholder
      |> Regex.split(message, include_captures: true)
      |> Enum.map_join(&legacy_piece/1)

    if Regex.match?(@needs_quoting, pattern) do
      "{{" <> pattern <> "}}"
    else
      pattern
    end
  end

  defp legacy_piece("%{" <> rest = piece) do
    if Regex.match?(@whole_legacy_placeholder, piece) do
      "{$" <> rest
    else
      escape_text(piece)
    end
  end

  defp legacy_piece(text) do
    escape_text(text)
  end

  defp escape_text(text) do
    Regex.replace(~r/[\\{}]/u, text, "\\\\\\0")
  end

  @impl Gettext.Interpolation
  def message_format do
    "icu-format"
  end

  # A value that cannot be formatted leaves the message unformatted, as
  # `runtime_interpolate/2` does, rather than raising.
  @doc false
  @spec do_interpolate(term(), map(), Keyword.t()) ::
          {:ok, String.t()}
          | {:missing_bindings, String.t(), [atom() | String.t()]}
  def do_interpolate(parsed_ast, bindings, format_options \\ []) do
    string_bindings = normalize_gettext_bindings(bindings)

    case Localize.Message.Interpreter.format_list(parsed_ast, string_bindings, format_options) do
      {:ok, iolist, _bound, []} ->
        {:ok, :erlang.iolist_to_binary(iolist)}

      {:error, iolist, _bound, unbound} ->
        missing = Enum.map(unbound, &safe_to_atom/1)
        {:missing_bindings, :erlang.iolist_to_binary(iolist), missing}

      {:format_error, payload} ->
        Logger.warning(
          "Localize.Gettext.Interpolation: returning message unformatted, " <>
            "format failed: #{inspect(payload)}"
        )

        {:ok, Localize.Message.Print.to_string(parsed_ast)}
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
