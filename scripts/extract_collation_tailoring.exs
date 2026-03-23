# Script: Extract CLDR collation tailoring rules from XML
#
# Parses collation XML files from the CLDR repository using SweetXml
# and extracts tailoring rule strings for each language/type combination.
# Outputs an ETF file for runtime loading.
#
# Search collation types are included. The [import] directives in
# search rules are resolved by inlining the referenced rules at
# extraction time so the ETF contains fully resolved rule sets.
#
# Usage:
#   mix run scripts/extract_collation_tailoring.exs [cldr_repo_path]
#
# Arguments:
#   cldr_repo_path - Path to the CLDR repository (default: ../cldr_repo)
#
# Output:
#   priv/cldr/supplemental_data/collation_tailoring.etf
#
# Requires sweet_xml as a dev dependency.

import SweetXml

cldr_repo =
  case System.argv() do
    [path | _] -> path
    [] -> Path.expand("../cldr_repo", __DIR__)
  end

collation_dir = Path.join(cldr_repo, "common/collation")

output_path =
  Path.join([__DIR__, "..", "priv", "cldr", "supplemental_data", "collation_tailoring.etf"])
  |> Path.expand()

unless File.dir?(collation_dir) do
  IO.puts(:stderr, "Error: #{collation_dir} not found")
  System.halt(1)
end

IO.puts("Parsing collation files from #{collation_dir}...")

# Types to skip — private and searchjl are internal only
skip_types = MapSet.new(["private", "searchjl"])

# Decode \uXXXX escape sequences to actual Unicode characters
decode_escapes = fn s ->
  Regex.replace(~r/\\u([0-9A-Fa-f]{4})/, s, fn _full, hex ->
    <<String.to_integer(hex, 16)::utf8>>
  end)
end

# Check if rules contain actual ordering operations (not just directives)
has_ordering_rules? = fn rules ->
  rules
  |> String.split("\n")
  |> Enum.any?(fn line ->
    String.starts_with?(line, "&") or
      String.starts_with?(line, "[caseFirst") or
      String.starts_with?(line, "[caseLevel") or
      String.starts_with?(line, "[alternate") or
      String.starts_with?(line, "[backwards") or
      String.starts_with?(line, "[normalization") or
      String.starts_with?(line, "[strength") or
      String.starts_with?(line, "[suppressContractions") or
      String.starts_with?(line, "[reorder") or
      String.starts_with?(line, "[import")
  end)
end

# Clean CDATA content — strip comments and empty lines, decode escapes.
# Does NOT strip [import] lines (those are resolved separately).
clean_rules = fn cdata ->
  cdata
  |> String.split("\n")
  |> Enum.map(&String.trim/1)
  |> Enum.reject(fn line ->
    line == "" or
      String.starts_with?(line, "#") or
      String.starts_with?(line, "[optimize")
  end)
  |> Enum.join("\n")
  |> String.trim()
  |> decode_escapes.()
end

# ── Phase 1: Parse all collation files into raw entries ────────

parse_file = fn filename ->
  path = Path.join(collation_dir, filename)
  xml = File.read!(path)
  xml = Regex.replace(~r/<!DOCTYPE[^>]*>/, xml, "")

  language =
    filename
    |> String.replace(".xml", "")
    |> String.replace("_", "-")

  doc = SweetXml.parse(xml)

  collations =
    doc
    |> SweetXml.xpath(~x"//collation"l,
      type: ~x"./@type"s,
      cr: ~x"./cr/text()"s
    )

  collations
  |> Enum.flat_map(fn %{type: type, cr: cr} ->
    if type in skip_types or cr == "" do
      []
    else
      rules = clean_rules.(cr)

      if has_ordering_rules?.(rules) and rules != "" do
        [{language, String.to_atom(type), rules}]
      else
        []
      end
    end
  end)
end

# Include root.xml for search rules (but not for standard — root
# standard is the base DUCET, not a tailoring)
xml_files =
  collation_dir
  |> File.ls!()
  |> Enum.filter(&String.ends_with?(&1, ".xml"))
  |> Enum.sort()

