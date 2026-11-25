defmodule Localize.Gettext.Migration do
  @moduledoc """
  Converts Gettext catalogs written in Gettext's own `%{name}` syntax to MF2, for a backend that uses `Localize.Gettext.Interpolation`.

  Each msgid, plural msgid and msgstr is rewritten by `Localize.Gettext.Interpolation.mf2_source/1`, the same reading the interpolator applies to it when it formats, so a converted message formats exactly as the original did: `%{count}` becomes `{$count}`, and the message's other text is escaped where MF2 needs it. A message that is valid MF2 and has no `%{name}` placeholder is left as it is; one that is not valid MF2, such as text holding a brace or beginning with `.`, which a `gettext` call in a backend with MF2 interpolation refuses, is converted as the text it is, so it shows as it did.

  A msgid is the key a translation is found by, so the `gettext` calls that use one must change with it. `convert/1` returns the msgids it renamed, for the source to be rewritten in step.

  """

  alias Expo.Message
  alias Expo.Messages
  alias Localize.Gettext.Migration.Arguments

  # A call of a Gettext macro, bare or through a backend module, or of a
  # `Gettext` function, which takes the backend first. It is found in text,
  # so in a HEEx template as in a module.
  @gettext_call ~r/(?<![\w.:?!@])((?:[A-Z]\w*\.)*)(d?p?n?gettext(?:_noop)?)\s*\(/u

  # The positions of each macro's msgid and plural msgid among its
  # arguments.
  @msgid_positions %{
    "gettext" => [0],
    "dgettext" => [1],
    "pgettext" => [1],
    "dpgettext" => [2],
    "ngettext" => [0, 1],
    "dngettext" => [1, 2],
    "pngettext" => [1, 2],
    "dpngettext" => [2, 3]
  }

  @typedoc "A msgid that conversion renamed, with its context."
  @type rename :: %{context: String.t() | nil, from: String.t(), to: String.t()}

  @typedoc "A msgid in a `gettext` call that `convert_source/1` left for a person to convert."
  @type skipped :: %{line: pos_integer(), call: String.t(), reason: String.t()}

  @doc """
  Converts the messages of a catalog to MF2.

  ### Arguments

  * `messages` is a catalog as `Expo.PO.parse_file/2` or `Expo.PO.parse_string/2` returns it.

  ### Returns

  * `{:ok, messages, renames}`, where `messages` is the converted catalog and `renames` lists each msgid and plural msgid that changed, with its context, in the order they appear, or

  * `{:error, exception}` when `messages` is not an `Expo.Messages` struct.

  ### Examples

      iex> {:ok, catalog} =
      ...>   Expo.PO.parse_string(~S'''
      ...>   msgid "should be at least %{count} character(s)"
      ...>   msgstr "doit contenir au moins %{count} caractère(s)"
      ...>   ''')
      iex> {:ok, converted, renames} = Localize.Gettext.Migration.convert(catalog)
      iex> [message] = converted.messages
      iex> {IO.iodata_to_binary(message.msgid), IO.iodata_to_binary(message.msgstr)}
      {"should be at least {$count} character(s)", "doit contenir au moins {$count} caractère(s)"}
      iex> renames
      [%{context: nil, from: "should be at least %{count} character(s)", to: "should be at least {$count} character(s)"}]

  """
  @spec convert(Messages.t()) :: {:ok, Messages.t(), [rename()]} | {:error, Exception.t()}
  def convert(%Messages{messages: messages} = catalog) do
    {converted, renames} = Enum.map_reduce(messages, [], &convert_message/2)
    {:ok, %{catalog | messages: converted}, Enum.reverse(renames)}
  end

  def convert(catalog) do
    {:error,
     Localize.InvalidValueError.exception(value: catalog, expected: "an Expo.Messages catalog")}
  end

  @doc """
  Converts the msgids of the `gettext` calls in a source file to MF2, as `convert/1` converts them in a catalog.

  Conversion is a function of the msgid alone, so a msgid converted here matches the msgid `convert/1` gives its catalog entry, and the two can be converted separately. The calls are found in the text, so a call in a HEEx template or in a `~H` sigil is converted as one in a module is: each Gettext macro, with or without `_noop`, bare or through its backend module, and each `Gettext` function, which takes the backend first. A msgid written as a string literal, a heredoc included, is rewritten as a string literal; one written as a sigil, a concatenation or an expression that holds a `%{name}` placeholder is left as it is and reported. A call in a comment or a documentation string is converted too, as it is found in text.

  ### Arguments

  * `source` is the text of a source file.

  ### Returns

  * `{:ok, source, report}`, where `source` is the converted text and `report` is a map with `:rewritten`, the number of msgids rewritten, and `:skipped`, the msgids left for a person to convert, each a map with `:line`, `:call` and `:reason`, or

  * `{:error, exception}` when `source` is not a string.

  ### Examples

      iex> Localize.Gettext.Migration.convert_source(~S|gettext("Hello %{name}", name: user.name)|)
      {:ok, ~S|gettext("Hello {$name}", name: user.name)|, %{rewritten: 1, skipped: []}}

      iex> Localize.Gettext.Migration.convert_source(~S|ngettext("%{count} file", "%{count} files", n)|)
      {:ok, ~S|ngettext("{$count} file", "{$count} files", n)|, %{rewritten: 2, skipped: []}}

  """
  @spec convert_source(String.t()) ::
          {:ok, String.t(), %{rewritten: non_neg_integer(), skipped: [skipped()]}}
          | {:error, Exception.t()}
  def convert_source(source) when is_binary(source) do
    {replacements, skipped} =
      @gettext_call
      |> Regex.scan(source, return: :index, capture: :all)
      |> Enum.reduce({[], []}, &call_replacements(source, &1, &2))

    converted =
      replacements
      |> Enum.uniq_by(fn {start, _stop, _text} -> start end)
      |> Enum.sort_by(fn {start, _stop, _text} -> start end, :desc)
      |> Enum.reduce(source, &replace/2)

    {:ok, converted,
     %{rewritten: length(Enum.uniq(replacements)), skipped: Enum.reverse(skipped)}}
  end

  def convert_source(source) do
    {:error,
     Localize.InvalidValueError.exception(value: source, expected: "a source file as a string")}
  end

  defp call_replacements(
         source,
         [{call_start, call_length}, {prefix_start, prefix_length}, {name_start, name_length}],
         acc
       ) do
    prefix = binary_part(source, prefix_start, prefix_length)
    name = binary_part(source, name_start, name_length)
    open = call_start + call_length - 1

    case Arguments.spans(source, open) do
      {:ok, spans} -> msgid_replacements(source, spans, positions(prefix, name), name, acc)
      :error -> acc
    end
  end

  # A `Gettext` function takes the backend before the macro's arguments.
  defp positions(prefix, name) do
    base = Map.fetch!(@msgid_positions, String.replace_suffix(name, "_noop", ""))

    if prefix == "Gettext." do
      Enum.map(base, &(&1 + 1))
    else
      base
    end
  end

  defp msgid_replacements(source, spans, positions, name, acc) do
    positions
    |> Enum.flat_map(&Enum.slice(spans, &1, 1))
    |> Enum.reduce(acc, &msgid_replacement(source, &1, name, &2))
  end

  defp msgid_replacement(source, {start, stop}, name, {replacements, skipped}) do
    text = binary_part(source, start, stop - start)
    leading = byte_size(text) - byte_size(String.trim_leading(text))
    literal = String.trim(text)
    literal_start = start + leading

    # No atom is made: a string literal needs none, and anything else is
    # not a msgid to rewrite.
    case Code.string_to_quoted(literal, existing_atoms_only: true) do
      {:ok, msgid} when is_binary(msgid) ->
        to = migrate(msgid)

        if to == msgid do
          {replacements, skipped}
        else
          replacement =
            {literal_start, literal_start + byte_size(literal),
             inspect(to, printable_limit: :infinity)}

          {[replacement | replacements], skipped}
        end

      _not_a_string ->
        {replacements, skip_placeholder(source, literal_start, literal, name, skipped)}
    end
  end

  # A msgid that is not a string literal is reported only where it holds
  # a placeholder to convert: most are variables, as in `translate_error/1`.
  defp skip_placeholder(source, position, literal, name, skipped) do
    if String.contains?(literal, "%{") do
      line =
        source
        |> binary_part(0, position)
        |> String.split("\n")
        |> length()

      [
        %{line: line, call: name, reason: "the msgid is not a string literal: #{literal}"}
        | skipped
      ]
    else
      skipped
    end
  end

  defp replace({start, stop, text}, source) do
    binary_part(source, 0, start) <> text <> binary_part(source, stop, byte_size(source) - stop)
  end

  defp convert_message(%Message.Singular{} = message, renames) do
    {msgid, renames} = convert_msgid(message.msgid, message.msgctxt, renames)
    {%{message | msgid: msgid, msgstr: convert_string(message.msgstr)}, renames}
  end

  defp convert_message(%Message.Plural{} = message, renames) do
    {msgid, renames} = convert_msgid(message.msgid, message.msgctxt, renames)
    {msgid_plural, renames} = convert_msgid(message.msgid_plural, message.msgctxt, renames)
    msgstr = Map.new(message.msgstr, fn {index, string} -> {index, convert_string(string)} end)

    {%{message | msgid: msgid, msgid_plural: msgid_plural, msgstr: msgstr}, renames}
  end

  defp convert_msgid(msgid, msgctxt, renames) do
    from = IO.iodata_to_binary(msgid)
    to = migrate(from)

    if to == from do
      {msgid, renames}
    else
      {[to], [%{context: context(msgctxt), from: from, to: to} | renames]}
    end
  end

  defp context(nil) do
    nil
  end

  defp context(msgctxt) do
    IO.iodata_to_binary(msgctxt)
  end

  # A string is read as the interpolator reads it. One that is still not
  # valid MF2, such as a msgid written before the backend was MF2 that
  # holds a brace or begins with `.`, is read as the Gettext text it is,
  # which the interpolator would have shown unformatted.
  defp migrate(string) do
    source = Localize.Gettext.Interpolation.mf2_source(string)

    case Localize.Message.parse(source) do
      {:ok, _parsed} -> source
      {:error, _exception} -> Localize.Gettext.Interpolation.__gettext_text__(string)
    end
  end

  # A string is kept as its segments when it does not change, so a catalog
  # with nothing to convert composes back as it was.
  defp convert_string(string) do
    from = IO.iodata_to_binary(string)
    to = migrate(from)

    if to == from do
      string
    else
      [to]
    end
  end
end
