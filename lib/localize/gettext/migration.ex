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

  * `:only` is the set of entries to convert, as `{context, msgid}` keys, leaving every other entry as it is. The default is `nil`, which converts every entry. `mix localize.gettext.mf2` passes the entries whose every lookup in source it converts too.

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
         {:ok, only} <- catalog_only(Keyword.get(options, :only)),
         {:ok, rules} <- plural_rules(catalog, options, plurals) do
      {converted, renames} =
        Enum.map_reduce(messages, [], &convert_selected(&1, &2, only, plurals, rules))

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

  @typedoc """
  A Gettext lookup in source: the call, its line, and its domain, context, msgid and plural msgid, each a string, `nil` where the call has none, or `:dynamic` where the argument is an expression.
  """
  @type lookup :: %{
          call: String.t(),
          line: pos_integer(),
          domain: String.t() | :dynamic,
          context: String.t() | nil | :dynamic,
          msgid: String.t() | :dynamic,
          msgid_plural: String.t() | nil | :dynamic
        }

  @doc """
  Returns the Gettext lookups in a source file.

  A msgid can only be converted where every lookup of it changes with it. A lookup with a literal msgid is converted with its catalog entry; one whose msgid is an expression, as in a `translate_error/1` that translates Ecto's messages, or whose domain is, looks up msgids that cannot be known from the source, which the catalogs they may name must therefore keep. `mix localize.gettext.mf2` reads the lookups to choose what it can convert safely.

  ### Arguments

  * `source` is the text of a source file.

  * `options` is a keyword list of options.

  ### Options

  * `:default_domain` is the domain of a call that names none. The default is `"default"`.

  ### Returns

  * `{:ok, lookups}`, a list of `t:lookup/0` in the order they appear, or

  * `{:error, exception}` when `source` is not a string.

  ### Examples

      iex> {:ok, [literal, dynamic]} =
      ...>   Localize.Gettext.Migration.lookups(~S|gettext("Hello %{name}", name: n) <> Gettext.dgettext(MyApp.Gettext, "errors", message)|)
      iex> {literal.domain, literal.msgid}
      {"default", "Hello %{name}"}
      iex> {dynamic.domain, dynamic.msgid}
      {"errors", :dynamic}

  """
  @spec lookups(String.t(), Keyword.t()) :: {:ok, [lookup()]} | {:error, Exception.t()}
  def lookups(source, options \\ [])

  def lookups(source, options) when is_binary(source) and is_list(options) do
    default_domain = Keyword.get(options, :default_domain, "default")

    lookups =
      for [{call_start, call_length}, {prefix_start, prefix_length}, {name_start, name_length}] <-
            Regex.scan(@gettext_call, source, return: :index, capture: :all),
          call = %{
            prefix: binary_part(source, prefix_start, prefix_length),
            name: binary_part(source, name_start, name_length),
            name_start: name_start,
            open: call_start + call_length - 1
          },
          {:ok, spans} <- [Arguments.spans(source, call.open)] do
        analyze_call(source, call, spans, default_domain)
      end

    {:ok, lookups}
  end

  def lookups(source, _options) do
    {:error,
     Localize.InvalidValueError.exception(value: source, expected: "a source file as a string")}
  end

  @doc """
  Converts the msgids of the `gettext` calls in a source file to MF2, as `convert/2` converts them in a catalog.

  Conversion is a function of the msgid alone, so a msgid converted here matches the msgid `convert/1` gives its catalog entry, and the two can be converted separately. The calls are found in the text, so a call in a HEEx template or in a `~H` sigil is converted as one in a module is: each Gettext macro, with or without `_noop`, bare or through its backend module, and each `Gettext` function, which takes the backend first. A msgid written as a string literal, a heredoc included, is rewritten as a string literal; one written as a sigil, a concatenation or an expression that holds a `%{name}` placeholder is left as it is and reported. A call in a comment or a documentation string is converted too, as it is found in text.

  With the `:plurals` option, a plural call, `ngettext` or its `d`, `p` and `dp` forms, whose entry `convert/2` writes as a `.match` message becomes the singular call, `gettext` and the rest, with that message as its msgid and the count in its bindings, written last so it wins as Gettext's does. Its domain and context must be string literals to know whether its entry is converted. Run `mix format` afterwards, as the bindings are written on one line.

  ### Arguments

  * `source` is the text of a source file.

  * `options` is a keyword list of options.

  ### Options

  * `:plurals` is `false`, the default, to leave plural calls as plural calls with their msgids converted, or the plural entries to convert, as a set of `t:plural_key/0` for every domain or a map of domain to such a set, built from `convertible_plurals/2` over the domain's catalogs.

  * `:source_locale` is the language msgids are written in, as for `convert/2`. The default is `"en"`.

  * `:default_domain` is the domain of a call that names none, the backend's default domain. The default is `"default"`.

  * `:only` is the entries whose calls to convert, as a set of `{context, msgid}` keys for every domain or a map of domain to such a set, leaving every other call as it is. The default is `nil`, which converts every call.

  ### Returns

  * `{:ok, source, report}`, where `source` is the converted text and `report` is a map with `:rewritten`, the number of msgids rewritten, and `:skipped`, the msgids left for a person to convert, each a map with `:line`, `:call` and `:reason`, or

  * `{:error, exception}` when `source` is not a string or an option is not valid.

  ### Examples

      iex> Localize.Gettext.Migration.convert_source(~S|gettext("Hello %{name}", name: user.name)|)
      {:ok, ~S|gettext("Hello {$name}", name: user.name)|, %{rewritten: 1, skipped: []}}

      iex> Localize.Gettext.Migration.convert_source(~S|ngettext("%{count} file", "%{count} files", n)|)
      {:ok, ~S|ngettext("{$count} file", "{$count} files", n)|, %{rewritten: 2, skipped: []}}

      iex> keys = MapSet.new([{nil, "%{count} file", "%{count} files"}])
      iex> {:ok, source, _report} =
      ...>   Localize.Gettext.Migration.convert_source(~S|ngettext("%{count} file", "%{count} files", n)|, plurals: keys)
      iex> source
      ~S|gettext(".local $plural_count = {$count :number}\\n.match $plural_count\\none {{{$count} file}}\\n* {{{$count} files}}", count: n)|

  """
  @spec convert_source(String.t(), Keyword.t()) ::
          {:ok, String.t(), %{rewritten: non_neg_integer(), skipped: [skipped()]}}
          | {:error, Exception.t()}
  def convert_source(source, options \\ [])

  def convert_source(source, options) when is_binary(source) and is_list(options) do
    with {:ok, context} <- source_context(options) do
      {converted, rewritten, skipped} = convert_text(source, context)
      {:ok, converted, %{rewritten: rewritten, skipped: skipped}}
    end
  end

  def convert_source(source, _options) do
    {:error,
     Localize.InvalidValueError.exception(value: source, expected: "a source file as a string")}
  end

  defp source_context(options) do
    with {:ok, plurals} <- source_plurals(Keyword.get(options, :plurals, false)),
         {:ok, only} <- only_option(Keyword.get(options, :only)),
         {:ok, rules} <- source_plural_rules(plurals, Keyword.get(options, :source_locale, "en")) do
      {:ok,
       %{
         plurals: plurals,
         only: only,
         rules: rules,
         default_domain: Keyword.get(options, :default_domain, "default")
       }}
    end
  end

  defp only_option(nil) do
    {:ok, nil}
  end

  defp only_option(%MapSet{} = keys) do
    {:ok, keys}
  end

  defp only_option(%{} = by_domain) do
    {:ok, by_domain}
  end

  defp only_option(only) do
    {:error,
     Localize.InvalidValueError.exception(
       value: only,
       expected:
         "nil, a set of {context, msgid} keys, or a map of domain to such a set, for the :only option"
     )}
  end

  defp source_plurals(false) do
    {:ok, false}
  end

  defp source_plurals(%MapSet{} = keys) do
    {:ok, keys}
  end

  defp source_plurals(%{} = by_domain) do
    {:ok, by_domain}
  end

  defp source_plurals(plurals) do
    {:error,
     Localize.InvalidValueError.exception(
       value: plurals,
       expected:
         "false, a set of plural keys, or a map of domain to such a set, for the :plurals option"
     )}
  end

  defp source_plural_rules(false, _source_locale) do
    {:ok, nil}
  end

  defp source_plural_rules(_plurals, source_locale) do
    language_rules(source_locale, nil)
  end

  # The text with its calls converted: each plural call whose entry is to
  # be converted becomes a singular call, with any call in its count or
  # bindings converted inside it, and each other msgid literal is
  # rewritten in place.
  defp convert_text(source, context) do
    {replacements, skipped} =
      @gettext_call
      |> Regex.scan(source, return: :index, capture: :all)
      |> Enum.reduce({[], []}, &call_replacements(source, &1, context, &2))

    kept = outermost(replacements)
    rewritten = Enum.sum_by(kept, fn {_start, _stop, _text, count} -> count end)

    converted =
      kept
      |> Enum.sort_by(fn {start, _stop, _text, _count} -> start end, :desc)
      |> Enum.reduce(source, &replace/2)

    {converted, rewritten, Enum.reverse(skipped)}
  end

  # A replacement inside another, such as a call in a converted plural
  # call's bindings, was made inside the outer one already.
  defp outermost(replacements) do
    sorted =
      replacements
      |> Enum.uniq_by(fn {start, _stop, _text, _count} -> start end)
      |> Enum.sort_by(fn {start, stop, _text, _count} -> {start, -stop} end)

    {kept, _limit} =
      Enum.reduce(sorted, {[], -1}, fn {start, stop, _text, _count} = replacement,
                                       {kept, limit} ->
        if start < limit do
          {kept, limit}
        else
          {[replacement | kept], stop}
        end
      end)

    kept
  end

  defp call_replacements(
         source,
         [{call_start, call_length}, {prefix_start, prefix_length}, {name_start, name_length}],
         context,
         acc
       ) do
    call = %{
      prefix: binary_part(source, prefix_start, prefix_length),
      name: binary_part(source, name_start, name_length),
      name_start: name_start,
      open: call_start + call_length - 1
    }

    case Arguments.spans(source, call.open) do
      {:ok, spans} -> call_or_msgid_replacements(source, call, spans, context, acc)
      :error -> acc
    end
  end

  defp call_or_msgid_replacements(source, call, spans, context, acc) do
    lookup = analyze_call(source, call, spans, context.default_domain)

    if selected_entry?(context.only, lookup) do
      selected_call_replacements(source, call, spans, context, acc)
    else
      acc
    end
  end

  defp selected_call_replacements(source, call, spans, context, acc) do
    case plural_call(source, call, spans, context) do
      {:ok, replacement} ->
        {replacements, skipped} = acc
        {[replacement | replacements], skipped}

      {:skip, reason} ->
        {replacements, skipped} =
          msgid_replacements(source, spans, positions(call.prefix, call.name), call.name, acc)

        {replacements,
         [%{line: line_of(source, call.name_start), call: call.name, reason: reason} | skipped]}

      :not_converted ->
        msgid_replacements(source, spans, positions(call.prefix, call.name), call.name, acc)
    end
  end

  # An entry is converted where `:only` names it in the call's domain, or
  # everywhere when there is no `:only`. A call whose domain, context or
  # msgid is not a literal names no entry.
  defp selected_entry?(nil, _lookup) do
    true
  end

  defp selected_entry?(only, %{domain: domain, context: msgctxt, msgid: msgid}) do
    if :dynamic in [domain, msgctxt, msgid] do
      false
    else
      MapSet.member?(domain_keys(only, domain), {msgctxt, msgid})
    end
  end

  defp domain_keys(%MapSet{} = keys, _domain) do
    keys
  end

  defp domain_keys(%{} = by_domain, domain) do
    Map.get(by_domain, domain, MapSet.new())
  end

  # What a call looks up: its domain, context, msgid and plural msgid, each
  # the literal's value or `:dynamic` where the argument is an expression.
  defp analyze_call(source, call, spans, default_domain) do
    shift = backend_shift(call.prefix)
    base = String.replace_suffix(call.name, "_noop", "")
    [msgid_index | plural_index] = Enum.map(Map.fetch!(@msgid_positions, base), &(&1 + shift))

    %{
      call: call.name,
      line: line_of(source, call.name_start),
      domain: lookup_domain(source, base, spans, shift, default_domain),
      context: lookup_context(source, base, spans, shift),
      msgid: literal_or_dynamic(source, Enum.at(spans, msgid_index)),
      msgid_plural: lookup_plural(source, spans, plural_index)
    }
  end

  defp lookup_domain(source, "d" <> _rest, spans, shift, _default_domain) do
    literal_or_dynamic(source, Enum.at(spans, shift))
  end

  defp lookup_domain(_source, _name, _spans, _shift, default_domain) do
    default_domain
  end

  defp lookup_context(source, "dp" <> _rest, spans, shift) do
    literal_or_dynamic(source, Enum.at(spans, shift + 1))
  end

  defp lookup_context(source, "p" <> _rest, spans, shift) do
    literal_or_dynamic(source, Enum.at(spans, shift))
  end

  defp lookup_context(_source, _name, _spans, _shift) do
    nil
  end

  defp lookup_plural(_source, _spans, []) do
    nil
  end

  defp lookup_plural(source, spans, [index]) do
    literal_or_dynamic(source, Enum.at(spans, index))
  end

  defp literal_or_dynamic(source, span) do
    case span_literal(source, span) do
      {:ok, value, _start, _stop} -> value
      :not_converted -> :dynamic
    end
  end

  # A plural call whose entry is among the domain's plural keys, as a
  # singular call with the count in its bindings.
  defp plural_call(_source, _call, _spans, %{plurals: false}) do
    :not_converted
  end

  defp plural_call(source, call, spans, context) do
    if String.contains?(call.name, "ngettext") do
      plural_call_parts(source, call, spans, context)
    else
      :not_converted
    end
  end

  defp plural_call_parts(source, call, spans, context) do
    shift = backend_shift(call.prefix)
    base = String.replace_suffix(call.name, "_noop", "")
    [msgid_index, plural_index] = Enum.map(Map.fetch!(@msgid_positions, base), &(&1 + shift))

    with {:ok, domain} <- call_domain(source, base, spans, shift, context),
         {:ok, msgctxt} <- call_context(source, base, spans, shift),
         {:ok, msgid, msgid_start, _stop} <- span_literal(source, Enum.at(spans, msgid_index)),
         {:ok, msgid_plural, _start, plural_stop} <-
           span_literal(source, Enum.at(spans, plural_index)),
         :ok <- selected(context.plurals, domain, {msgctxt, msgid, msgid_plural}),
         {:ok, message} <- plural_source_message(msgid, msgid_plural, context.rules) do
      rest = Enum.drop(spans, plural_index + 1)
      head = binary_part(source, call.open, msgid_start - call.open)
      plural_call_text(source, call, head, message, plural_stop, rest, context)
    end
  end

  defp backend_shift("Gettext.") do
    1
  end

  defp backend_shift(_prefix) do
    0
  end

  # The domain of a `d` call is its first argument, which must be a
  # literal to know which catalogs agreed to convert the entry.
  defp call_domain(source, "d" <> _rest, spans, shift, _context) do
    case span_literal(source, Enum.at(spans, shift)) do
      {:ok, domain, _start, _stop} -> {:ok, domain}
      :not_converted -> {:skip, "the domain of a plural call is not a string literal"}
    end
  end

  defp call_domain(_source, _name, _spans, _shift, context) do
    {:ok, context.default_domain}
  end

  # The context of a `p` call is its argument before the msgid.
  defp call_context(source, "dp" <> _rest, spans, shift) do
    context_literal(source, Enum.at(spans, shift + 1))
  end

  defp call_context(source, "p" <> _rest, spans, shift) do
    context_literal(source, Enum.at(spans, shift))
  end

  defp call_context(_source, _name, _spans, _shift) do
    {:ok, nil}
  end

  defp context_literal(source, span) do
    case span_literal(source, span) do
      {:ok, msgctxt, _start, _stop} -> {:ok, msgctxt}
      :not_converted -> {:skip, "the context of a plural call is not a string literal"}
    end
  end

  defp selected(%MapSet{} = keys, _domain, key) do
    selected_in(keys, key)
  end

  defp selected(%{} = by_domain, domain, key) do
    selected_in(Map.get(by_domain, domain, MapSet.new()), key)
  end

  defp selected_in(keys, key) do
    if MapSet.member?(keys, key) do
      :ok
    else
      :not_converted
    end
  end

  defp plural_source_message(msgid, msgid_plural, rules) do
    case rules_message([msgid, msgid_plural], rules) do
      {:ok, message} -> {:ok, message}
      {:error, _reason} -> :not_converted
    end
  end

  # A string literal argument, its value and where the literal lies.
  defp span_literal(_source, nil) do
    :not_converted
  end

  defp span_literal(source, {start, stop}) do
    text = binary_part(source, start, stop - start)
    leading = byte_size(text) - byte_size(String.trim_leading(text))
    literal = String.trim(text)

    case literal_value(literal) do
      {:ok, value} -> {:ok, value, start + leading, start + leading + byte_size(literal)}
      :error -> :not_converted
    end
  end

  # A string literal, a heredoc included, or a `~s` or `~S` sigil with no
  # interpolation and no modifiers, which Gettext reads as the string it
  # is. No atom is made: a string needs none, and anything else is not a
  # msgid to rewrite.
  defp literal_value(literal) do
    case Code.string_to_quoted(literal, existing_atoms_only: true) do
      {:ok, value} when is_binary(value) ->
        {:ok, value}

      {:ok, {:sigil_S, _meta, [{:<<>>, _parts, [value]}, []]}} when is_binary(value) ->
        {:ok, value}

      {:ok, {:sigil_s, _meta, [{:<<>>, _parts, [value]}, []]}} when is_binary(value) ->
        {:ok, Macro.unescape_string(value)}

      _not_a_string ->
        :error
    end
  end

  # The call from its name to its last argument: the singular name, the
  # arguments before the msgid as written, the msgid, and for a call with
  # a count, bindings that hold it.
  defp plural_call_text(source, call, head, message, plural_stop, rest, context) do
    name = String.replace(call.name, "ngettext", "gettext")
    literal = inspect(message, printable_limit: :infinity)

    case rest do
      [] ->
        {:ok, {call.name_start, plural_stop, name <> head <> literal, 1}}

      [count_span | binding_spans] ->
        {_start, last_stop} = List.last(rest)
        count = converted_span(source, count_span, context)
        bindings = Enum.map(binding_spans, &converted_span(source, &1, context))

        case count_bindings(count, bindings) do
          {:ok, bindings_text} ->
            {:ok,
             {call.name_start, last_stop, name <> head <> literal <> ", " <> bindings_text, 1}}

          {:skip, reason} ->
            {:skip, reason}
        end
    end
  end

  defp converted_span(source, {start, stop}, context) do
    text =
      source
      |> binary_part(start, stop - start)
      |> String.trim()

    {converted, _rewritten, _skipped} = convert_text(text, context)
    converted
  end

  # Gettext puts the count in the bindings, after the caller's, so it is
  # written last, where it wins as it does there.
  defp count_bindings(count, []) do
    {:ok, "count: " <> count}
  end

  defp count_bindings(count, ["[" <> _rest = list]) do
    {:ok, inner_with_count(list, "[", "]", count)}
  end

  defp count_bindings(count, ["%{" <> _rest = map]) do
    {:ok, inner_with_count(map, "%{", "}", count)}
  end

  defp count_bindings(count, [expression]) do
    if keyword?(expression) do
      {:ok, expression <> ", count: " <> count}
    else
      {:ok, "Map.put(Map.new(" <> expression <> "), :count, " <> count <> ")"}
    end
  end

  defp count_bindings(count, [_ | _] = arguments) do
    if Enum.all?(arguments, &keyword?/1) do
      {:ok, Enum.join(arguments, ", ") <> ", count: " <> count}
    else
      {:skip, "the bindings of a plural call are not a keyword list, a map or one expression"}
    end
  end

  defp inner_with_count(text, opening, closing, count) do
    inner =
      text
      |> String.replace_prefix(opening, "")
      |> String.replace_suffix(closing, "")
      |> String.trim()
      |> String.trim_trailing(",")

    if inner == "" do
      opening <> "count: " <> count <> closing
    else
      opening <> inner <> ", count: " <> count <> closing
    end
  end

  defp keyword?(text) do
    Regex.match?(~r/\A(?:[a-z_][a-zA-Z0-9_]*[?!]?|"[^"]*"):\s/u, text)
  end

  defp line_of(source, position) do
    source
    |> binary_part(0, position)
    |> String.split("\n")
    |> length()
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

    case literal_value(literal) do
      {:ok, msgid} ->
        to = migrate(msgid)

        if to == msgid do
          {replacements, skipped}
        else
          replacement =
            {literal_start, literal_start + byte_size(literal),
             inspect(to, printable_limit: :infinity), 1}

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
      line = line_of(source, position)

      [
        %{line: line, call: name, reason: "the msgid is not a string literal: #{literal}"}
        | skipped
      ]
    else
      skipped
    end
  end

  defp replace({start, stop, text, _count}, source) do
    binary_part(source, 0, start) <> text <> binary_part(source, stop, byte_size(source) - stop)
  end

  defp catalog_only(nil) do
    {:ok, nil}
  end

  defp catalog_only(%MapSet{} = keys) do
    {:ok, keys}
  end

  defp catalog_only(only) do
    {:error,
     Localize.InvalidValueError.exception(
       value: only,
       expected: "nil or a set of {context, msgid} keys for the :only option"
     )}
  end

  # An entry `:only` does not name is left as it is.
  defp convert_selected(message, renames, only, plurals, rules) do
    if is_nil(only) or MapSet.member?(only, entry_key(message)) do
      convert_message(message, renames, plurals, rules)
    else
      {message, renames}
    end
  end

  defp entry_key(message) do
    {context(message.msgctxt), IO.iodata_to_binary(message.msgid)}
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
