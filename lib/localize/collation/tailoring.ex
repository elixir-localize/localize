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

  # The tailoring table (~500KB of rule strings) is loaded at runtime
  # on first use rather than embedded at compile time — embedding it
  # made this the largest beam in the library (~1.7MB) for data that
  # many applications never touch. `Localize.DataLoader` deduplicates
  # concurrent first loads; per-{language, type} results are then
  # cached in `:persistent_term` by `get_tailoring/2`.
  defp tailorings do
    Localize.DataLoader.load({:localize, :collation_tailorings}, fn ->
      :localize
      |> Application.app_dir("priv/localize/supplemental_data/collation_tailoring.etf")
      |> File.read!()
      |> :erlang.binary_to_term()
    end)
  end

  @doc """
  Get a tailoring overlay for the given locale and collation type.

  ### Arguments

  * `language` - ISO 639 language code (e.g., `"sv"`, `"de"`, `"es"`).

  * `type` - collation type atom (e.g., `:standard`, `:phonebook`, `:traditional`).

  ### Returns

  * `{overlay, option_overrides}` - a map of overlay entries and a keyword list of option overrides.

  * `nil` - if no tailoring exists for the given locale and type.

  """
  @spec get_tailoring(String.t(), atom()) :: {map(), keyword()} | nil
  def get_tailoring(language, type) do
    cache_key = {:localize, :collation_tailoring, language, type}

    case :persistent_term.get(cache_key, :unset) do
      :unset ->
        result =
          case Map.get(tailorings(), {language, type}) do
            nil -> get_tailoring_from_parent(language, type, MapSet.new([language]))
            rules_str -> build_tailoring(rules_str)
          end

        :persistent_term.put(cache_key, result)
        result

      cached ->
        cached
    end
  end

  defp get_tailoring_from_parent(language, type, visited) do
    case Localize.validate_locale(language) do
      {:ok, tag} ->
        walk_parent_chain(tag, type, visited)

      {:error, _} ->
        nil
    end
  end

  @dialyzer {:nowarn_function, walk_parent_chain: 3, resolve_parent_tailoring: 3}
  defp walk_parent_chain(tag, type, visited) do
    case Localize.Locale.parent(tag) do
      {:ok, parent_tag} ->
        resolve_parent_tailoring(parent_tag, type, visited)

      {:error, _} ->
        check_und_fallback(type)
    end
  end

  defp resolve_parent_tailoring(parent_tag, type, visited) do
    parent_language = parent_tag.language |> to_string()
    parent_id = Localize.LanguageTag.to_string(parent_tag)

    cond do
      parent_id in visited ->
        # Chain exhausted — try und as final fallback
        check_und_fallback(type)

      parent_language == "und" ->
        # Reached und — check for und tailoring (e.g., und:search)
        case Map.get(tailorings(), {"und", type}) do
          nil -> nil
          rules_str -> build_tailoring(rules_str)
        end

      true ->
        case Map.get(tailorings(), {parent_language, type}) do
          nil ->
            walk_parent_chain(parent_tag, type, MapSet.put(visited, parent_id))

          rules_str ->
            build_tailoring(rules_str)
        end
    end
  end

  defp check_und_fallback(type) do
    case Map.get(tailorings(), {"und", type}) do
      nil -> nil
      rules_str -> build_tailoring(rules_str)
    end
  end

  @doc """
  List all supported locale/type combinations.

  ### Returns

  A list of `{language, type}` tuples.

  ### Examples

      iex> locales = Localize.Collation.Tailoring.supported_locales()
      iex> {"es", :standard} in locales
      true

  """
  @spec supported_locales() :: [{String.t(), atom()}]
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

  @bidi_lrm <<0x200E::utf8>>
  @bidi_rlm <<0x200F::utf8>>
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

    overlay = apply_operations(ordering_ops)

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

  # Split "chars/expansion" — for now we record the target chars
  # and ignore the expansion (expansion support requires changes
  # to the collation engine to generate expansion sort keys).
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
      Enum.reduce(ops, {%{}, nil}, fn op, {overlay, state} ->
        apply_operation(op, overlay, state)
      end)

    overlay
  end

  defp apply_operation({:reset, cps}, overlay, _state) do
    elements = lookup_elements(cps)
    {overlay, {:after, elements}}
  end

  defp apply_operation({:reset_before, level, cps}, overlay, _state) do
    elements = lookup_elements(cps)
    adjusted = adjust_before(elements, level)
    {overlay, {:after, adjusted}}
  end

  # Positional anchors like `&[last regular]` or `&[first
  # primary ignorable]`. Semantically these insert subsequent
  # `<X<Y...` rules at a specific boundary in the primary-weight
  # spectrum. We map each anchor to a synthetic element whose
  # primary is outside the DUCET range so subsequent `<*` rules
  # get incrementing primaries that won't collide with real
  # DUCET entries. This unlocks thousands of Han ordering rules
  # in the CJK tailorings (pinyin, stroke, zhuyin).
  defp apply_operation({:reset_special, anchor_str}, overlay, _state) do
    elements = synthetic_anchor_elements(anchor_str)
    {overlay, {:after, elements}}
  end

  # Expansion: target sorts at `level` relative to the
  # expansion's collation elements. E.g., ccs/cs means
  # ccs produces the same elements as cs but at tertiary
  # level below.
  defp apply_operation({level, target_cps, expansion_cps}, overlay, _state)
       when level in [:primary, :secondary, :tertiary, :identical] do
    expansion_key = Parser.codepoints_to_key(expansion_cps)

    expansion_elements =
      case Map.get(overlay, expansion_key) do
        nil -> lookup_elements(expansion_cps)
        elements -> elements
      end

    new_elements =
      if level == :identical do
        expansion_elements
      else
        compute_tailored_elements(expansion_elements, level)
      end

    key = Parser.codepoints_to_key(target_cps)
    new_overlay = Map.put(overlay, key, new_elements)
    {new_overlay, {:after, new_elements}}
  end

  # Identical (=): target gets the same elements as the anchor
  defp apply_operation({:identical, cps}, overlay, {:after, anchor_elements} = state) do
    key = Parser.codepoints_to_key(cps)
    new_overlay = Map.put(overlay, key, anchor_elements)
    # State stays the same — next entry still relative to anchor
    {new_overlay, state}
  end

  defp apply_operation({:identical, _cps}, overlay, nil) do
    {overlay, nil}
  end

  defp apply_operation({level, cps}, overlay, {:after, anchor_elements})
       when level in [:primary, :secondary, :tertiary] do
    new_elements = compute_tailored_elements(anchor_elements, level)
    key = Parser.codepoints_to_key(cps)
    new_overlay = Map.put(overlay, key, new_elements)
    {new_overlay, {:after, new_elements}}
  end

  defp apply_operation({level, _cps}, overlay, nil)
       when level in [:primary, :secondary, :tertiary] do
    {overlay, nil}
  end

  defp apply_operation(other, overlay, state) do
    require Logger

    Logger.debug(
      "Unhandled tailoring operation: #{inspect(other, limit: 3, printable_limit: 120)}",
      domain: [:localize]
    )

    {overlay, state}
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
        1 -> {p - 1, s, t, v}
        2 -> {p, s - 1, t, v}
        3 -> {p, s, t - 1, v}
      end

    init ++ [adjusted]
  end

  defp compute_tailored_elements([], level) do
    # Fallback for unmapped anchors — use a synthetic element
    case level do
      :primary -> [Element.new(1, 0x0020, 0x0002)]
      :secondary -> [Element.new(0, 0x0021, 0x0002)]
      :tertiary -> [Element.new(0, 0x0020, 0x0003)]
    end
  end

  defp compute_tailored_elements(anchor_elements, :primary) do
    {init, [{p, _s, _t, v}]} = Enum.split(anchor_elements, -1)
    init ++ [{p + 1, 0x0020, 0x0002, v}]
  end

  defp compute_tailored_elements(anchor_elements, :secondary) do
    {init, [{p, s, _t, v}]} = Enum.split(anchor_elements, -1)
    init ++ [{p, s + 1, 0x0002, v}]
  end

  defp compute_tailored_elements(anchor_elements, :tertiary) do
    {init, [{p, s, t, v}]} = Enum.split(anchor_elements, -1)
    init ++ [{p, s, t + 1, v}]
  end

  # Synthetic primary weights for the CLDR positional anchors. These
  # need to satisfy two constraints:
  #
  # 1. Subsequent `<X<Y...` rules increment the primary each time.
  #    Large tailorings (e.g. zh-pinyin, zh-stroke) produce 20,000+
  #    primary entries, so the anchor plus the largest expected
  #    increment must stay within the 16-bit primary weight range
  #    that our sort-key serialization uses. Anchors too close to
  #    0xFFFF cause overflow and break comparison.
  #
  # 2. The anchor should not collide with real DUCET primary weights
  #    for characters that aren't in the overlay. The overlay overrides
  #    per-codepoint, so a collision only matters for chars NOT in the
  #    tailoring — those fall through to DUCET weights directly.
  #
  # We pick 0x8000 (32768) for `[last regular]`. This leaves ~33K
  # primary slots before hitting the implicit-weight boundary (0xFB40),
  # comfortably fitting the largest observed CJK tailoring (~24K
  # primaries for zh-stroke).
  @synthetic_last_regular 0x8000
  @synthetic_first_regular 0x0300
  @synthetic_last_primary_ignorable 0x02FF
  @synthetic_first_primary_ignorable 0x0100
  @synthetic_last_secondary_ignorable 0x00
  @synthetic_first_secondary_ignorable 0x00
  @synthetic_last_tertiary_ignorable 0x00
  @synthetic_first_tertiary_ignorable 0x00

  # One branch per CLDR logical-position anchor ([first/last regular,
  # primary/secondary/tertiary ignorable]).
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp synthetic_anchor_elements(str) do
    primary =
      cond do
        String.contains?(str, "[last regular]") ->
          @synthetic_last_regular

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
          @synthetic_last_regular
      end

    [Element.new(primary, 0x0020, 0x0002)]
  end
end