all_raw =
  xml_files
  |> Enum.flat_map(fn filename ->
    try do
      entries = parse_file.(filename)

      # For root.xml, only keep the search type (standard is DUCET base)
      if filename == "root.xml" do
        Enum.filter(entries, fn {_lang, type, _rules} -> type == :search end)
        |> Enum.map(fn {"root", type, rules} -> {"und", type, rules} end)
      else
        entries
      end
    rescue
      e ->
        IO.puts(:stderr, "Warning: Could not parse #{filename}: #{Exception.message(e)}")
        []
    end
  end)

# Build initial map (before import resolution)
raw_map =
  all_raw
  |> Enum.map(fn {language, type, rules} -> {{language, type}, rules} end)
  |> Map.new()

IO.puts("Parsed #{map_size(raw_map)} raw entries")

# ── Phase 2: Resolve [import] directives ───────────────────────

# Parse an import BCP47 tag like "und-u-co-search", "de-u-co-phonebk",
# or a short tag like "hr" (meaning standard collation for that locale)
parse_import_tag = fn tag ->
  # BCP47 collation type abbreviations to CLDR XML type names
  bcp47_to_cldr_type = %{
    "phonebk" => "phonebook",
    "trad" => "traditional",
    "dict" => "dictionary",
    "ducet" => "ducet"
  }

  case Regex.run(~r/^([a-zA-Z_-]+)-u-co-(.+)$/, tag) do
    [_, lang, type] ->
      lang = String.replace(lang, "_", "-")
      type = Map.get(bcp47_to_cldr_type, type, type)
      {lang, String.to_atom(type)}

    nil ->
      # Short tag like "hr" — means standard collation for that locale
      if Regex.match?(~r/^[a-zA-Z_-]+$/, tag) do
        lang = String.replace(tag, "_", "-")
        {lang, :standard}
      else
        nil
      end
  end
end

# Resolve [import] directives by inlining referenced rules.
# Returns the fully resolved rule string with imports replaced.
resolve_imports = fn rules, raw_map ->
  rules
  |> String.split("\n")
  |> Enum.flat_map(fn line ->
    case Regex.run(~r/^\[import\s+(.+)\]$/, line) do
      [_, tag] ->
        case parse_import_tag.(tag) do
          {lang, type} ->
            case Map.get(raw_map, {lang, type}) do
              nil ->
                IO.puts(:stderr, "  Warning: import #{tag} not found in extracted rules")
                []

              imported_rules ->
                # Strip [import] lines from the imported rules too
                # (avoid recursive imports — we only go one level deep)
                imported_rules
                |> String.split("\n")
                |> Enum.reject(&String.starts_with?(&1, "[import"))
                |> Enum.map(&(&1))
            end

          nil ->
            IO.puts(:stderr, "  Warning: could not parse import tag #{tag}")
            []
        end

      nil ->
        [line]
    end
  end)
  |> Enum.join("\n")
  |> String.trim()
end

# Resolve all entries that contain [import] directives
tailoring_map =
  raw_map
  |> Enum.map(fn {{language, type}, rules} ->
    resolved =
      if String.contains?(rules, "[import") do
        IO.puts("  Resolving imports for #{language}:#{type}")
        resolve_imports.(rules, raw_map)
      else
        rules
      end

    {{language, type}, resolved}
  end)
  |> Enum.reject(fn {{_language, _type}, rules} ->
    # After import resolution, remove entries with no actual rules
    not has_ordering_rules?.(rules) or rules == ""
  end)
  |> Map.new()

# ── Phase 3: Write output ─────────────────────────────────────

File.write!(output_path, :erlang.term_to_binary(tailoring_map))

IO.puts("")
IO.puts("Wrote #{map_size(tailoring_map)} tailoring entries to #{output_path}")
IO.puts("")

# Summary
languages =
  tailoring_map
  |> Map.keys()
  |> Enum.map(&elem(&1, 0))
  |> Enum.uniq()
  |> Enum.sort()

IO.puts("Languages with tailoring (#{length(languages)}):")

for lang <- languages do
  types =
    tailoring_map
    |> Map.keys()
    |> Enum.filter(&(elem(&1, 0) == lang))
    |> Enum.map(&elem(&1, 1))
    |> Enum.sort()

  IO.puts("  #{lang}: #{inspect(types)}")
end
