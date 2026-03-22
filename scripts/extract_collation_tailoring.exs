# Script: Extract CLDR collation tailoring rules from XML
#
# Parses collation XML files from the CLDR repository and extracts
# tailoring rule strings for each language/type combination.
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
# The ETF file contains a map of {language, type} tuples to
# tailoring rule strings. Only "standard" and named collation
# types are included. Types marked as "search" or "private" are
# excluded. Files with only [import], [reorder], or [strength]
# directives (no actual ordering rules) are excluded.

cldr_repo =
  case System.argv() do
    [path | _] -> path
    [] -> Path.expand("../cldr_repo", __DIR__)
  end

collation_dir = Path.join(cldr_repo, "common/collation")
output_path = Path.join([__DIR__, "..", "priv", "cldr", "supplemental_data", "collation_tailoring.etf"]) |> Path.expand()

unless File.dir?(collation_dir) do
  IO.puts(:stderr, "Error: #{collation_dir} not found")
  System.halt(1)
end

IO.puts("Parsing collation files from #{collation_dir}...")

# Skip the root file (it's the base DUCET, not a tailoring)
xml_files =
  collation_dir
  |> File.ls!()
  |> Enum.filter(&String.ends_with?(&1, ".xml"))
  |> Enum.reject(&(&1 == "root.xml"))
  |> Enum.sort()

# Parse a single collation XML file and extract {language, type} => rules
parse_file = fn filename ->
  path = Path.join(collation_dir, filename)
  content = File.read!(path)

  # Extract language from filename (e.g., "cs.xml" -> "cs", "bs_Cyrl.xml" -> "bs_Cyrl")
  language = String.replace(filename, ".xml", "")
  # Normalize: bs_Cyrl -> bs-Cyrl for BCP47 compatibility
  language = String.replace(language, "_", "-")

  # Find all <collation type="..."> sections with <cr><![CDATA[...]]></cr>
  regex = ~r/<collation\s+type="([^"]+)"[^>]*>.*?<cr><!\[CDATA\[(.*?)\]\]><\/cr>/s

  Regex.scan(regex, content)
  |> Enum.flat_map(fn [_full, type, cdata] ->
    # Skip search and private types
    if type in ["search", "private", "searchjl"] do
      []
    else
      # Clean up the CDATA content
      rules =
        cdata
        |> String.split("\n")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(fn line ->
          line == "" or
            String.starts_with?(line, "#") or
            String.starts_with?(line, "[import") or
            String.starts_with?(line, "[reorder")
        end)
        |> Enum.join("\n")
        |> String.trim()
        # Decode \uXXXX escape sequences to actual Unicode characters
        |> then(fn s ->
          Regex.replace(~r/\\u([0-9A-Fa-f]{4})/, s, fn _full, hex ->
            <<String.to_integer(hex, 16)::utf8>>
          end)
        end)

      # Check if there are actual ordering rules (not just directives)
      has_ordering_rules =
        rules
        |> String.split("\n")
        |> Enum.any?(fn line ->
          String.starts_with?(line, "&") or
            (String.starts_with?(line, "[") and
               not String.starts_with?(line, "[reorder") and
               not String.starts_with?(line, "[strength") and
               not String.starts_with?(line, "[normalization") and
               not String.starts_with?(line, "[suppressContractions") and
               not String.starts_with?(line, "[optimize"))
        end)

      if has_ordering_rules and rules != "" do
        type_atom = String.to_atom(type)
        [{language, type_atom, rules}]
      else
        []
      end
    end
  end)
end

# Parse all files
all_tailorings =
  xml_files
  |> Enum.flat_map(fn filename ->
    try do
      parse_file.(filename)
    rescue
      e ->
        IO.puts(:stderr, "Warning: Could not parse #{filename}: #{inspect(e)}")
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
languages = tailoring_map |> Map.keys() |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> Enum.sort()
IO.puts("Languages with tailoring (#{length(languages)}):")

for lang <- languages do
  types = tailoring_map |> Map.keys() |> Enum.filter(&(elem(&1, 0) == lang)) |> Enum.map(&elem(&1, 1))
  IO.puts("  #{lang}: #{inspect(types)}")
end
