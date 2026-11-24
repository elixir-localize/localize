defmodule Localize.Data.Collation do
  @moduledoc """
  Generates collation tailoring ETF data from CLDR collation XML files.

  Parses all collation XML files from the CLDR repository, extracts
  tailoring rule strings, resolves `[import]` directives, and returns
  a map keyed by `{cldr_locale_id, type}` tuples, the locale id being the
  atom a validated tag carries as its `cldr_locale_id`.

  """

  import SweetXml

  # Types to skip — private and searchjl are internal only
  @skip_types MapSet.new(["private", "searchjl"])

  # The draft statuses left out, as the JSON build leaves them out of the
  # locale data (`Localize.Data.CldrJson` keeps `contributed` and above).
  # A collation with an `alt="proposed…"` is a proposal, and unconfirmed.
  @excluded_drafts ["provisional", "unconfirmed"]

  # BCP47 collation type abbreviations to CLDR XML type names
  @bcp47_to_cldr_type %{
    "phonebk" => "phonebook",
    "trad" => "traditional",
    "dict" => "dictionary",
    "ducet" => "ducet"
  }

  @latin_limit 0x0180

  @doc """
  Generates collation tailoring data from CLDR XML collation files.

  Reads XML files from `../cldr_repo/common/collation/`, parses
  tailoring rules, resolves import directives, and returns a map of
  `{cldr_locale_id, type_atom}` tuples to the type's rules: `fr_CA.xml` is
  `{:"fr-CA", :standard}`, and `root.xml`'s search collation `{:und, :search}`.

  A type's rules are grouped by their `alt` form, as `alt` forms are
  throughout the locale data: `:standard` for the collation with no `alt`,
  and the `alt` value, such as `:short`, for each alternative. CLDR gives
  `zh` a short form of its pinyin, stroke and zhuyin collations. An
  `[import]` names a type, which is its `:standard` form.

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
          root_search_entries(entries)
        else
          entries
        end
      end)

    raw_map =
      Map.new(all_raw, fn {language, type, alt, rules} -> {{language, type, alt}, rules} end)

    # Phase 2: Resolve [import] directives
    raw_map
    |> Enum.map(fn {key, rules} -> {key, resolve_all_imports(rules, raw_map)} end)
    |> Enum.reject(fn {_key, rules} -> not has_ordering_rules?(rules) or rules == "" end)
    # Keyed by the CLDR locale a file is for, as the atom a validated tag
    # carries in `cldr_locale_id`, so a lookup uses the tag's id and builds
    # no identifier. The set is CLDR's and closed, so the atoms are made
    # here, at build time.
    |> Enum.group_by(
      fn {{locale, type, _alt}, _rules} -> {String.to_atom(locale), type} end,
      fn {{_locale, _type, alt}, rules} -> {alt, rules} end
    )
    |> Map.new(fn {key, forms} -> {key, Map.new(forms)} end)
  end

  defp resolve_all_imports(rules, raw_map) do
    if String.contains?(rules, "[import") do
      resolve_imports(rules, raw_map)
    else
      rules
    end
  end

  @doc """
  Generates the collation inheritance data from the CLDR collation XML
  and the `collations` component of `parentLocales.json`.

  TR35 gives collation data its own inheritance. A locale's parent is the
  one the `collations` component of `parentLocales` names; otherwise the
  one the main `parentLocales` names, except through its
  `localeRules="nonlikelyScript"` element, which TR35 does not apply to
  collations; otherwise the locale with its last subtag dropped. So
  `zh-Hant`, whose main parent is the root, takes its collation data from
  `zh`, `yue` from `zh-Hant`, and `nb` from `no`. A locale's default collation type is the `defaultCollation`
  of the first locale on that chain that declares one: `pinyin` for `zh`
  and `stroke` for `zh-Hant` and its children.

  Returns a map with two keys, both keyed by every CLDR locale id as the
  atom a validated tag carries in `cldr_locale_id`:

  * `:chains` maps a locale to the locales on its collation chain that
    have collation data, nearest first and ending with `:und`. A locale
    whose chain has only `:und` is left out.

  * `:default_types` maps a locale to its default collation type, for
    the locales whose default is not `:standard`.

  """
  def generate_collation_inheritance do
    collation_dir = collation_source_dir()

    defaults =
      collation_dir
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".xml"))
      |> Enum.flat_map(&default_collation(collation_dir, &1))
      |> Map.new()

    data_locales =
      generate_collation_tailoring()
      |> Map.keys()
      |> Enum.map(fn {locale, _type} -> Atom.to_string(locale) end)
      |> MapSet.new()
      |> MapSet.union(MapSet.new(Map.keys(defaults)))
      |> MapSet.put("und")

    parents = collation_parents()

    chains =
      Map.new(Localize.SupplementalData.all_locale_ids(), fn locale ->
        {locale, collation_chain(Atom.to_string(locale), parents)}
      end)

    # Every CLDR locale id is already an atom, and so is every collation
    # locale and type, which are CLDR's closed sets.
    %{
      chains:
        for {locale, chain} <- chains,
            data_chain = Enum.filter(chain, &MapSet.member?(data_locales, &1)),
            data_chain != ["und"],
            into: %{} do
          {locale, Enum.map(data_chain, &String.to_atom/1)}
        end,
      default_types:
        for {locale, chain} <- chains,
            type = Enum.find_value(chain, &Map.get(defaults, &1)),
            type not in [nil, "standard"],
            into: %{} do
          {locale, String.to_atom(type)}
        end
    }
  end

  # A file's `defaultCollation`, keyed by its locale as a chain names it.
  defp default_collation(collation_dir, filename) do
    locale =
      case Path.basename(filename, ".xml") do
        "root" -> "und"
        name -> String.replace(name, "_", "-")
      end

    xml =
      collation_dir
      |> Path.join(filename)
      |> File.read!()
      |> then(&Regex.replace(~r/<!DOCTYPE[^>]*>/, &1, ""))

    case xpath(SweetXml.parse(xml), ~x"//collations/defaultCollation/text()"s) do
      "" -> []
      type -> [{locale, type}]
    end
  end

  # The collation parents `supplementalData.xml` names, as `%{"nb" => "no"}`.
  # The main component's explicit entries apply, but not its `localeRules`
  # element, whose short list holds `zh_Hant`; the `collations` component's
  # entries are read last, so they win.
  defp collation_parents do
    xml =
      [Localize.Data.cldr_repo_dir(), "common", "supplemental", "supplementalData.xml"]
      |> Path.join()
      |> File.read!()
      |> then(&Regex.replace(~r/<!DOCTYPE[^>]*>/, &1, ""))
      |> SweetXml.parse()

    groups =
      xpath(xml, ~x"//parentLocales"l,
        component: ~x"./@component"s,
        entries: [
          ~x"./parentLocale"l,
          parent: ~x"./@parent"s,
          locales: ~x"./@locales"s,
          rules: ~x"./@localeRules"s
        ]
      )

    main = Enum.filter(groups, &(&1.component == ""))
    collations = Enum.filter(groups, &("collations" in String.split(&1.component)))

    Map.merge(parent_entries(main), parent_entries(collations))
  end

  defp parent_entries(groups) do
    for %{entries: entries} <- groups,
        %{parent: parent, locales: locales, rules: ""} <- entries,
        locale <- String.split(locales),
        into: %{} do
      {cldr_locale_name(locale), cldr_locale_name(parent)}
    end
  end

  defp cldr_locale_name("root") do
    "und"
  end

  defp cldr_locale_name(name) do
    String.replace(name, "_", "-")
  end

  # The locale, then each collation parent, ending with `und`.
  defp collation_chain(locale, parents) do
    locale
    |> Stream.unfold(fn
      nil -> nil
      current -> {current, collation_parent(current, parents)}
    end)
    |> Enum.to_list()
  end

  defp collation_parent("und", _parents) do
    nil
  end

  defp collation_parent(locale, parents) do
    Map.get_lazy(parents, locale, fn -> truncated(locale) end)
  end

  defp truncated(locale) do
    subtags = String.split(locale, "-")

    case Enum.drop(subtags, -1) do
      [] -> "und"
      parent -> Enum.join(parent, "-")
    end
  end

  defp root_search_entries(entries) do
    entries
    |> Enum.filter(fn {_lang, type, _alt, _rules} -> type == :search end)
    |> Enum.map(fn {"root", type, alt, rules} -> {"und", type, alt, rules} end)
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
    source_path = Localize.Data.uca_table_path()

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

    binary = :erlang.term_to_binary(data, [:compressed, :deterministic])
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
          add_radical_members(members, radical_num, acc)

        :skip ->
          acc
      end
    end)
  end

  defp add_radical_members(members, radical_num, acc) do
    Enum.reduce(members, acc, fn {cp, simplification, strokes}, acc ->
      Map.put(acc, cp, {radical_num, strokes, simplification})
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
      alt: ~x"./@alt"s,
      draft: ~x"./@draft"s,
      cr: ~x"./cr/text()"s
    )
    |> Enum.flat_map(fn %{type: type, alt: alt, draft: draft, cr: cr} ->
      if MapSet.member?(@skip_types, type) or cr == "" or not published?(draft, alt) do
        []
      else
        collation_entry(language, type, alt_form(alt), clean_rules(cr))
      end
    end)
  end

  defp collation_entry(language, type, alt, rules) do
    if has_ordering_rules?(rules) and rules != "" do
      [{language, String.to_atom(type), alt, rules}]
    else
      []
    end
  end

  defp published?(draft, alt) do
    draft not in @excluded_drafts and not String.starts_with?(alt, "proposed")
  end

  # A collation with no `alt` is the `:standard` form, as the locale data
  # names an unqualified entry.
  defp alt_form("") do
    :standard
  end

  defp alt_form(alt) do
    String.to_atom(alt)
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
      String.starts_with?(line, [
        "&",
        "[caseFirst",
        "[caseLevel",
        "[alternate",
        "[backwards",
        "[normalization",
        "[strength",
        "[suppressContractions",
        "[reorder",
        "[import"
      ])
    end)
  end

  defp resolve_imports(rules, raw_map) do
    rules
    |> String.split("\n")
    |> Enum.flat_map(fn line ->
      case Regex.run(~r/^\[import\s+(.+)\]$/, line) do
        [_, tag] ->
          resolve_import_tag(parse_import_tag(tag), raw_map)

        nil ->
          [line]
      end
    end)
    |> Enum.join("\n")
    |> String.trim()
  end

  defp resolve_import_tag({lang, type}, raw_map) do
    imported_rule_lines(Map.get(raw_map, {lang, type, :standard}))
  end

  defp resolve_import_tag(nil, _raw_map), do: []

  defp imported_rule_lines(nil), do: []

  defp imported_rule_lines(imported_rules) do
    imported_rules
    |> String.split("\n")
    |> Enum.reject(&String.starts_with?(&1, "[import"))
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
