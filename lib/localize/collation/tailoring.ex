defmodule Localize.Collation.Tailoring do
  @moduledoc """
  CLDR locale-specific collation tailoring.

  Parses and applies CLDR tailoring rules that modify the root collation order
  for specific locales. Rules use the ICU/CLDR syntax defined in UTS #35:

  * `&X` - reset position to after character X.

  * `&[before N]X` - reset to just before X at level N.

  * `<` - primary difference (new letter).

  * `<<` - secondary difference (accent variant).

  * `<<<` - tertiary difference (case variant).

  * `[caseFirst upper]` - option overrides.

  Tailoring data is embedded directly from CLDR XML sources, covering common
  European and Asian locales.

  """

  alias Localize.Collation.{Element, Table}
  alias Localize.Collation.Table.Parser

  @tailorings_path Path.join(
                     :code.priv_dir(:localize) |> to_string(),
                     "cldr/supplemental_data/collation_tailoring.etf"
                   )
  @external_resource @tailorings_path
  @tailorings @tailorings_path |> File.read!() |> :erlang.binary_to_term()

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
    case Map.get(@tailorings, {language, type}) do
      nil -> get_tailoring_from_parent(language, type, MapSet.new([language]))
      rules_str -> build_tailoring(rules_str)
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

  defp walk_parent_chain(tag, type, visited) do
    case Localize.Locale.parent(tag) do
      {:ok, parent_tag} ->
        parent_language = parent_tag.language |> to_string()
        parent_id = Localize.LanguageTag.to_string(parent_tag)

        if parent_id in visited or parent_language == "und" do
          nil
        else
          case Map.get(@tailorings, {parent_language, type}) do
            nil ->
              walk_parent_chain(parent_tag, type, MapSet.put(visited, parent_id))

            rules_str ->
              build_tailoring(rules_str)
          end
        end

      {:error, _} ->
        nil
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
    Map.keys(@tailorings)
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
    |> Enum.flat_map(&parse_rule_line/1)
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

      # Ordering rules
      String.starts_with?(line, "&") ->
        parse_reset_and_rules(String.trim_leading(line, "&"))

      true ->
        []
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
    case Regex.run(~r/^(.+?)(<<<\*|<<\*|<\*|<<<|<<|<)(.*)$/, str) do
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
    # Match star syntax (<<<*, <<*, <*) or regular (<<<, <<, <)
    case Regex.run(~r/^(<<<\*|<<\*|<\*|<<<|<<|<)(.+?)(?=(<<<\*|<<\*|<\*|<<<|<<|<)|$)/, str) do
      [full, op, chars | _] ->
        {level, star?} = parse_operator(op)
        rest = String.trim_leading(str, full)

        if star? do
          # Star syntax: each grapheme cluster gets its own entry
          entries =
            chars
            |> String.trim()
            |> String.graphemes()
            |> Enum.map(fn grapheme ->
              cps = target_to_codepoints(grapheme)
              {level, cps}
            end)

          entries ++ parse_ordering_rules(rest)
        else
          # Regular syntax — handle slash expansion
          {target_chars, expansion} = split_expansion(chars)
          cps = target_to_codepoints(target_chars)

          if expansion do
            expansion_cps = target_to_codepoints(expansion)
            [{level, cps, expansion_cps} | parse_ordering_rules(rest)]
          else
            [{level, cps} | parse_ordering_rules(rest)]
          end
        end

      nil ->
        []
    end
  end

  defp parse_operator("<<<*"), do: {:tertiary, true}
  defp parse_operator("<<*"), do: {:secondary, true}
  defp parse_operator("<*"), do: {:primary, true}
  defp parse_operator("<<<"), do: {:tertiary, false}
  defp parse_operator("<<"), do: {:secondary, false}
  defp parse_operator("<"), do: {:primary, false}

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
        case op do
          {:reset, cps} ->
            elements = lookup_elements(cps)
            {overlay, {:after, elements}}

          {:reset_before, level, cps} ->
            elements = lookup_elements(cps)
            adjusted = adjust_before(elements, level)
            {overlay, {:after, adjusted}}

          # Expansion: target sorts at `level` relative to the
          # expansion's collation elements. E.g., ccs/cs means
          # ccs produces the same elements as cs but at tertiary
          # level below.
          {level, target_cps, expansion_cps}
          when level in [:primary, :secondary, :tertiary] ->
            expansion_key = Parser.codepoints_to_key(expansion_cps)

            expansion_elements =
              case Map.get(overlay, expansion_key) do
                nil -> lookup_elements(expansion_cps)
                elements -> elements
              end

            new_elements = compute_tailored_elements(expansion_elements, level)
            key = Parser.codepoints_to_key(target_cps)
            new_overlay = Map.put(overlay, key, new_elements)
            {new_overlay, {:after, new_elements}}

          {level, cps} when level in [:primary, :secondary, :tertiary] ->
            case state do
              {:after, anchor_elements} ->
                new_elements = compute_tailored_elements(anchor_elements, level)
                key = Parser.codepoints_to_key(cps)
                new_overlay = Map.put(overlay, key, new_elements)
                {new_overlay, {:after, new_elements}}

              nil ->
                {overlay, state}
            end

          _ ->
            {overlay, state}
        end
      end)

    overlay
  end

  defp lookup_elements(cps) do
    case Table.lookup(cps) do
      {:ok, elements} ->
        elements

      :unmapped ->
        Enum.flat_map(cps, fn cp ->
          case Table.lookup(cp) do
            {:ok, elems} -> elems
            :unmapped -> [Element.new(0, 0x0020, 0x0002)]
          end
        end)
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
end
