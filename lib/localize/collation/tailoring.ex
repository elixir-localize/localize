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

  @tailorings %{
    {"da", :standard} =>
      "[caseFirst upper]\n&D<<đ<<<Đ<<ð<<<Ð\n&Y<<ü<<<Ü<<ű<<<Ű\n&[before 1]ǀ<æ<<<Æ<<ä<<<Ä<ø<<<Ø<<ö<<<Ö<<ő<<<Ő<å<<<Å<<<aa<<<Aa<<<AA",
    {"de", :phonebook} => "&AE<<ä<<<Ä\n&OE<<ö<<<Ö\n&UE<<ü<<<Ü",
    {"es", :standard} => "&N<ñ<<<Ñ",
    {"es", :traditional} => "&N<ñ<<<Ñ\n&C<ch<<<Ch<<<CH\n&l<ll<<<Ll<<<LL",
    {"sv", :standard} =>
      "&D<<đ<<<Đ<<ð<<<Ð\n&Y<<ü<<<Ü<<ű<<<Ű\n&[before 1]ǀ<å<<<Å<ä<<<Ä<<æ<<<Æ<<ę<<<Ę<ö<<<Ö<<ø<<<Ø<<ő<<<Ő<<œ<<<Œ<<ô<<<Ô",
    {"fi", :standard} =>
      "&D<<đ<<<Đ<<ð<<<Ð\n&Y<<ü<<<Ü<<ű<<<Ű\n&[before 1]ǀ<å<<<Å<ä<<<Ä<<æ<<<Æ<<ę<<<Ę<ö<<<Ö<<ø<<<Ø<<ő<<<Ő<<œ<<<Œ<<ô<<<Ô",
    {"nb", :standard} =>
      "[caseFirst upper]\n&D<<đ<<<Đ<<ð<<<Ð\n&Y<<ü<<<Ü<<ű<<<Ű\n&[before 1]ǀ<æ<<<Æ<<ä<<<Ä<ø<<<Ø<<ö<<<Ö<<ő<<<Ő<å<<<Å<<<aa<<<Aa<<<AA",
    {"nn", :standard} =>
      "[caseFirst upper]\n&D<<đ<<<Đ<<ð<<<Ð\n&Y<<ü<<<Ü<<ű<<<Ű\n&[before 1]ǀ<æ<<<Æ<<ä<<<Ä<ø<<<Ø<<ö<<<Ö<<ő<<<Ő<å<<<Å<<<aa<<<Aa<<<AA",
    {"pl", :standard} =>
      "&A<ą<<<Ą\n&C<ć<<<Ć\n&E<ę<<<Ę\n&L<ł<<<Ł\n&N<ń<<<Ń\n&O<ó<<<Ó\n&S<ś<<<Ś\n&Z<ź<<<Ź<ż<<<Ż",
    {"hr", :standard} =>
      "&C<č<<<Č<ć<<<Ć\n&D<dž<<<Dž<<<DŽ<đ<<<Đ\n&L<lj<<<Lj<<<LJ\n&N<nj<<<Nj<<<NJ\n&S<š<<<Š\n&Z<ž<<<Ž",
    {"tr", :standard} => "&C<ç<<<Ç\n&G<ğ<<<Ğ\n&H<ı<<<I\n&O<ö<<<Ö\n&S<ş<<<Ş\n&U<ü<<<Ü"
  }

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
      String.starts_with?(line, "[caseFirst ") ->
        value = line |> String.trim_leading("[caseFirst ") |> String.trim_trailing("]")

        case value do
          "upper" -> [{:option, :case_first, :upper}]
          "lower" -> [{:option, :case_first, :lower}]
          "off" -> [{:option, :case_first, false}]
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

      String.starts_with?(line, "&") ->
        parse_reset_and_rules(String.trim_leading(line, "&"))

      true ->
        []
    end
  end

  defp parse_reset_and_rules(str) do
    {reset_op, after_reset} =
      case Regex.run(~r/^\[before (\d)\](.+)$/, str) do
        [_, level_str, remainder] ->
          level = String.to_integer(level_str)
          {first_char, rest} = split_first_char_sequence(remainder)
          {{:reset_before, level, first_char}, rest}

        nil ->
          {first_char, rest} = split_first_char_sequence(str)
          {{:reset, first_char}, rest}
      end

    ordering_ops = parse_ordering_rules(after_reset)
    [reset_op | ordering_ops]
  end

  defp split_first_char_sequence(str) do
    case Regex.run(~r/^(.+?)(<<<|<<|<)(.*)$/, str) do
      [_, chars, op, rest] ->
        cps = string_to_codepoints(chars)
        {cps, op <> rest}

      nil ->
        cps = string_to_codepoints(str)
        {cps, ""}
    end
  end

  defp parse_ordering_rules(""), do: []

  defp parse_ordering_rules(str) do
    case Regex.run(~r/^(<<<|<<|<)(.+?)(?=(<<<|<<|<)|$)/, str) do
      [full, op, chars | _] ->
        level =
          case op do
            "<<<" -> :tertiary
            "<<" -> :secondary
            "<" -> :primary
          end

        cps = string_to_codepoints(chars)
        rest = String.trim_leading(str, full)
        [{level, cps} | parse_ordering_rules(rest)]

      nil ->
        []
    end
  end

  defp string_to_codepoints(str) do
    str
    |> String.trim()
    |> String.to_charlist()
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
