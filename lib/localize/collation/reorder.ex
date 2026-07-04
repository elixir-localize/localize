defmodule Localize.Collation.Reorder do
  # Script reordering for collation (kr= / reorder option).
  #
  # Remaps primary weights to change the relative order of scripts.
  # For example, `reorder: [:Grek, :Latn]` would sort Greek characters
  # before Latin characters.
  #
  @moduledoc false

  import Bitwise

  @doc """
  Build a reorder mapping function from the given script codes.

  ### Arguments

  * `reorder_codes` - a list of script code atoms (e.g., `[:Grek, :Latn]`).

  ### Returns

  * A function `(primary :: integer()) -> integer()` that remaps primary weights.

  * `nil` if the list is empty or no valid mappings were found.

  """
  @spec build_mapping([atom()]) :: (non_neg_integer() -> non_neg_integer()) | nil
  def build_mapping([]), do: nil

  def build_mapping(reorder_codes) do
    script_ranges = load_script_ranges()
    lead_byte_remap = build_lead_byte_permutation(reorder_codes, script_ranges)

    if lead_byte_remap == nil do
      nil
    else
      primary_to_frac_lead = load_primary_to_fractional_lead()

      fn primary -> remap_primary(primary, primary_to_frac_lead, lead_byte_remap) end
    end
  end

  defp remap_primary(0, _frac_map, _lead_byte_remap), do: 0

  defp remap_primary(primary, frac_map, lead_byte_remap) do
    case Map.get(frac_map, primary) do
      nil ->
        # Tailored weight — find the nearest base weight and
        # preserve the offset so relative ordering is maintained.
        base = find_nearest_base(primary, frac_map)
        remap_tailored_primary(base, primary, frac_map, lead_byte_remap)

      frac_lead ->
        remap_base_primary(Map.get(lead_byte_remap, frac_lead), primary, frac_map)
    end
  end

  defp remap_tailored_primary(nil, primary, _frac_map, _lead_byte_remap), do: primary

  defp remap_tailored_primary({base_primary, frac_lead}, primary, frac_map, lead_byte_remap) do
    case Map.get(lead_byte_remap, frac_lead) do
      nil ->
        primary

      new_lead ->
        offset = primary - base_primary
        base_sub = Map.get(frac_map, {:sub, base_primary}, 0)
        (new_lead <<< 8 ||| base_sub) + offset
    end
  end

  defp remap_base_primary(nil, primary, _frac_map), do: primary

  defp remap_base_primary(new_lead, primary, frac_map) do
    frac_sub = Map.get(frac_map, {:sub, primary}, 0)
    new_lead <<< 8 ||| frac_sub
  end

  defp build_lead_byte_permutation(reorder_codes, script_ranges) do
    {ordered_ranges, remaining} =
      Enum.reduce(reorder_codes, {[], script_ranges}, &collect_reorder_code/2)

    ordered_ranges = Enum.reverse(ordered_ranges)

    core_codes = ["space", "punctuation", "symbol", "currency", "digit"]

    missing_core =
      Enum.filter(core_codes, fn c ->
        not Enum.any?(reorder_codes, &(normalize_code(&1) == c))
      end)

    core_entries =
      missing_core
      |> Enum.flat_map(fn c ->
        case Map.get(script_ranges, c) do
          nil -> []
          range -> [{c, range}]
        end
      end)
      |> dedup_by_range()

    # All scripts not explicitly mentioned, in their default order.
    # Per TR35 these splice in at the position of the :others code,
    # or append after the mentioned scripts when :others is absent.
    others_entries =
      remaining
      |> Map.drop(core_codes)
      |> Enum.sort_by(fn {_k, {start, _end}} -> start end)
      |> dedup_by_range()

    ordered_with_others =
      if :others in ordered_ranges do
        Enum.flat_map(ordered_ranges, fn
          :others -> others_entries
          entry -> [entry]
        end)
      else
        ordered_ranges ++ others_entries
      end

    all_entries =
      (core_entries ++ ordered_with_others)
      |> dedup_by_range()

    build_lead_byte_remap(all_entries)
  end

  defp collect_reorder_code(code, {ordered, remaining}) when code in [:others, :Zzzz] do
    {[:others | ordered], remaining}
  end

  defp collect_reorder_code(code, {ordered, remaining}) do
    case Map.pop(remaining, normalize_code(code)) do
      {nil, remaining} ->
        {ordered, remaining}

      {range, remaining} ->
        {[{normalize_code(code), range} | ordered], remaining}
    end
  end

  defp dedup_by_range(entries) do
    {deduped, _seen} =
      Enum.reduce(entries, {[], MapSet.new()}, fn {name, range}, {acc, seen} ->
        if MapSet.member?(seen, range) do
          {acc, seen}
        else
          {[{name, range} | acc], MapSet.put(seen, range)}
        end
      end)

    Enum.reverse(deduped)
  end

  defp build_lead_byte_remap(entries) do
    {remap, _next} =
      Enum.reduce(entries, {%{}, 0x03}, fn {_code, {range_start, range_end}}, {remap, next} ->
        count = range_end - range_start + 1

        new_mappings =
          Enum.zip(range_start..range_end, next..(next + count - 1))
          |> Map.new()

        {Map.merge(remap, new_mappings), next + count}
      end)

    if map_size(remap) == 0 do
      nil
    else
      remap
    end
  end

  @doc """
  Load a mapping from allkeys integer primary weights to their
  fractional lead bytes and sub-bytes.

  ### Returns

  A map `%{integer() | {:sub, integer()} => non_neg_integer()}`.

  """
  @spec load_primary_to_fractional_lead() :: %{
          (integer() | {:sub, integer()}) => non_neg_integer()
        }
  def load_primary_to_fractional_lead do
    Localize.Collation.Table.ensure_loaded()
    :persistent_term.get({:localize, :collation_primary_to_frac}, %{})
  end

  @doc false
  def parse_primary_to_frac(path) do
    path
    |> File.stream!()
    |> Enum.reduce(%{}, fn line, acc ->
      line = String.trim(line)

      cond do
        line == "" or String.starts_with?(line, "#") or
          String.starts_with?(line, "[") or String.starts_with?(line, "FDD") ->
          acc

        String.contains?(line, ";") ->
          parse_frac_line_for_lead(line, acc)

        true ->
          acc
      end
    end)
  end

  defp parse_frac_line_for_lead(line, acc) do
    with [_cp_part, rest] <- String.split(line, ";", parts: 2),
         [_, frac_hex] <- Regex.run(~r/\[([0-9A-Fa-f ]+),/, rest),
         [_, allkeys_hex] <- Regex.run(~r/\[([0-9A-Fa-f]+)\.[0-9A-Fa-f]+\.[0-9A-Fa-f]+\]/, rest) do
      frac_bytes =
        frac_hex
        |> String.trim()
        |> String.split()
        |> Enum.map(&String.to_integer(&1, 16))

      frac_lead = hd(frac_bytes)
      frac_sub = if length(frac_bytes) > 1, do: Enum.at(frac_bytes, 1), else: 0
      allkeys_primary = String.to_integer(allkeys_hex, 16)

      if allkeys_primary > 0 do
        acc
        |> Map.put_new(allkeys_primary, frac_lead)
        |> Map.put_new({:sub, allkeys_primary}, frac_sub)
      else
        acc
      end
    else
      _ -> acc
    end
  end

  defp normalize_code(code) when is_atom(code) do
    normalize_code(Atom.to_string(code))
  end

  defp normalize_code(code) when is_binary(code) do
    code
    |> String.downcase()
    |> case do
      "punct" -> "punctuation"
      other -> other
    end
  end

  @doc """
  Load the script-to-lead-byte-range mapping from FractionalUCA.txt.

  ### Returns

  A map `%{String.t() => {start_byte, end_byte}}`.

  """
  @spec load_script_ranges() :: %{String.t() => {non_neg_integer(), non_neg_integer()}}
  def load_script_ranges do
    Localize.Collation.Table.ensure_loaded()

    case :persistent_term.get({:localize, :collation_script_ranges}, nil) do
      nil -> default_script_ranges()
      ranges -> ranges
    end
  end

  @non_reorderable_groups MapSet.new([
                            "terminator",
                            "level-separator",
                            "field-separator",
                            "compress",
                            "implicit",
                            "trailing",
                            "special",
                            "reorder_reserved_before_latin",
                            "reorder_reserved_after_latin"
                          ])

  @doc false
  def parse_top_bytes(path) do
    path
    |> File.stream!()
    |> Enum.reduce(%{}, fn line, acc ->
      case Regex.run(~r/^\[top_byte\s+([0-9A-Fa-f]+)\s+(.+?)\s*\]/, line) do
        [_, hex, group_name] ->
          add_top_byte_groups(acc, String.to_integer(hex, 16), group_name)

        _ ->
          acc
      end
    end)
  end

  defp add_top_byte_groups(acc, byte, group_name) do
    group_name
    |> String.downcase()
    |> String.split()
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&MapSet.member?(@non_reorderable_groups, &1))
    |> Enum.reduce(acc, fn group, inner_acc ->
      case Map.get(inner_acc, group) do
        nil -> Map.put(inner_acc, group, {byte, byte})
        {start, _end} -> Map.put(inner_acc, group, {start, byte})
      end
    end)
  end

  defp default_script_ranges do
    %{
      "space" => {0x03, 0x0B},
      "punctuation" => {0x03, 0x0B},
      "symbol" => {0x0C, 0x0E},
      "currency" => {0x0C, 0x0E},
      "digit" => {0x0F, 0x27},
      "latn" => {0x2A, 0x5E},
      "grek" => {0x61, 0x61},
      "cyrl" => {0x62, 0x62},
      "hani" => {0x81, 0xDF},
      "hang" => {0x7C, 0x7C}
    }
  end

  @doc """
  Apply a reorder mapping to a primary weight.

  ### Arguments

  * `mapping_fn` - a reorder mapping function from `build_mapping/1`, or `nil`.

  * `primary` - the primary weight to remap.

  ### Returns

  The remapped primary weight, or the original if `mapping_fn` is `nil`.

  """
  @spec apply_mapping((non_neg_integer() -> non_neg_integer()) | nil, non_neg_integer()) ::
          non_neg_integer()
  def apply_mapping(nil, primary), do: primary
  def apply_mapping(mapping_fn, primary), do: mapping_fn.(primary)

  # Find the nearest base weight (one that has a fractional lead
  # byte mapping) by searching downward from the tailored weight.
  # Returns `{base_primary, frac_lead}` or `nil`.
  defp find_nearest_base(primary, frac_map) do
    find_nearest_base(primary - 1, frac_map, 32)
  end

  defp find_nearest_base(_primary, _frac_map, 0), do: nil

  defp find_nearest_base(primary, frac_map, remaining) when primary > 0 do
    case Map.get(frac_map, primary) do
      nil -> find_nearest_base(primary - 1, frac_map, remaining - 1)
      lead -> {primary, lead}
    end
  end

  defp find_nearest_base(_primary, _frac_map, _remaining), do: nil
end
