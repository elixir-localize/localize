defmodule Localize.Gettext.Migration do
  @moduledoc """
  Converts Gettext catalogs written in Gettext's own `%{name}` syntax to MF2, for a backend that uses `Localize.Gettext.Interpolation`.

  Each msgid, plural msgid and msgstr is rewritten by `Localize.Gettext.Interpolation.mf2_source/1`, the same reading the interpolator applies to it when it formats, so a converted message formats exactly as the original did: `%{count}` becomes `{$count}`, and the message's other text is escaped where MF2 needs it. A message that is valid MF2 and has no `%{name}` placeholder is left as it is; one that is not valid MF2, such as text holding a brace or beginning with `.`, which a `gettext` call in a backend with MF2 interpolation refuses, is converted as the text it is, so it shows as it did.

  A msgid is the key a translation is found by, so the `gettext` calls that use one must change with it. `convert/1` returns the msgids it renamed, for the source to be rewritten in step.

  """

  alias Expo.Message
  alias Expo.Messages

  @typedoc "A msgid that conversion renamed, with its context."
  @type rename :: %{context: String.t() | nil, from: String.t(), to: String.t()}

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
