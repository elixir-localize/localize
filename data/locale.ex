defmodule Localize.Data.Locale do
  @moduledoc """
  Generates consolidated CLDR locale data from raw CLDR JSON and XML sources.

  Reads locale-specific JSON files from the CLDR production data directories,
  merges them, applies normalization transforms, and saves the result as a
  JSON file suitable for runtime loading by the locale loader.

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
    "placeholder_boundary_spacing",
    "lenient_parse",
    "locale_display_names",
    "subdivisions",
    "person_names",
    "layout",
    "posix"
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
    |> put_japanese_era_names(locale)
    |> put_localized_subdivisions(locale)
    |> LMap.underscore_keys(
      except: "locale_display_names",
      skip: ["availableFormats", "intervalFormats"]
    )
    |> normalize_content(locale)
    |> apply_loader_transforms()
    |> put_format_key_tokens()
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

  # Reads every JSON source file for the locale, across the JSON's
  # packages, and merges them into a single map in the order
  # `Localize.Data.locale_source_files/1` gives.
  defp consolidate_locale_content(locale) do
    locale
    |> Localize.Data.locale_source_files()
    |> Enum.map(&decode_locale_file/1)
    |> merge_maps()
  end

  defp decode_locale_file(path) do
    content = File.read!(path)
    if content == "", do: %{}, else: :json.decode(content)
  end

  defp merge_maps([]), do: %{}
  defp merge_maps([single]), do: single
  defp merge_maps([first, second]), do: LMap.deep_merge(first, second)
  defp merge_maps([first | rest]), do: LMap.deep_merge(first, merge_maps(rest))

  defp level_up_locale(content, locale) do
    get_in(content, ["main", locale])
  end

  # CLDR 49 names the Japanese eras from Meiji onwards only. The earlier
  # names are Localize's own data, kept from CLDR 48, and they are merged
  # over CLDR's so that the curated names hold for every pre-Meiji era.
  defp put_japanese_era_names(content, locale) do
    path = ["dates", "calendars", "japanese", "eras"]

    case get_in(content, path) do
      %{} = eras ->
        curated = Localize.Data.Calendars.japanese_era_names(locale)
        put_in(content, path, LMap.deep_merge(eras, curated))

      _no_japanese_eras ->
        content
    end
  end

  defp put_localized_subdivisions(result, locale) do
    subdivisions =
      localized_subdivisions(locale)
      |> LMap.atomize_keys()

    Map.put(result, "subdivisions", subdivisions)
  end

  defp localized_subdivisions(locale) do
    subdivisions_path = Localize.Data.subdivisions_source_path(locale)

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

  # Stores each calendar's format tables with their keys already tokenized for
  # skeleton matching. Matching a skeleton needs those tokens, and deriving
  # them — tokenizing every key of a table that runs to 74 entries — costs far
  # more than reading them. They derive from data that does not change, so
  # generating them here trades a little space in the locale file (about 1.6%)
  # for that work on every match.
  #
  # The tokens come from `Localize.DateTime.Format.Match`, the module that
  # consumes them, so the two cannot drift apart; a change to its tokenizer
  # means regenerating the locale data.
  defp put_format_key_tokens(%{dates: %{calendars: calendars} = dates} = content)
       when is_map(calendars) do
    tokenized =
      Map.new(calendars, fn {calendar_type, calendar} ->
        {calendar_type, put_calendar_format_tokens(calendar)}
      end)

    %{content | dates: %{dates | calendars: tokenized}}
  end

  defp put_format_key_tokens(content), do: content

  defp put_calendar_format_tokens(calendar) when is_map(calendar) do
    alias Localize.DateTime.Format.Match

    calendar
    |> put_tokens(
      :available_formats,
      :available_format_tokens,
      &Match.tokenize_available_formats/1
    )
    |> put_tokens(:interval_formats, :interval_format_tokens, &Match.tokenize_interval_formats/1)
  end

  defp put_calendar_format_tokens(calendar), do: calendar

  defp put_tokens(calendar, source_key, token_key, tokenize) do
    case Map.get(calendar, source_key) do
      formats when is_map(formats) -> Map.put(calendar, token_key, tokenize.(formats))
      _no_table -> calendar
    end
  end

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
    |> Localize.Data.Normalize.PlaceholderBoundarySpacing.normalize(locale)
    |> Localize.Data.Normalize.LenientParse.normalize(locale)
    |> Localize.Data.Normalize.LocaleDisplayNames.normalize(locale)
    |> Localize.Data.Normalize.PersonName.normalize(locale)
    |> Localize.Data.Normalize.Posix.normalize(locale)
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
    #
    # `:compressed` shrinks a locale by around 83%: the data repeats itself
    # heavily — pattern strings, field names and the tokenized format keys
    # recur across every calendar — and these files are downloaded one per
    # locale. The cost is about 8% on the one `binary_to_term/1` a locale
    # load pays, against bytes every consumer fetches and stores.
    File.write!(output_path, :erlang.term_to_binary(content, [:deterministic, :compressed]))
    :ok
  end
end
