defmodule Localize.Data.Locale do
  @moduledoc """
  Generates consolidated CLDR locale data from raw CLDR JSON and XML sources.

  Reads locale-specific JSON files from the CLDR production data directories,
  merges them, applies normalization transforms, and saves the result as a
  JSON file suitable for runtime loading by `Localize.Locale.Loader`.

  """

  alias Localize.Utils.Map, as: LMap

  @required_modules [
    "version",
    "number_formats",
    "list_formats",
    "currencies",
    "number_systems",
    "number_symbols",
    "minimum_grouping_digits",
    "minimal_pairs",
    "rbnf",
    "units",
    "date_fields",
    "dates",
    "territories",
    "languages",
    "delimiters",
    "ellipsis",
    "nested_bracket_replacement",
    "lenient_parse",
    "locale_display_names",
    "subdivisions",
    "person_names",
    "layout"
  ]

  @doc """
  Generates a consolidated locale data map for the given locale.

  ### Arguments

  * `locale` is a locale name string (e.g., `"en"`, `"fr"`, `"zh-Hant"`).

  ### Returns

  * The consolidated locale data map.

  """
  def generate_locale(locale) do
    consolidate_locale_content(locale)
    |> level_up_locale(locale)
    |> put_localized_subdivisions(locale)
    |> LMap.underscore_keys(
      except: "locale_display_names",
      skip: ["availableFormats", "intervalFormats"]
    )
    |> normalize_content(locale)
    |> apply_loader_transforms()
    |> Map.take(Enum.map(@required_modules, &String.to_atom/1))
    |> add_version()
    |> add_name(locale)
  end

  @doc """
  Generates and transforms locale data.

  Calls `generate_locale/1` to produce the consolidated data,
  then applies `Localize.Data.LocaleTransformer.transform/1` to
  convert number symbols, number formats, and currencies to
  their struct forms.

  """
  def generate_and_transform(locale) do
    locale
    |> generate_locale()
    |> Localize.Data.LocaleTransformer.transform()
  end

  @doc """
  Generates, transforms, and saves a locale ETF file.

  Calls `generate_locale/1` to produce the consolidated data,
  then applies `Localize.Data.LocaleTransformer.transform/1` to
  convert number symbols, number formats, and currencies to
  their struct forms before writing the ETF file.

  """
  def generate_and_save_locale(locale) do
    data = generate_and_transform(locale)
    save_locale(data, locale)

    data
  end

  # ── Content consolidation ─────────────────────────────────────

  # Reads all JSON files from priv/cldr/locales/<locale>/ and
  # merges them into a single map. Files are named as
  # <source-dir>__<original-name>.json by copy_locale_sources.
  defp consolidate_locale_content(locale) do
    locale_dir = Path.join(Localize.Data.locales_source_dir(), locale)

    case File.ls(locale_dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, ".json"))
        |> Enum.sort()
        |> Enum.map(&decode_locale_file(locale_dir, &1))
        |> merge_maps()

      {:error, _} ->
        %{}
    end
  end

  defp decode_locale_file(locale_dir, file) do
    content = File.read!(Path.join(locale_dir, file))
    if content == "", do: %{}, else: :json.decode(content)
  end

  defp merge_maps([]), do: %{}
  defp merge_maps([single]), do: single
  defp merge_maps([first, second]), do: LMap.deep_merge(first, second)
  defp merge_maps([first | rest]), do: LMap.deep_merge(first, merge_maps(rest))

  defp level_up_locale(content, locale) do
    get_in(content, ["main", locale])
  end

  defp put_localized_subdivisions(result, locale) do
    subdivisions =
      localized_subdivisions(locale)
      |> LMap.atomize_keys()

    Map.put(result, "subdivisions", subdivisions)
  end

  defp localized_subdivisions(locale) do
    subdivisions_path =
      Path.join([Localize.Data.locales_source_dir(), locale, "subdivisions.xml"])

    if File.exists?(subdivisions_path) do
      parse_xml_subdivisions(subdivisions_path)
    else
      %{}
    end
  end

  defp parse_xml_subdivisions(xml_path) do
    import SweetXml

    xml_path
    |> File.read!()
    |> String.replace(~r/<!DOCTYPE.*>\n/, "")
    |> xpath(~x"//subdivision"l, code: ~x"./@type"s, translation: ~x"./text()")
    |> Map.new(fn subdivision ->
      {subdivision.code, to_string(subdivision.translation)}
    end)
  end

  # ── Loader-equivalent post-processing ──────────────────────────
  #
  # The Cldr.Locale.Loader applies additional transformations when
  # loading consolidated JSON. We replicate those here so the
  # generated data matches what get_locale returns.

  @alt_keys [
    "default",
    "menu",
    "short",
    "long",
    "variant",
    "standard",
    "medium",
    "core",
    "extension",
    "alt"
  ]

  @lenient_parse_keys ["date", "general", "number"]

  defp apply_loader_transforms(content) do
    content
    |> LMap.atomize_keys(level: 1)
    |> LMap.atomize_keys(filter: :languages, only: @alt_keys)
    |> LMap.atomize_keys(filter: :lenient_parse, only: @lenient_parse_keys)
    |> restore_alt_language_code()
  end

  # The "alt" language code (Southern Altai) collides with the
  # "alt" style key in @alt_keys, so the :languages atomize pass
  # above converts the language code itself to :alt. Restore the
  # binary code — language codes are binary keys.
  defp restore_alt_language_code(%{languages: %{alt: name} = languages} = content) do
    languages = languages |> Map.delete(:alt) |> Map.put("alt", name)
    %{content | languages: languages}
  end

  defp restore_alt_language_code(content), do: content

  # ── Normalization pipeline ────────────────────────────────────

  defp normalize_content(content, locale) do
    content
    |> Localize.Data.Normalize.Number.normalize(locale)
    |> Localize.Data.Normalize.MinimalPairs.normalize(locale)
    |> Localize.Data.Normalize.Currency.normalize(locale)
    |> Localize.Data.Normalize.List.normalize(locale)
    |> Localize.Data.Normalize.NumberSystem.normalize(locale)
    |> Localize.Data.Normalize.Rbnf.normalize(locale)
    |> Localize.Data.Normalize.Units.normalize(locale)
    |> Localize.Data.Normalize.DateFields.normalize(locale)
    |> Localize.Data.Normalize.Calendar.normalize(locale)
    |> Localize.Data.Normalize.DateTime.normalize(locale)
    |> Localize.Data.Normalize.TerritoryNames.normalize(locale)
    |> Localize.Data.Normalize.LanguageNames.normalize(locale)
    |> Localize.Data.Normalize.Delimiter.normalize(locale)
    |> Localize.Data.Normalize.Ellipsis.normalize(locale)
    |> Localize.Data.Normalize.NestedBrackets.normalize(locale)
    |> Localize.Data.Normalize.LenientParse.normalize(locale)
    |> Localize.Data.Normalize.LocaleDisplayNames.normalize(locale)
    |> Localize.Data.Normalize.PersonName.normalize(locale)
    |> Localize.Data.Normalize.Layout.normalize(locale)
  end

  defp add_version(content) do
    Map.put(content, :version, Localize.version())
  end

  defp add_name(content, locale) do
    Map.put(content, :name, String.to_atom(locale))
  end

  defp save_locale(content, locale) do
    output_dir = Localize.Data.locales_output_dir()
    File.mkdir_p!(output_dir)
    output_path = Path.join(output_dir, "#{locale}.etf")
    # `:deterministic` sorts map keys into canonical term order so the
    # encoding is byte-reproducible across machines and architectures.
    # Without it, term_to_binary reflects a map's internal representation,
    # which differs between VM instances (e.g. macOS/arm64 vs Linux/amd64),
    # breaking the download-integrity hash manifest.
    File.write!(output_path, :erlang.term_to_binary(content, [:deterministic]))
    :ok
  end
end
