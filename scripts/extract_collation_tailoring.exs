# Script: Extract CLDR collation tailoring rules from XML
#
# Parses collation XML files from the CLDR repository using SweetXml
# and extracts tailoring rule strings for each language/type combination.
# Outputs an ETF file for runtime loading.
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

# Types to skip — search collations and private types are not tailorings
skip_types = MapSet.new(["search", "private", "searchjl"])

# Lines to strip from CDATA content
strip_line? = fn line ->
  line == "" or
    String.starts_with?(line, "#") or
    String.starts_with?(line, "[import") or
    String.starts_with?(line, "[optimize") or
    String.starts_with?(line, "[suppressContractions")
end

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
      String.starts_with?(line, "[strength")
  end)
end

# Clean CDATA content into a rule string
clean_rules = fn cdata ->
  cdata
  |> String.split("\n")
  |> Enum.map(&String.trim/1)
  |> Enum.reject(strip_line?)
  |> Enum.join("\n")
  |> String.trim()
  |> decode_escapes.()
end

# Parse a single XML file
parse_file = fn filename ->
  path = Path.join(collation_dir, filename)
  xml = File.read!(path)
  # Remove DOCTYPE to avoid DTD resolution
  xml = Regex.replace(~r/<!DOCTYPE[^>]*>/, xml, "")

  language =
    filename
    |> String.replace(".xml", "")
    |> String.replace("_", "-")

  doc = SweetXml.parse(xml)

  # Extract all collation elements with their type and cr content
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

# Skip root.xml (base DUCET, not a tailoring)
xml_files =
  collation_dir
  |> File.ls!()
  |> Enum.filter(&String.ends_with?(&1, ".xml"))
  |> Enum.reject(&(&1 == "root.xml"))
  |> Enum.sort()

# Parse all files
all_tailorings =
  xml_files
  |> Enum.flat_map(fn filename ->
    try do
      parse_file.(filename)
    rescue
      e ->
        IO.puts(:stderr, "Warning: Could not parse #{filename}: #{Exception.message(e)}")
        []
    end
  end)

# Build the map
tailoring_map =
  all_tailorings
  |> Enum.map(fn {language, type, rules} ->
    {{language, type}, rules}
  end)
  |> Map.new()

# Write ETF
File.write!(output_path, :erlang.term_to_binary(tailoring_map))

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

  IO.puts("  #{lang}: #{inspect(types)}")
end
