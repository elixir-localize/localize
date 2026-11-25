defmodule Localize.Gettext.Migration do
  @moduledoc """
  Converts Gettext catalogs written in Gettext's own `%{name}` syntax to MF2, for a backend that uses `Localize.Gettext.Interpolation`.

  Each msgid, plural msgid and msgstr is rewritten by `Localize.Gettext.Interpolation.mf2_source/1`, the same reading the interpolator applies to it when it formats, so a converted message formats exactly as the original did: `%{count}` becomes `{$count}`, and the message's other text is escaped where MF2 needs it. A message that is valid MF2 and has no `%{name}` placeholder is left as it is; one that is not valid MF2, such as text holding a brace or beginning with `.`, which a `gettext` call in a backend with MF2 interpolation refuses, is converted as the text it is, so it shows as it did.

  A msgid is the key a translation is found by, so the `gettext` calls that use one must change with it. `convert/1` returns the msgids it renamed, for the source to be rewritten in step.

  """

  alias Expo.Message
  alias Expo.Messages
  alias Localize.Gettext.Migration.{Arguments, Plural}
  alias Localize.Utils.Helpers

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

  @typedoc """
  A msgid that conversion renamed, with its context. A plural entry converted to one `.match` message also names its plural msgid in `:from_plural`.
  """
  @type rename :: %{
          required(:context) => String.t() | nil,
          required(:from) => String.t(),
          required(:to) => String.t(),
          optional(:from_plural) => String.t()
        }

  @typedoc "A plural entry, by its context, msgid and plural msgid."
  @type plural_key :: {String.t() | nil, String.t(), String.t()}

  @typedoc "A msgid in a `gettext` call that `convert_source/1` left for a person to convert."
  @type skipped :: %{line: pos_integer(), call: String.t(), reason: String.t()}

  @doc """
  Converts the messages of a catalog to MF2.

  With the `:plurals` option, a plural entry becomes a singular entry whose msgid and msgstr are each one `.match` message on the `count` binding, choosing the form Gettext would choose: each CLDR plural category takes the form Gettext gives its counts, and a count Gettext gives another form, such as `0` under a French `n != 1` formula, takes an exact key. The msgid's variants follow the source language's plural rules and the msgstr's the catalog's language and `Plural-Forms` header. An entry Gettext and CLDR disagree on beyond a few small counts cannot be written as categories, and is converted as with `:plurals` off; `convertible_plurals/2` tells which entries can be.

  ### Arguments

  * `messages` is a catalog as `Expo.PO.parse_file/2` or `Expo.PO.parse_string/2` returns it.

  * `options` is a keyword list of options.

  ### Options

  * `:plurals` is `false`, the default, to keep plural entries as plural entries with their placeholders converted, `true` to convert each plural entry that can be, or a set of `t:plural_key/0`, from `convertible_plurals/2`, to convert those alone, so a template, its translations and the calls that use them convert the same entries.

  * `:locale` is the catalog's language, for its plural forms. The default is its `Language` header.

  * `:source_locale` is the language msgids are written in. The default is `"en"`.

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
  @spec convert(Messages.t(), Keyword.t()) ::
          {:ok, Messages.t(), [rename()]} | {:error, Exception.t()}
  def convert(catalog, options \\ [])

  def convert(%Messages{messages: messages} = catalog, options) when is_list(options) do
    with {:ok, plurals} <- plurals_option(Keyword.get(options, :plurals, false)),
         {:ok, rules} <- plural_rules(catalog, options, plurals) do
      {converted, renames} =
        Enum.map_reduce(messages, [], &convert_message(&1, &2, plurals, rules))

      {:ok, %{catalog | messages: converted}, Enum.reverse(renames)}
    end
  end

  def convert(catalog, _options) do
    {:error,
     Localize.InvalidValueError.exception(value: catalog, expected: "an Expo.Messages catalog")}
  end

  @doc """
  Returns the plural entries of a catalog that `convert/2` can write as one `.match` message each.

  An entry can be converted in a template when its msgid and plural msgid can be, under the source language's plural rules, and in a translation when its msgstr forms can be too, under the catalog's language and `Plural-Forms` header. A msgid is a key shared by the template, every translation and the calls that use it, so convert only the entries every catalog of a domain can convert: the intersection of what this function returns for each.

  ### Arguments

  * `messages` is a catalog as `Expo.PO.parse_file/2` returns it.

  * `options` is a keyword list of the `:locale` and `:source_locale` options `convert/2` takes.

  ### Returns

  * `{:ok, keys}`, a set of `t:plural_key/0`, or

  * `{:error, exception}` when `messages` is not an `Expo.Messages` struct or an option is not valid.

  ### Examples

      iex> {:ok, catalog} =
      ...>   Expo.PO.parse_string(~S'''
      ...>   msgid "%{count} file"
      ...>   msgid_plural "%{count} files"
      ...>   msgstr[0] ""
      ...>   msgstr[1] ""
      ...>   ''')
      iex> Localize.Gettext.Migration.convertible_plurals(catalog)
      {:ok, MapSet.new([{nil, "%{count} file", "%{count} files"}])}

  """
  @spec convertible_plurals(Messages.t(), Keyword.t()) ::
          {:ok, MapSet.t(plural_key())} | {:error, Exception.t()}
  def convertible_plurals(catalog, options \\ [])

  def convertible_plurals(%Messages{messages: messages} = catalog, options)
      when is_list(options) do
    with {:ok, rules} <- plural_rules(catalog, options, true) do
      keys =
        for %Message.Plural{} = message <- messages,
            match?({:ok, _message}, plural_message(message, rules)),
            into: MapSet.new(),
            do: plural_key(message)

      {:ok, keys}
    end
  end

  def convertible_plurals(catalog, _options) do
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

  defp convert_message(%Message.Singular{} = message, renames, _plurals, _rules) do
    {msgid, renames} = convert_msgid(message.msgid, message.msgctxt, renames)
    {%{message | msgid: msgid, msgstr: convert_string(message.msgstr)}, renames}
  end

  defp convert_message(%Message.Plural{} = message, renames, plurals, rules) do
    case plural_conversion(message, plurals, rules) do
      {:ok, singular} ->
        rename = %{
          context: context(message.msgctxt),
          from: IO.iodata_to_binary(message.msgid),
          from_plural: IO.iodata_to_binary(message.msgid_plural),
          to: IO.iodata_to_binary(singular.msgid)
        }

        {singular, [rename | renames]}

      :keep ->
        convert_plural_forms(message, renames)
    end
  end

  defp plural_conversion(message, plurals, rules) do
    if convert_plural?(message, plurals) do
      keep_unless_converted(plural_message(message, rules))
    else
      :keep
    end
  end

  defp keep_unless_converted({:ok, singular}) do
    {:ok, singular}
  end

  defp keep_unless_converted({:error, _reason}) do
    :keep
  end

  defp convert_plural_forms(message, renames) do
    {msgid, renames} = convert_msgid(message.msgid, message.msgctxt, renames)
    {msgid_plural, renames} = convert_msgid(message.msgid_plural, message.msgctxt, renames)
    msgstr = Map.new(message.msgstr, fn {index, string} -> {index, convert_string(string)} end)

    {%{message | msgid: msgid, msgid_plural: msgid_plural, msgstr: msgstr}, renames}
  end

  defp convert_plural?(_message, false) do
    false
  end

  defp convert_plural?(_message, true) do
    true
  end

  defp convert_plural?(message, %MapSet{} = keys) do
    MapSet.member?(keys, plural_key(message))
  end

  defp plural_key(message) do
    {context(message.msgctxt), IO.iodata_to_binary(message.msgid),
     IO.iodata_to_binary(message.msgid_plural)}
  end

  # A plural entry as a singular one: its msgid from the msgid and plural
  # msgid under the source language's rules, and its msgstr from its forms
  # under the catalog's, or empty where it is untranslated.
  defp plural_message(message, rules) do
    msgid_forms = [IO.iodata_to_binary(message.msgid), IO.iodata_to_binary(message.msgid_plural)]

    with {:ok, msgid} <- rules_message(msgid_forms, rules.source),
         {:ok, msgstr} <- plural_msgstr(message.msgstr, rules.catalog) do
      {:ok,
       %Message.Singular{
         msgid: [msgid],
         msgstr: [msgstr],
         msgctxt: message.msgctxt,
         comments: message.comments,
         extracted_comments: message.extracted_comments,
         flags: message.flags,
         previous_messages: [],
         references: message.references,
         obsolete: message.obsolete
       }}
    end
  end

  defp plural_msgstr(msgstr, catalog_rules) do
    forms =
      msgstr
      |> Enum.sort()
      |> Enum.map(fn {_index, string} -> IO.iodata_to_binary(string) end)

    if Enum.all?(forms, &(&1 == "")) do
      {:ok, ""}
    else
      rules_message(forms, catalog_rules)
    end
  end

  defp rules_message(_forms, nil) do
    {:error, :no_plural_rules}
  end

  defp rules_message(forms, {plural_info, locale}) do
    Plural.message(forms, plural_info, locale)
  end

  defp plurals_option(plurals) when is_boolean(plurals) do
    {:ok, plurals}
  end

  defp plurals_option(%MapSet{} = plurals) do
    {:ok, plurals}
  end

  defp plurals_option(plurals) do
    {:error,
     Localize.InvalidValueError.exception(
       value: plurals,
       expected: "true, false or a set of plural keys for the :plurals option"
     )}
  end

  # The plural rules of the source language, for msgids, and of the
  # catalog's language, for msgstrs. Gettext raises for a locale it has no
  # plural rules for, so each is tried once here.
  defp plural_rules(_catalog, _options, false) do
    {:ok, %{source: nil, catalog: nil}}
  end

  defp plural_rules(catalog, options, _plurals) do
    source_locale = Keyword.get(options, :source_locale, "en")
    catalog_locale = Keyword.get(options, :locale) || header(catalog, "Language")

    with {:ok, source} <- language_rules(source_locale, nil) do
      {:ok,
       %{source: source, catalog: catalog_rules(catalog_locale, header(catalog, "Plural-Forms"))}}
    end
  end

  defp catalog_rules(nil, _plural_forms) do
    nil
  end

  defp catalog_rules(locale, plural_forms) do
    case language_rules(locale, plural_forms) do
      {:ok, rules} -> rules
      {:error, _exception} -> nil
    end
  end

  defp language_rules(locale, plural_forms) when is_binary(locale) do
    context = gettext_plural_context(String.replace(locale, "-", "_"), plural_forms)

    with {:ok, tag} <- Localize.validate_locale(String.replace(locale, "_", "-")),
         {:ok, plural_info} <- Helpers.run_isolated(fn -> gettext_plural_info(context) end) do
      {:ok, {plural_info, tag}}
    end
  end

  defp language_rules(locale, _plural_forms) do
    {:error, Localize.InvalidLocaleError.exception(locale_id: inspect(locale))}
  end

  defp gettext_plural_context(locale, nil) do
    %{locale: locale}
  end

  defp gettext_plural_context(locale, plural_forms) do
    %{locale: locale, plural_forms_header: plural_forms}
  end

  # Gettext raises for a locale it has no rules for, and for a malformed
  # `Plural-Forms` header, the first when a form is asked for.
  defp gettext_plural_info(context) do
    plural_info = Gettext.Plural.init(context)
    _index = Gettext.Plural.plural(plural_info, 1)
    plural_info
  end

  defp header(catalog, name) do
    case Messages.get_header(catalog, name) do
      [] -> nil
      values -> values |> Enum.join() |> String.trim() |> blank_to_nil()
    end
  end

  defp blank_to_nil("") do
    nil
  end

  defp blank_to_nil(value) do
    value
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

  @doc false
  # A string as `convert/2` converts it, for `Localize.Gettext.Migration.Plural`.
  @spec __mf2_text__(String.t()) :: String.t()
  def __mf2_text__(string) when is_binary(string) do
    migrate(string)
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
