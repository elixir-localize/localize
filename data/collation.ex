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

  @doc """
  Pre-generates the UCA collation table from FractionalUCA.txt and
  writes it as a compressed ETF file to `priv/localize/collation_table.etf`.

  The ETF contains all data needed at runtime:

  * `:entries` — the full codepoint-to-collation-element map.

  * `:contractions` — contraction starter index.

  * `:fast_latin` — pre-built fast lookup tuple for U+0000..U+017F.

  * `:primary_to_frac` — primary weight to fractional lead byte mapping (for script reordering).

  * `:script_ranges` — script-to-lead-byte-range mapping (for script reordering).

  * `:han_radicals` — map of CJK codepoint to
    `{radical, residual_strokes, simplification}` for UAX #38
    radical-stroke ordering.

  """
  def generate_collation_table do
    source_path = Application.app_dir(:localize, "priv/cldr/FractionalUCA.txt")

    unless File.exists?(source_path) do
      raise "FractionalUCA.txt not found at #{source_path}"
    end

    IO.puts("Parsing FractionalUCA.txt...")
    %{entries: entries} = Localize.Collation.Table.Parser.parse(source_path)

    IO.puts("Building contraction index...")
    contractions = build_contractions(entries)

    IO.puts("Building fast Latin table...")
    fast_latin = build_fast_latin(entries, contractions)

    IO.puts("Parsing reorder data...")
    primary_to_frac = Localize.Collation.Reorder.parse_primary_to_frac(source_path)
    script_ranges = Localize.Collation.Reorder.parse_top_bytes(source_path)

    IO.puts("Parsing Han radical data...")
    han_radicals = parse_han_radicals(source_path)

    data = %{
      entries: entries,
      contractions: contractions,
      fast_latin: fast_latin,
      primary_to_frac: primary_to_frac,
      script_ranges: script_ranges,
      han_radicals: han_radicals
    }

    binary = :erlang.term_to_binary(data, [:compressed])
    size_kb = div(byte_size(binary), 1024)

    # Write to the build output directory
    build_path = Application.app_dir(:localize, "priv/localize/collation_table.etf")
    File.mkdir_p!(Path.dirname(build_path))
    File.write!(build_path, binary)
    IO.puts("Wrote #{size_kb}KB to #{build_path}")

    # Also write to the source priv directory so it ships with the package
    source_path = Path.join([File.cwd!(), "priv", "localize", "collation_table.etf"])
    File.mkdir_p!(Path.dirname(source_path))
    File.write!(source_path, binary)
    IO.puts("Wrote #{size_kb}KB to #{source_path}")

    :ok
  end

  defp build_contractions(entries) do
    entries
    |> Enum.reduce(%{}, fn {key, _elements}, acc ->
      case key do
        cp when is_integer(cp) ->
          acc

        tuple when is_tuple(tuple) ->
          first = elem(tuple, 0)
          len = tuple_size(tuple)
          existing = Map.get(acc, first, MapSet.new())
          Map.put(acc, first, MapSet.put(existing, len))
      end
    end)
    |> Map.new(fn {cp, lengths} -> {cp, MapSet.to_list(lengths)} end)
  end

  @latin_limit 0x0180

  defp build_fast_latin(entries, contractions) do
    for cp <- 0..(@latin_limit - 1) do
      cond do
        Map.has_key?(contractions, cp) -> nil
        combining_mark?(cp) -> nil
        true -> Map.get(entries, cp)
      end
    end
    |> List.to_tuple()
  end

  defp combining_mark?(cp) do
    Localize.Collation.Unicode.combining_class(cp) > 0
  end

  # Parse `[radical N=...:members]` lines from FractionalUCA.txt into a
  # %{codepoint => {radical_number, residual_strokes, simplification}}
  # map. Uses Localize.Collation.Han.parse_radical_line/1 which is
  # already a pure parser (no I/O, no state).
  defp parse_han_radicals(path) do
    path
    |> File.stream!()
    |> Enum.reduce(%{}, fn line, acc ->
      case Localize.Collation.Han.parse_radical_line(String.trim(line)) do
        {:ok, radical_num, members} ->
          Enum.reduce(members, acc, fn {cp, simplification, strokes}, acc ->
            Map.put(acc, cp, {radical_num, strokes, simplification})
          end)

        :skip ->
          acc
      end
    end)
  end

  # ── Private helpers ─────────────────────────────────────────────

  defp collation_source_dir do
    Localize.Data.collation_source_dir()
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
                nil ->
                  []

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
