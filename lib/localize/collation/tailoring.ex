defmodule Localize.Collation.Tailoring do
  # CLDR locale-specific collation tailoring.
  #
  # Parses and applies CLDR tailoring rules that modify the root collation order
  # for specific locales. Rules use the ICU/CLDR syntax defined in UTS #35:
  #
  # * `&X` - reset position to after character X.
  #
  # * `&[before N]X` - reset to just before X at level N.
  #
  # * `<` - primary difference (new letter).
  #
  # * `<<` - secondary difference (accent variant).
  #
  # * `<<<` - tertiary difference (case variant).
  #
  # * `[caseFirst upper]` - option overrides.
  #
  # Tailoring data is embedded directly from CLDR XML sources, covering common
  # European and Asian locales.
  #
  @moduledoc false

  alias Localize.Collation.{Element, Table}
  alias Localize.Collation.Table.Parser

  @bidi_lrm <<0x200E::utf8>>

  @bidi_rlm <<0x200F::utf8>>

  # The forms a collation type's rules may take: `:standard`, the
  # collation with no `alt`, and CLDR's `alt="short"` alternative.
  @forms [:standard, :short]

  # Synthetic primary weights for the CLDR positional anchors.
  #
  # Rules after `&[last regular]` place characters after every regular
  # primary and before the implicit weights of the Han characters they do
  # not name, which begin at 0xFB40. The table's regular primaries end at
  # 0xFB20, so there is no room for the 102,615 entries of zh stroke as
  # single 16-bit primaries.
  #
  # Such a rule is given a position rather than a weight while the rules
  # are applied: `{:tailored, path}`, where paths compare as lists. A
  # relation after a relation increments the last component; a relation
  # after a reset to a position inserts below it, `path ++ [-index, 1]`, so
  # that `&虫<重庆` falls between 虫 and the character after it, and a later
  # insertion at the same place sorts before an earlier one, as TR35 has
  # it. Once every rule is applied the positions are numbered in order and
  # each is written as two elements, as UTS #10 writes an implicit weight:
  # a lead in 0xFB21..0xFB3F carrying the secondary and tertiary weights,
  # then a trail in 0x8000..0xFFFF. The 31 leads give 1,015,808 places, so
  # the pairs sort after every regular character and before the untailored
  # Han.
  @last_regular_position {:tailored, [0]}

  @tailored_first_lead 0xFB21

  @tailored_last_lead 0xFB3F

  @tailored_trail_base 0x8000

  @tailored_trail_span 0x8000

  @synthetic_first_regular 0x0300

  @synthetic_last_primary_ignorable 0x02FF

  @synthetic_first_primary_ignorable 0x0100

  @synthetic_last_secondary_ignorable 0x00

  @synthetic_first_secondary_ignorable 0x00

  @synthetic_last_tertiary_ignorable 0x00

  @synthetic_first_tertiary_ignorable 0x00

  # The tailoring table (~500KB of rule strings) is loaded at runtime
  # on first use rather than embedded at compile time — embedding it
  # made this the largest beam in the library (~1.7MB) for data that
  # many applications never touch. `Localize.DataLoader` deduplicates
  # concurrent first loads; per-{language, type} results are then
  # cached in `:persistent_term` by `get_tailoring/2`.
  defp tailorings do
    Localize.DataLoader.load({:localize, :collation_tailorings}, fn ->
      "localize/supplemental_data/collation_tailoring.etf"
      |> Localize.Priv.path()
      |> File.read!()
      |> :erlang.binary_to_term()
    end)
  end

  # Collation data inherits along its own chain (TR35): a locale's parent
  # drops its last subtag unless the `collations` component of
  # `parentLocales` names another, so `zh-Hant` takes `zh`'s data although
  # its main parent is the root. The chains, and each locale's default
  # collation type, are built from CLDR by the data pass, so a lookup is a
  # map read that walks no parents and builds no identifier.
  defp inheritance do
    Localize.DataLoader.load({:localize, :collation_inheritance}, fn ->
      "localize/supplemental_data/collation_inheritance.etf"
      |> Localize.Priv.path()
      |> File.read!()
      |> :erlang.binary_to_term()
    end)
  end

  @doc false
  # The locales whose collation data a validated tag inherits, nearest
  # first and ending with the root, `:und`.
  @spec collation_chain(Localize.LanguageTag.t()) :: [atom(), ...]
  def collation_chain(%Localize.LanguageTag{cldr_locale_id: locale_id}) do
    Map.get(inheritance().chains, locale_id, [:und])
  end

  @doc false
  # The collation type CLDR makes a validated tag's default: the
  # `defaultCollation` of the first locale on its collation chain that
  # declares one, such as `:pinyin` for `zh` and `:stroke` for `zh-Hant`.
  @spec default_type(Localize.LanguageTag.t()) :: atom()
  def default_type(%Localize.LanguageTag{cldr_locale_id: locale_id}) do
    Map.get(inheritance().default_types, locale_id, :standard)
  end

  @doc """
  Get a tailoring overlay for the given locale and collation type.

  ### Arguments

  * `locale` - a `t:Localize.LanguageTag.t/0`, or a locale name as an atom
    or a binary, which is validated first.

  * `type` - collation type atom (e.g., `:standard`, `:phonebook`, `:traditional`).

  * `prefer` - the form of the type's rules: `:standard` (the default) or
    `:short`, CLDR's `alt="short"` alternative. A locale whose type has no
    such form takes its `:standard` form.

  ### Returns

  * `{overlay, option_overrides}` - a map of overlay entries and a keyword list of option overrides.

  * `nil` - if no tailoring of that type exists for the locale or any locale on its collation chain, the root included, or `prefer` is not a form.

  """
  @spec get_tailoring(Localize.LanguageTag.t() | atom() | String.t(), atom(), atom()) ::
          {map(), keyword()} | nil
  def get_tailoring(locale, type, prefer \\ :standard)

  def get_tailoring(%Localize.LanguageTag{} = language_tag, type, prefer) when prefer in @forms do
    cache_key = {:localize, :collation_tailoring, language_tag.cldr_locale_id, type, prefer}

    case :persistent_term.get(cache_key, :unset) do
      :unset -> cache_tailoring(cache_key, language_tag, type, prefer)
      cached -> cached
    end
  end

  def get_tailoring(%Localize.LanguageTag{}, _type, _prefer) do
    nil
  end

  def get_tailoring(locale, type, prefer) do
    case Localize.validate_locale(locale) do
      {:ok, language_tag} -> get_tailoring(language_tag, type, prefer)
      {:error, _reason} -> nil
    end
  end

  # The type is the caller's, so a type no tailoring has, which no locale or
  # parent can match, is answered without a lookup and without a key; each
  # such type would otherwise add a key that is never removed.
  defp cache_tailoring(cache_key, language_tag, type, prefer) do
    if known_type?(type) do
      result = tailoring_for(language_tag, type, prefer)
      Localize.LiteralMemory.cache(cache_key, result)
      result
    else
      nil
    end
  end

  defp preferred_rules(nil, _prefer) do
    nil
  end

  defp preferred_rules(forms, prefer) do
    Map.get(forms, prefer) || Map.get(forms, :standard)
  end

  defp known_type?(type) do
    Enum.any?(tailorings(), fn {{_locale_id, known}, _rules} -> known == type end)
  end

  # The data is keyed by the CLDR locale a tailoring file is for, and holds
  # each type's rules by form. A locale takes the tailoring of the first
  # locale on its collation chain that has one of the type, in the preferred
  # form, or in its `:standard` form when it has no preferred one.
  defp tailoring_for(language_tag, type, prefer) do
    tailorings = tailorings()

    rules =
      language_tag
      |> collation_chain()
      |> Enum.find_value(&preferred_rules(Map.get(tailorings, {&1, type}), prefer))

    if is_nil(rules) do
      nil
    else
      build_tailoring(rules)
    end
  end

  @doc """
  List all supported locale/type combinations.

  ### Returns

  A list of `{cldr_locale_id, type}` tuples.

  ### Examples

      iex> locales = Localize.Collation.Tailoring.supported_locales()
      iex> {:es, :standard} in locales
      true

  """
  @spec supported_locales() :: [{atom(), atom()}]
  def supported_locales do
    Map.keys(tailorings())
  end

  @doc """
  Parse a CLDR tailoring rule string into a list of operations.

  ### Arguments

  * `rules_str` - a CLDR/ICU tailoring rule string.

  ### Returns

  A list of operation tuples.

  ### Examples

      iex> ops = Localize.Collation.Tailoring.parse_rules("&N<ñ<<<Ñ")
      iex> length(ops)
      3

  """
  @spec parse_rules(String.t()) :: [tuple()]
  def parse_rules(rules_str) do
    rules_str
    |> String.split("\n", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    # Strip `# ...` inline comments PER LINE, before line-continuation
    # joining. If we left them in, the subsequent `.*$` regex in
    # parse_ordering_rules would match the rest of the joined string
    # (no newlines present after join) and silently eat thousands of
    # CJK ordering rules. This bug hid the fact that large CJK
    # tailorings (zh-pinyin, zh-stroke, zh-zhuyin) weren't producing
    # overlay entries for Han characters.
    |> Enum.map(&strip_inline_comment/1)
    |> Enum.reject(&(&1 == ""))
    |> join_continuation_lines()
    |> Enum.flat_map(&parse_rule_line/1)
  end

  defp strip_inline_comment(line) do
    # Match `<whitespace>#<whitespace>rest` or a line starting with `#`.
    # The space before `#` matters: CLDR allows `#` inside quoted
    # character data, but always has a separating space for comments.
    case Regex.run(~r/^(.*?)\s+#\s/, line) do
      [_, before] ->
        String.trim_trailing(before)

      nil ->
        if String.starts_with?(line, "#"), do: "", else: line
    end
  end

  # Join continuation lines onto the previous line. A continuation
  # is any line that starts with an ordering operator (<, <<, <<<,
  # <*, <<*, <<<*, =) without a preceding & reset. These occur when
  # CLDR wraps long rules across multiple lines.
  defp join_continuation_lines(lines) do
    {result, current} =
      Enum.reduce(lines, {[], nil}, fn line, {acc, current} ->
        stripped = strip_bidi_marks(line)
        accumulate_rule_line(continuation_line?(stripped), line, acc, current)
      end)

    result =
      case current do
        nil -> result
        last -> [last | result]
      end

    Enum.reverse(result)
  end

  # A continuation line is appended to the current rule; any other
  # line flushes the current rule and starts a new one.
  defp accumulate_rule_line(true, line, acc, nil), do: {acc, line}
  defp accumulate_rule_line(true, line, acc, previous), do: {acc, previous <> line}
  defp accumulate_rule_line(false, line, acc, nil), do: {acc, line}
  defp accumulate_rule_line(false, line, acc, previous), do: {[previous | acc], line}

  defp continuation_line?(line) do
    String.starts_with?(line, "<<<*") or
      String.starts_with?(line, "<<<") or
      String.starts_with?(line, "<<*") or
      String.starts_with?(line, "<<") or
      String.starts_with?(line, "<*") or
      String.starts_with?(line, "<") or
      String.starts_with?(line, "=")
  end

  defp strip_bidi_marks(str) do
    str
    |> String.replace(@bidi_lrm, "")
    |> String.replace(@bidi_rlm, "")
  end

  defp build_tailoring(rules_str) do
    ops = parse_rules(rules_str)

    {option_ops, ordering_ops} =
      Enum.split_with(ops, fn
        {:option, _, _} -> true
        _ -> false
      end)

    option_overrides =
      Enum.map(option_ops, fn {:option, key, value} -> {key, value} end)

    overlay =
      ordering_ops
      |> apply_operations()
      |> encode_positions()

    {overlay, option_overrides}
  end

  # CLDR collation rule dispatch: one branch per [option] directive
  # plus the ordering-rule and comment line shapes.
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp parse_rule_line(line) do
    line = String.trim(line)

    cond do
      # Option directives
      String.starts_with?(line, "[caseFirst ") ->
        value = line |> String.trim_leading("[caseFirst ") |> String.trim_trailing("]")

        case value do
          "upper" -> [{:option, :case_first, :upper}]
          "lower" -> [{:option, :case_first, :lower}]
          "off" -> [{:option, :case_first, false}]
          _ -> []
        end

      String.starts_with?(line, "[caseLevel on]") ->
        [{:option, :case_level, true}]

      String.starts_with?(line, "[backwards 2]") ->
        [{:option, :backwards, true}]

      String.starts_with?(line, "[alternate shifted]") ->
        [{:option, :alternate, :shifted}]

      String.starts_with?(line, "[normalization on]") ->
        [{:option, :normalization, true}]

      String.starts_with?(line, "[strength ") ->
        value =
          line
          |> String.trim_leading("[strength ")
          |> String.trim_trailing("]")
          |> String.trim()

        case value do
          "1" -> [{:option, :strength, :primary}]
          "2" -> [{:option, :strength, :secondary}]
          "3" -> [{:option, :strength, :tertiary}]
          "4" -> [{:option, :strength, :quaternary}]
          _ -> []
        end

      String.starts_with?(line, "[reorder ") ->
        codes =
          line
          |> String.trim_leading("[reorder ")
          |> String.trim_trailing("]")
          |> String.split()
          |> Enum.map(&String.to_atom/1)

        [{:option, :reorder, codes}]

      String.starts_with?(line, "[suppressContractions") ->
        chars = parse_suppress_contractions(line)
        [{:option, :suppress_contractions, chars}]

      # Ordering rules — strip bidi marks before checking
      String.starts_with?(line, "&") or String.starts_with?(strip_bidi_marks(line), "&") ->
        cleaned = strip_bidi_marks(line) |> String.trim_leading("&")
        parse_reset_and_rules(cleaned)

      true ->
        []
    end
  end

  defp parse_suppress_contractions(line) do
    # Format: [suppressContractions [chars-or-ranges]]
    # Extract the content between the inner brackets
    case Regex.run(~r/\[suppressContractions\s+\[(.+)\]\]/, line) do
      [_, content] ->
        content
        |> decode_unicode_escapes()
        |> expand_ranges()

      nil ->
        []
    end
  end

  defp decode_unicode_escapes(str) do
    Regex.replace(~r/\\u([0-9A-Fa-f]{4})/, str, fn _full, hex ->
      <<String.to_integer(hex, 16)::utf8>>
    end)
  end

  defp expand_ranges(str) do
    # Split by spaces, then expand any X-Y ranges into individual codepoints
    str
    |> String.split(~r/\s+/, trim: true)
    |> Enum.flat_map(fn token ->
      case String.split(token, "-", parts: 2) do
        [from, to] -> expand_range_token(token, from, to)
        [single] -> String.to_charlist(single)
      end
    end)
  end

  defp expand_range_token(token, from, to) do
    from_cp = from |> String.to_charlist() |> List.first()
    to_cp = to |> String.to_charlist() |> List.first()

    if from_cp && to_cp && to_cp >= from_cp do
      Enum.to_list(from_cp..to_cp)
    else
      String.to_charlist(token)
    end
  end

  defp parse_reset_and_rules(str) do
    {reset_op, after_reset} =
      cond do
        # [before N] reset
        match = Regex.run(~r/^\[before (\d)\](.+)$/, str) ->
          [_, level_str, remainder] = match
          level = String.to_integer(level_str)
          {first_char, rest} = split_first_char_sequence(remainder)
          {{:reset_before, level, first_char}, rest}

        # Special reset positions: [last regular], [first primary ignorable], etc.
        match =
            Regex.run(
              ~r/^\[(last|first) (regular|primary ignorable|secondary ignorable|tertiary ignorable)\](.*)$/,
              str
            ) ->
          [_, _pos, _level, rest] = match
          # These are positional anchors — we handle them as a reset to
          # a synthetic position. For now, skip the reset and just parse
          # the ordering rules that follow.
          {{:reset_special, str}, rest}

        true ->
          {first_char, rest} = split_first_char_sequence(str)
          {{:reset, first_char}, rest}
      end

    ordering_ops = parse_ordering_rules(after_reset)
    [reset_op | ordering_ops]
  end

  defp split_first_char_sequence(str) do
    case Regex.run(~r/^(.+?)(<<<\*|<<\*|<\*|<<<|<<|<|=)(.*)$/, str) do
      [_, chars, op, rest] ->
        cps = anchor_to_codepoints(chars)
        {cps, op <> rest}

      nil ->
        cps = anchor_to_codepoints(str)
        {cps, ""}
    end
  end

  defp parse_ordering_rules(""), do: []

  defp parse_ordering_rules(str) do
    # Strip inline comments (# ...) but preserve # inside character data
    str = Regex.replace(~r/\s+#\s.*$/, str, "")

    # Match star syntax, regular operators, or equivalence (=)
    case Regex.run(
           ~r/^(<<<\*|<<\*|<\*|<<<|<<|<|=)(.+?)(?=(<<<\*|<<\*|<\*|<<<|<<|<|=)|$)/,
           str
         ) do
      [full, op, chars | _] ->
        {level, star?} = parse_operator(op)
        rest = String.trim_leading(str, full)
        parse_rule_targets(star?, level, chars, rest)

      nil ->
        []
    end
  end

  # Star syntax: each grapheme cluster gets its own entry
  defp parse_rule_targets(true, level, chars, rest) do
    entries =
      chars
      |> String.trim()
      |> String.graphemes()
      |> Enum.map(fn grapheme ->
        cps = target_to_codepoints(grapheme)
        {level, cps}
      end)

    entries ++ parse_ordering_rules(rest)
  end

  # Regular syntax — handle slash expansion
  defp parse_rule_targets(false, level, chars, rest) do
    {target_chars, expansion} = split_expansion(chars)
    cps = target_to_codepoints(target_chars)

    if expansion do
      expansion_cps = target_to_codepoints(expansion)
      [{level, cps, expansion_cps} | parse_ordering_rules(rest)]
    else
      [{level, cps} | parse_ordering_rules(rest)]
    end
  end

  defp parse_operator("<<<*"), do: {:tertiary, true}
  defp parse_operator("<<*"), do: {:secondary, true}
  defp parse_operator("<*"), do: {:primary, true}
  defp parse_operator("<<<"), do: {:tertiary, false}
  defp parse_operator("<<"), do: {:secondary, false}
  defp parse_operator("<"), do: {:primary, false}
  defp parse_operator("="), do: {:identical, false}

  # Splits "chars/extension" into the relation string and its extension
  # string (TR35 "Expansions").
  defp split_expansion(str) do
    str = String.trim(str)

    case String.split(str, "/", parts: 2) do
      [target, expansion] -> {target, expansion}
      [target] -> {target, nil}
    end
  end

  # Convert rule characters to codepoints. Both anchors and
  # ordering targets use NFC form. The collation table stores
  # entries for precomposed characters, and the overlay keys
  # must match what the engine looks up after normalising input
  # to NFD and then matching against the table/overlay.
  #
  # The collation engine normalises input to NFD, but the table
  # has entries keyed by precomposed codepoints. The overlay
  # lookup in `longest_match_with_overlay` checks the overlay
  # map using `Parser.codepoints_to_key`, which produces a
  # single integer for one codepoint or a tuple for sequences.
  # Since the engine decomposes input to NFD, we store overlay
  # keys in NFD form so they match the decomposed input stream.
  # Anchors (reset characters) use NFC for table lookup since
  # the base collation table has entries for precomposed chars.
  defp anchor_to_codepoints(str) do
    str |> String.trim() |> :unicode.characters_to_nfc_binary() |> String.to_charlist()
  end

  # Targets (ordering characters) use NFD since the collation
  # engine normalises input to NFD before overlay lookup.
  defp target_to_codepoints(str) do
    str |> String.trim() |> :unicode.characters_to_nfd_binary() |> String.to_charlist()
  end

  defp apply_operations(ops) do
    Table.ensure_loaded()

    {overlay, _state} =
      ops
      |> Enum.with_index()
      |> Enum.reduce({%{}, nil}, fn {op, index}, {overlay, state} ->
        apply_operation(op, index, overlay, state)
      end)

    overlay
  end

  # The state is `{:after, elements, insertion}`: the elements of the
  # position the next relation is placed after, and, when that position
  # was set by a reset, the reset's insertion component (see
  # `@last_regular_position`), or `nil` after a relation. A reset is
  # mapped according to the rules applied so far, as TR35 has it, so
  # `&cs<<<ccs/cs` resets to the Hungarian letter cs.
  defp apply_operation({:reset, cps}, index, overlay, _state) do
    {overlay, {:after, current_elements(cps, overlay), -index}}
  end

  defp apply_operation({:reset_before, level, cps}, index, overlay, _state) do
    adjusted = adjust_before(current_elements(cps, overlay), level)
    {overlay, {:after, adjusted, -index}}
  end

  # Positional anchors like `&[last regular]` or `&[first primary
  # ignorable]` insert the rules that follow at a boundary of the primary
  # weights; see `synthetic_anchor_elements/1`.
  defp apply_operation({:reset_special, anchor_str}, index, overlay, _state) do
    {overlay, {:after, synthetic_anchor_elements(anchor_str), -index}}
  end

  # A relation with an extension string (TR35 "Expansions"): the relation
  # string's elements are placed at `level` after the current position, as
  # for any relation, and the extension's elements, as they are mapped so
  # far, are appended unchanged. Only the regular elements are the position
  # for the next relation. `&虫<重庆/庆` places 重庆 primary-after 虫,
  # followed by the elements of 庆, and `&cs<<<ccs/cs` makes Hungarian ccs a
  # tertiary variant of cs followed by cs.
  defp apply_operation(
         {:identical, target_cps, extension_cps},
         _index,
         overlay,
         {:after, anchor_elements, _insertion} = state
       ) do
    key = Parser.codepoints_to_key(target_cps)
    elements = anchor_elements ++ extension_elements(extension_cps, overlay)

    {Map.put(overlay, key, elements), state}
  end

  defp apply_operation(
         {level, target_cps, extension_cps},
         _index,
         overlay,
         {:after, anchor_elements, insertion}
       )
       when level in [:primary, :secondary, :tertiary] do
    regular_elements = compute_tailored_elements(anchor_elements, level, insertion)
    key = Parser.codepoints_to_key(target_cps)
    elements = regular_elements ++ extension_elements(extension_cps, overlay)

    {Map.put(overlay, key, elements), {:after, regular_elements, nil}}
  end

  defp apply_operation({level, _target_cps, _extension_cps}, _index, overlay, nil)
       when level in [:primary, :secondary, :tertiary, :identical] do
    {overlay, nil}
  end

  # Identical (=): the target takes the position's elements, and the
  # position is unchanged for the next relation.
  defp apply_operation({:identical, cps}, _index, overlay, {:after, anchor_elements, _} = state) do
    key = Parser.codepoints_to_key(cps)
    {Map.put(overlay, key, anchor_elements), state}
  end

  defp apply_operation({:identical, _cps}, _index, overlay, nil) do
    {overlay, nil}
  end

  defp apply_operation({level, cps}, _index, overlay, {:after, anchor_elements, insertion})
       when level in [:primary, :secondary, :tertiary] do
    new_elements = compute_tailored_elements(anchor_elements, level, insertion)
    key = Parser.codepoints_to_key(cps)
    {Map.put(overlay, key, new_elements), {:after, new_elements, nil}}
  end

  defp apply_operation({level, _cps}, _index, overlay, nil)
       when level in [:primary, :secondary, :tertiary] do
    {overlay, nil}
  end

  defp apply_operation(other, _index, overlay, state) do
    require Logger

    Logger.debug(
      "Unhandled tailoring operation: #{inspect(other, limit: 3, printable_limit: 120)}",
      domain: [:localize]
    )

    {overlay, state}
  end

  # A reset's elements as the rules applied so far map it: the tailored
  # elements of the string, whose overlay key is its NFD form, or else
  # those of the base table.
  defp current_elements(cps, overlay) do
    key =
      cps
      |> List.to_string()
      |> :unicode.characters_to_nfd_binary()
      |> String.to_charlist()
      |> Parser.codepoints_to_key()

    case Map.get(overlay, key) do
      nil -> lookup_elements(cps)
      elements -> elements
    end
  end

  # The extension's elements as the tailoring maps them so far: the whole
  # extension if it is tailored, else each code point's tailored or base
  # elements.
  defp extension_elements(cps, overlay) do
    case Map.get(overlay, Parser.codepoints_to_key(cps)) do
      nil -> Enum.flat_map(cps, &codepoint_elements(&1, overlay))
      elements -> elements
    end
  end

  defp codepoint_elements(cp, overlay) do
    case Map.get(overlay, Parser.codepoints_to_key([cp])) do
      nil -> lookup_elements([cp])
      elements -> elements
    end
  end

  defp lookup_elements(cps) do
    case Table.lookup(cps) do
      {:ok, elements} ->
        elements

      :unmapped ->
        Enum.flat_map(cps, &lookup_single_codepoint/1)
    end
  end

  defp lookup_single_codepoint(cp) do
    case Table.lookup(cp) do
      {:ok, elements} -> elements
      :unmapped -> [Element.new(0, 0x0020, 0x0002)]
    end
  end

  defp adjust_before([], _level), do: [Element.new(0, 0x0020, 0x0002)]

  defp adjust_before(elements, level) do
    {init, [{p, s, t, v}]} = Enum.split(elements, -1)

    adjusted =
      case level do
        1 -> {primary_before(p), s, t, v}
        2 -> {p, s - 1, t, v}
        3 -> {p, s, t - 1, v}
      end

    init ++ [adjusted]
  end

  defp compute_tailored_elements([], level, _insertion) do
    # Fallback for unmapped anchors — use a synthetic element
    case level do
      :primary -> [Element.new(1, 0x0020, 0x0002)]
      :secondary -> [Element.new(0, 0x0021, 0x0002)]
      :tertiary -> [Element.new(0, 0x0020, 0x0003)]
    end
  end

  defp compute_tailored_elements(anchor_elements, :primary, insertion) do
    {init, [{p, _s, _t, v}]} = Enum.split(anchor_elements, -1)
    init ++ [{primary_after(p, insertion), 0x0020, 0x0002, v}]
  end

  defp compute_tailored_elements(anchor_elements, :secondary, _insertion) do
    {init, [{p, s, _t, v}]} = Enum.split(anchor_elements, -1)
    init ++ [{p, s + 1, 0x0002, v}]
  end

  defp compute_tailored_elements(anchor_elements, :tertiary, _insertion) do
    {init, [{p, s, t, v}]} = Enum.split(anchor_elements, -1)
    init ++ [{p, s, t + 1, v}]
  end

  # The primary after a position: the next sibling after a relation, a new
  # child below it after a reset. A base weight is followed by the next.
  defp primary_after({:tailored, path}, nil) do
    {init, [last]} = Enum.split(path, -1)
    {:tailored, init ++ [last + 1]}
  end

  defp primary_after({:tailored, path}, insertion) do
    {:tailored, path ++ [insertion, 1]}
  end

  defp primary_after(primary, _insertion) do
    primary + 1
  end

  # The primary just before a position: after every descendant of the
  # previous sibling, which `:infinity`, sorting after every integer, gives.
  defp primary_before({:tailored, path}) do
    {init, [last]} = Enum.split(path, -1)
    {:tailored, init ++ [last - 1, :infinity]}
  end

  defp primary_before(primary) do
    primary - 1
  end

  # Numbers the positions in order and writes each as a lead and a trail.
  defp encode_positions(overlay) do
    numbers =
      for {_key, elements} <- overlay,
          {{:tailored, path}, _secondary, _tertiary, _variable} <- elements,
          uniq: true do
        path
      end
      |> Enum.sort()
      |> Enum.with_index()
      |> Map.new()

    Map.new(overlay, fn {key, elements} ->
      {key, Enum.flat_map(elements, &encode_primary(&1, numbers))}
    end)
  end

  # The lead is bounded so that the pair never reaches the implicit Han
  # weights.
  defp encode_primary({{:tailored, path}, secondary, tertiary, variable}, numbers) do
    number = Map.fetch!(numbers, path)
    lead = min(@tailored_first_lead + div(number, @tailored_trail_span), @tailored_last_lead)
    trail = @tailored_trail_base + rem(number, @tailored_trail_span)

    [{lead, secondary, tertiary, variable}, {trail, 0, 0, variable}]
  end

  defp encode_primary(element, _numbers) do
    [element]
  end

  # One branch per CLDR logical-position anchor ([first/last regular,
  # primary/secondary/tertiary ignorable]).
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp synthetic_anchor_elements(str) do
    primary =
      cond do
        String.contains?(str, "[last regular]") ->
          @last_regular_position

        String.contains?(str, "[first regular]") ->
          @synthetic_first_regular

        String.contains?(str, "[last primary ignorable]") ->
          @synthetic_last_primary_ignorable

        String.contains?(str, "[first primary ignorable]") ->
          @synthetic_first_primary_ignorable

        String.contains?(str, "[last secondary ignorable]") ->
          @synthetic_last_secondary_ignorable

        String.contains?(str, "[first secondary ignorable]") ->
          @synthetic_first_secondary_ignorable

        String.contains?(str, "[last tertiary ignorable]") ->
          @synthetic_last_tertiary_ignorable

        String.contains?(str, "[first tertiary ignorable]") ->
          @synthetic_first_tertiary_ignorable

        true ->
          @last_regular_position
      end

    [Element.new(primary, 0x0020, 0x0002)]
  end
end
