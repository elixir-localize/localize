defmodule Localize.Data.Collation do
  @moduledoc """
  Generates collation tailoring ETF data from CLDR collation XML files.

  Parses all collation XML files from the CLDR repository, extracts
  tailoring rule strings, resolves `[import]` directives, and returns
  a map keyed by `{language, type}` tuples.

  """

  import SweetXml

  # Types to skip — private and searchjl are internal only
  @skip_types MapSet.new(["private", "searchjl"])

  # BCP47 collation type abbreviations to CLDR XML type names
  @bcp47_to_cldr_type %{
    "phonebk" => "phonebook",
    "trad" => "traditional",
    "dict" => "dictionary",
    "ducet" => "ducet"
  }

  @doc """
  Generates collation tailoring data from CLDR XML collation files.

  Reads XML files from `../cldr_repo/common/collation/`, parses
  tailoring rules, resolves import directives, and returns a map
  of `{language_string, type_atom}` tuples to rule strings.

  """
  def generate_collation_tailoring do
    collation_dir = collation_source_dir()

    unless File.dir?(collation_dir) do
      raise "Collation directory not found: #{collation_dir}"
    end

    xml_files =
      collation_dir
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".xml"))
      |> Enum.sort()

    # Phase 1: Parse all collation files into raw entries
    all_raw =
      Enum.flat_map(xml_files, fn filename ->
        entries = parse_collation_file(collation_dir, filename)

        if filename == "root.xml" do
          entries
          |> Enum.filter(fn {_lang, type, _rules} -> type == :search end)
          |> Enum.map(fn {"root", type, rules} -> {"und", type, rules} end)
        else
          entries
        end
      end)

    raw_map =
      all_raw
      |> Enum.map(fn {language, type, rules} -> {{language, type}, rules} end)
      |> Map.new()

    # Phase 2: Resolve [import] directives
    raw_map
    |> Enum.map(fn {{language, type}, rules} ->
      resolved =
        if String.contains?(rules, "[import") do
          resolve_imports(rules, raw_map)
        else
          rules
        end

      {{language, type}, resolved}
    end)
    |> Enum.reject(fn {{_language, _type}, rules} ->
      not has_ordering_rules?(rules) or rules == ""
    end)
    |> Map.new()
  end

  # ── Private helpers ─────────────────────────────────────────────

  defp collation_source_dir do
    Path.join(Localize.Data.cldr_repo_dir(), "common/collation")
  end

  defp parse_collation_file(collation_dir, filename) do
    path = Path.join(collation_dir, filename)
    xml = File.read!(path)
    xml = Regex.replace(~r/<!DOCTYPE[^>]*>/, xml, "")

    language =
      filename
      |> String.replace(".xml", "")
      |> String.replace("_", "-")

    doc = SweetXml.parse(xml)

    doc
    |> xpath(~x"//collation"l,
      type: ~x"./@type"s,
      cr: ~x"./cr/text()"s
    )
    |> Enum.flat_map(fn %{type: type, cr: cr} ->
      if MapSet.member?(@skip_types, type) or cr == "" do
        []
      else
        rules = clean_rules(cr)

        if has_ordering_rules?(rules) and rules != "" do
          [{language, String.to_atom(type), rules}]
        else
          []
        end
      end
    end)
  rescue
    e ->
      IO.puts(:stderr, "Warning: Could not parse #{filename}: #{Exception.message(e)}")
      []
  end

  defp clean_rules(cdata) do
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
    |> decode_escapes()
  end

  defp decode_escapes(string) do
    Regex.replace(~r/\\u([0-9A-Fa-f]{4})/, string, fn _full, hex ->
      <<String.to_integer(hex, 16)::utf8>>
    end)
  end

  defp has_ordering_rules?(rules) do
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

  defp resolve_imports(rules, raw_map) do
    rules
    |> String.split("\n")
    |> Enum.flat_map(fn line ->
      case Regex.run(~r/^\[import\s+(.+)\]$/, line) do
        [_, tag] ->
          case parse_import_tag(tag) do
            {lang, type} ->
              case Map.get(raw_map, {lang, type}) do
                nil -> []
                imported_rules ->
                  imported_rules
                  |> String.split("\n")
                  |> Enum.reject(&String.starts_with?(&1, "[import"))
              end

            nil ->
              []
          end

        nil ->
          [line]
      end
    end)
    |> Enum.join("\n")
    |> String.trim()
  end

  defp parse_import_tag(tag) do
    case Regex.run(~r/^([a-zA-Z_-]+)-u-co-(.+)$/, tag) do
      [_, lang, type] ->
        lang = String.replace(lang, "_", "-")
        type = Map.get(@bcp47_to_cldr_type, type, type)
        {lang, String.to_atom(type)}

      nil ->
        if Regex.match?(~r/^[a-zA-Z_-]+$/, tag) do
          lang = String.replace(tag, "_", "-")
          {lang, :standard}
        else
          nil
        end
    end
  end
end
