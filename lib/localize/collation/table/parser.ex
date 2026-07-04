defmodule Localize.Collation.Table.Parser do
  # Parses the FractionalUCA.txt file into a map of codepoint sequences to collation elements.
  #
  # FractionalUCA.txt is the single source of truth for the collation table. Each data line
  # contains both fractional weights (used for script reordering) and allkeys-format decimal
  # weights (used for collation element construction) in the comment:
  #
  # * Single codepoint: `0041; [2B, 05, 9C]  # Latn Lu  [23EC.0020.0008]  * LATIN CAPITAL LETTER A`.
  #
  # * Multi-CE: `00E9; [2B 86, 05, 05]  # Latn Ll  [2453.0020.0002][0000.0024.0002]  * LATIN SMALL LETTER E WITH ACUTE`.
  #
  # * Context entry: `004C | 00B7; [, FB B6, 05]  # Zyyy Po  [0000.011F.0002]  * MIDDLE DOT`.
  #
  # Context entries represent CLDR-specific contractions where a target codepoint's weights
  # change depending on the preceding context codepoint. These are converted to explicit
  # contraction entries (e.g., `{0x004C, 0x00B7} => L's CEs ++ modified CEs`).
  #
  # Variable status (spaces, punctuation, symbols, currency) is derived from the
  # `[first variable]` and `[last variable]` header lines rather than per-entry
  # markers. Those lines carry fractional byte weights, e.g.
  # `[first variable [03 04, 05, 05]]` / `[last variable [0B 8E 64, 05, 05]]`,
  # so the parser extracts the fractional primary lead bytes (0x03 and 0x0B for
  # the vendored file) and maps them back into allkeys primary space using the
  # per-entry fractional-lead-to-allkeys-primary pairs collected while parsing.
  #
  @moduledoc false

  alias Localize.Collation.Element

  # Fractional primary lead bytes of the variable section, used when the
  # header lines are absent. These match the vendored FractionalUCA.txt
  # (`[first variable [03 04, ...]]` and `[last variable [0B 8E 64, ...]]`).
  @default_first_variable_lead 0x03
  @default_last_variable_lead 0x0B

  # Allkeys-space fallback when no entry carries fractional lead data
  # (0x0201 is U+0009 TAB, the first variable; 0x04E0 is U+1E5FF, the last).
  @default_variable_primary_range {0x0201, 0x04E0}

  @doc """
  Parse FractionalUCA.txt into a collation table.

  This is the primary parser that builds the complete collation table from
  a single data file. Variable status is derived from the `[last variable]`
  header line.

  ### Arguments

  * `path` - file path to the FractionalUCA.txt data file.

  ### Returns

  A map with two keys:

  * `:entries` - `%{integer() | tuple() => [Element.t()]}` mapping codepoints
    (integers for single, tuples for contractions) to collation elements.

  * `:version` - the UCA version string from the file header, or `nil`.

  """
  def parse(path) do
    acc =
      path
      |> File.stream!()
      |> Enum.reduce(
        %{
          entries: %{},
          contexts: [],
          version: nil,
          first_variable_lead: @default_first_variable_lead,
          last_variable_lead: @default_last_variable_lead,
          lead_primaries: %{}
        },
        fn line, acc ->
          parse_line(String.trim(line), acc)
        end
      )

    variable_range = variable_primary_range(acc)
    entries = apply_variable_flags(acc.entries, variable_range)
    entries = resolve_context_entries(acc.contexts, entries, variable_range)

    %{entries: entries, version: acc.version}
  end

  # FractionalUCA.txt line dispatch: one branch per directive or entry
  # line shape in the source file.
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp parse_line(line, acc) do
    cond do
      line == "" or String.starts_with?(line, "#") ->
        acc

      String.starts_with?(line, "[UCA version") ->
        case Regex.run(~r/\[UCA version = (.+)\]/, line) do
          [_, version] -> %{acc | version: String.trim(version)}
          _ -> acc
        end

      String.starts_with?(line, "[first variable") ->
        case parse_variable_boundary(line) do
          {:ok, lead} -> %{acc | first_variable_lead: lead}
          :skip -> acc
        end

      String.starts_with?(line, "[last variable") ->
        case parse_variable_boundary(line) do
          {:ok, lead} -> %{acc | last_variable_lead: lead}
          :skip -> acc
        end

      String.starts_with?(line, "[") ->
        acc

      String.starts_with?(line, "FDD") ->
        acc

      String.contains?(line, ";") ->
        case parse_fractional_entry(line) do
          {:ok, codepoints, elements} when elements != [] ->
            key = codepoints_to_key(codepoints)
            acc = track_lead_primary(acc, line)
            %{acc | entries: Map.put(acc.entries, key, elements)}

          {:context, context_cp, target_cp, elements} ->
            %{acc | contexts: [{context_cp, target_cp, elements} | acc.contexts]}

          _ ->
            acc
        end

      true ->
        acc
    end
  end

  @doc """
  Parse a single FractionalUCA.txt data entry.

  ### Arguments

  * `line` - a single data line from FractionalUCA.txt.

  ### Returns

  * `{:ok, codepoints, elements}` - the parsed codepoint list and collation elements.

  * `{:context, context_cp, target_cp, elements}` - a context entry to be resolved later.

  * `:skip` - the line could not be parsed.

  """
  def parse_fractional_entry(line) do
    case String.split(line, ";", parts: 2) do
      [cp_part, rest] ->
        parse_entry_body(String.trim(cp_part), rest)

      _ ->
        :skip
    end
  end

  defp parse_entry_body(cp_str, rest) do
    if String.contains?(cp_str, "|") do
      parse_context_entry(cp_str, rest)
    else
      codepoints = parse_codepoints(cp_str)

      case extract_allkeys_weights(rest) do
        elements when elements != [] ->
          {:ok, codepoints, elements}

        _ ->
          :skip
      end
    end
  end

  @doc """
  Convert a codepoint list to a table key.

  Single codepoints become bare integers, multi-codepoint sequences (contractions)
  become tuples for compact persistent_term storage.

  ### Arguments

  * `codepoints` - a list of integer codepoints.

  ### Returns

  An integer for single codepoints, or a tuple for contractions.

  ### Examples

      iex> Localize.Collation.Table.Parser.codepoints_to_key([0x0041])
      0x0041

      iex> Localize.Collation.Table.Parser.codepoints_to_key([0x006C, 0x00B7])
      {0x006C, 0x00B7}

  """
  def codepoints_to_key([cp]), do: cp
  def codepoints_to_key(cps) when is_list(cps), do: List.to_tuple(cps)

  @doc """
  Parse weight elements from an allkeys weight string.

  ### Arguments

  * `str` - the weight portion of an allkeys line (e.g., `"[.23EC.0020.0008]"`).

  ### Returns

  A list of collation element tuples `{primary, secondary, tertiary, variable}`.

  ### Examples

      iex> Localize.Collation.Table.Parser.parse_elements("[.23EC.0020.0008]")
      [{0x23EC, 0x0020, 0x0008, false}]

      iex> Localize.Collation.Table.Parser.parse_elements("[*0269.0020.0002]")
      [{0x0269, 0x0020, 0x0002, true}]

  """
  def parse_elements(str) do
    ~r/\[([.*])([0-9A-Fa-f]{4})\.([0-9A-Fa-f]{4})\.([0-9A-Fa-f]{4})\]/
    |> Regex.scan(str)
    |> Enum.map(fn [_full, marker, p, s, t] ->
      Element.new(
        String.to_integer(p, 16),
        String.to_integer(s, 16),
        String.to_integer(t, 16),
        marker == "*"
      )
    end)
  end

  # Extracts the fractional primary lead byte from a variable boundary
  # header line, e.g. `[first variable [03 04, 05, 05]]` yields 0x03 and
  # `[last variable [0B 8E 64, 05, 05]]` yields 0x0B.
  defp parse_variable_boundary(line) do
    case Regex.run(~r/\[(?:first|last) variable\s+\[([0-9A-Fa-f]{2})[ ,\]]/, line) do
      [_, lead_hex] -> {:ok, String.to_integer(lead_hex, 16)}
      _ -> :skip
    end
  end

  # Records the pairing between an entry's fractional primary lead byte and
  # its allkeys primary weight, accumulating the min/max allkeys primaries
  # seen per lead byte. This lets the variable boundary lead bytes be mapped
  # back into allkeys primary space once the whole file has been read (the
  # boundary header lines appear after the data lines in FractionalUCA.txt).
  defp track_lead_primary(acc, line) do
    with [_cp_part, rest] <- String.split(line, ";", parts: 2),
         [_, frac_hex] <- Regex.run(~r/\[([0-9A-Fa-f][0-9A-Fa-f ]*),/, rest),
         [_, allkeys_hex] <-
           Regex.run(~r/\[([0-9A-Fa-f]{4})\.[0-9A-Fa-f]{4}\.[0-9A-Fa-f]{4}\]/, rest),
         primary = String.to_integer(allkeys_hex, 16),
         true <- primary > 0 do
      lead =
        frac_hex
        |> String.split()
        |> hd()
        |> String.to_integer(16)

      lead_primaries =
        Map.update(acc.lead_primaries, lead, {primary, primary}, fn {min_p, max_p} ->
          {min(min_p, primary), max(max_p, primary)}
        end)

      %{acc | lead_primaries: lead_primaries}
    else
      _ -> acc
    end
  end

  # Maps the variable boundary lead bytes into an allkeys `{min, max}` primary
  # range using the per-lead-byte primaries collected during parsing. Falls
  # back to the vendored file's known range when no lead data is available.
  defp variable_primary_range(acc) do
    bounds =
      acc.lead_primaries
      |> Enum.filter(fn {lead, _range} ->
        lead >= acc.first_variable_lead and lead <= acc.last_variable_lead
      end)
      |> Enum.reduce(nil, fn
        {_lead, {min_p, max_p}}, nil -> {min_p, max_p}
        {_lead, {min_p, max_p}}, {acc_min, acc_max} -> {min(acc_min, min_p), max(acc_max, max_p)}
      end)

    bounds || @default_variable_primary_range
  end

  defp parse_context_entry(cp_str, rest) do
    case String.split(cp_str, "|") do
      [context_str, target_str] ->
        [context_cp] = parse_codepoints(String.trim(context_str))
        [target_cp] = parse_codepoints(String.trim(target_str))

        case extract_allkeys_weights(rest) do
          elements when elements != [] ->
            {:context, context_cp, target_cp, elements}

          _ ->
            :skip
        end

      _ ->
        :skip
    end
  end

  defp extract_allkeys_weights(rest) do
    elements =
      case Regex.run(~r/#.*?(\[.+)$/, rest) do
        [_, weights_section] ->
          ~r/\[([0-9A-Fa-f]{4})\.([0-9A-Fa-f]{4})\.([0-9A-Fa-f]{4})\]/
          |> Regex.scan(weights_section)
          |> Enum.map(fn [_full, p, s, t] ->
            Element.new(
              String.to_integer(p, 16),
              String.to_integer(s, 16),
              String.to_integer(t, 16)
            )
          end)

        nil ->
          []
      end

    if elements != [] do
      elements
    else
      parse_fractional_as_allkeys(rest)
    end
  end

  defp parse_fractional_as_allkeys(rest) do
    weight_part =
      case String.split(rest, "#", parts: 2) do
        [w, _] -> String.trim(w)
        [w] -> String.trim(w)
      end

    cond do
      String.contains?(weight_part, "[02, 05, 05]") ->
        [Element.new(0x0001, 0x0020, 0x0002)]

      String.contains?(weight_part, "[EF FF, 05, 05]") ->
        [Element.new(0xFFFE, 0x0020, 0x0002)]

      true ->
        []
    end
  end

  defp apply_variable_flags(entries, variable_range) do
    Map.new(entries, fn {key, elements} ->
      {key, flag_variable_elements(elements, variable_range)}
    end)
  end

  defp resolve_context_entries(contexts, entries, variable_range) do
    Enum.reduce(contexts, entries, fn {context_cp, target_cp, modified_elements}, acc ->
      case Map.get(acc, context_cp) do
        nil ->
          acc

        context_elements ->
          flagged = flag_variable_elements(modified_elements, variable_range)
          contraction_key = {context_cp, target_cp}
          contraction_elements = context_elements ++ flagged
          Map.put(acc, contraction_key, contraction_elements)
      end
    end)
  end

  defp flag_variable_elements(elements, {first_variable, last_variable}) do
    Enum.map(elements, fn {p, s, t, _v} ->
      variable = p >= first_variable and p <= last_variable
      {p, s, t, variable}
    end)
  end

  defp parse_codepoints(str) do
    str
    |> String.split()
    |> Enum.map(&String.to_integer(&1, 16))
  end
end
