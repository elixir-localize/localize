defmodule Localize.Data.Supplemental do
  @moduledoc """
  Generates supplemental data ETF files from raw CLDR JSON source data.

  Each `generate_*` function reads raw CLDR JSON from the production
  data directory, transforms it into the runtime format expected by
  `Localize.SupplementalData`, and returns the data structure. The
  caller is responsible for writing the result as an ETF file.

  """

  alias Localize.Utils.Map, as: LMap

  # ── Simple generators ───────────────────────────────────────────

  @doc """
  Generates parent locale data from `parentLocales.json`.

  Returns a map of locale strings to their parent locale strings.

  """
  def generate_parent_locales do
    Localize.Data.read_json("parentLocales.json")
    |> get_in(["supplemental", "parentLocales", "parentLocale"])
  end

  @doc """
  Generates territory code mappings from `codeMappings.json`.

  Returns a map of territory atoms to maps with `:alpha3`, `:numeric`,
  and `:fips10` string values.

  """
  def generate_territory_codes do
    Localize.Data.read_json("codeMappings.json")
    |> get_in(["supplemental", "codeMappings"])
    |> LMap.rename_keys("_numeric", "numeric")
    |> LMap.rename_keys("_alpha3", "alpha3")
    |> LMap.rename_keys("_fips10", "fips10")
    |> Enum.reject(fn {code, _value} -> String.length(code) > 2 end)
    |> Map.new()
    |> LMap.atomize_keys()
  end

  @doc """
  Generates number system definitions from `numberingSystems.json`.

  Returns a map of number system atoms to maps with `:type` (atom),
  `:digits` (string), and/or `:rules` (string).

  """
  def generate_number_systems do
    Localize.Data.read_json("numberingSystems.json")
    |> get_in(["supplemental", "numberingSystems"])
    |> LMap.remove_leading_underscores()
    |> LMap.atomize_keys()
    |> Enum.map(fn {k, v} -> {k, %{v | type: String.to_atom(v.type)}} end)
    |> Map.new()
  end

  @doc """
  Generates calendar preferences from `calendarPreferenceData.json`.

  Returns a map of territory atoms to lists of calendar type atoms.

  """
  def generate_calendar_preferences do
    Localize.Data.read_json("calendarPreferenceData.json")
    |> get_in(["supplemental", "calendarPreferenceData"])
    |> LMap.remove_leading_underscores()
    |> Enum.map(fn {k, v} ->
      {k, Enum.map(v, &Localize.Utils.String.to_underscore(&1))}
    end)
    |> Map.new()
    |> LMap.atomize_keys()
    |> LMap.atomize_values()
  end

  @doc """
  Generates territory container mappings from `territoryContainment.json`.

  Returns a map of container territory atoms to lists of contained
  territory atoms.

  """
  def generate_territory_containers do
    Localize.Data.read_json("territoryContainment.json")
    |> get_in(["supplemental", "territoryContainment"])
    |> normalize_territory_containers()
    |> LMap.atomize_keys()
    |> LMap.atomize_values()
  end

  @doc """
  Generates territory containment chains derived from territory containers.

  Returns a map of territory atoms to their ancestor chain as a
  list of territory atoms.

  """
  def generate_territory_containment do
    containers =
      Localize.Data.read_json("territoryContainment.json")
      |> get_in(["supplemental", "territoryContainment"])
      |> normalize_territory_containers()

    containers
    |> build_tree()
    |> Enum.map(&Enum.reverse/1)
    |> Enum.map(fn [head | rest] -> {head, rest} end)
    |> Map.new()
    |> LMap.atomize_keys()
    |> LMap.atomize_values()
  end

  # ── Medium complexity generators ────────────────────────────────

  @doc """
  Generates alias data from `aliases.json`.

  Returns a map with atom keys `:language`, `:script`, `:region`,
  `:variant`, `:subdivision`, and `:zone`, each containing alias
  mappings.

  """
  def generate_aliases do
    Localize.Data.read_json("aliases.json")
    |> get_in(["supplemental", "metadata", "alias"])
    |> LMap.remove_leading_underscores()
    |> LMap.rename_keys("variantAlias", "variant")
    |> LMap.rename_keys("scriptAlias", "script")
    |> LMap.rename_keys("zoneAlias", "zone")
    |> LMap.rename_keys("territoryAlias", "region")
    |> LMap.rename_keys("languageAlias", "language")
    |> LMap.rename_keys("subdivisionAlias", "subdivision")
    |> LMap.deep_map(&split_alternates/1)
    |> Enum.map(&simplify_replacements/1)
    |> Map.new()
    |> parse_language_aliases()
    |> LMap.atomize_keys(level: 1..1)
    |> LMap.deep_map(
      fn
        {k, v} when is_binary(v) ->
          if String.length(v) == 2, do: {k, String.to_atom(v)}, else: {k, v}

        other ->
          other
      end,
      filter: :subdivision
    )
  end

  @doc """
  Generates likely subtags data from `likelySubtags.json`.

  Returns a map of locale strings to maps with `:language` (string),
  `:script` (atom), and `:territory` (atom).

  """
  def generate_likely_subtags do
    Localize.Data.read_json("likelySubtags.json")
    |> get_in(["supplemental", "likelySubtags"])
    |> Enum.map(fn {k, v} ->
      tag = parse_locale_to_subtag_map(v)
      {k, tag}
    end)
    |> Map.new()
  end

  @doc """
  Generates time preference data from `timeData.json`.

  Returns a map of territory atoms to maps with `:preferred` (string)
  and `:allowed` (list of strings).

  """
  def generate_time_preferences do
    Localize.Data.read_json("timeData.json")
    |> get_in(["supplemental", "timeData"])
    |> LMap.remove_leading_underscores()
    |> LMap.deep_map(fn {k, v} -> {k, String.split(v)} end, only: "allowed")
    |> atomize_territory_keys()
  end

  @doc """
  Generates week data from `weekData.json`.

  Returns a map with atom keys `:first_day`, `:min_days`,
  `:weekend_start`, and `:weekend_end`, each mapping territory
  atoms to integer day-of-week values.

  """
  def generate_weeks do
    Localize.Data.read_json("weekData.json")
    |> get_in(["supplemental", "weekData"])
    |> adjust_day_names()
    |> LMap.integerize_values()
    |> LMap.underscore_keys(only: ["weekendStart", "weekendEnd", "minDays", "firstDay"])
    |> Map.take(["weekend_start", "min_days", "first_day", "weekend_end"])
    |> LMap.atomize_keys()
  end

  @doc """
  Generates sorted list of currency code atoms from `currencyData.json`.

  """
  def generate_currency_codes do
    Path.join([Localize.Data.locales_source_dir(), "en", "cldr-numbers-full__currencies.json"])
    |> File.read!()
    |> :json.decode()
    |> get_in(["main", "en", "numbers", "currencies"])
    |> Map.keys()
    |> Enum.sort()
    |> Enum.map(&String.to_atom/1)
  end

  @doc """
  Generates territory currency data from `currencyData.json`.

  Returns a map of territory atoms to maps of currency atoms
  to maps with `:from` and `:to` Date values and optional
  `:tender` boolean.

  """
  def generate_territory_currencies do
    Localize.Data.read_json("currencyData.json")
    |> get_in(["supplemental", "currencyData", "region"])
    |> Enum.map(fn {territory, currency_list} ->
      currencies =
        Enum.map(currency_list, fn currency_map ->
          Enum.map(currency_map, fn {currency_code, attrs} ->
            parsed = parse_currency_attrs(attrs)
            {String.to_atom(currency_code), parsed}
          end)
        end)
        |> List.flatten()
        |> Map.new()

      {String.to_atom(territory), currencies}
    end)
    |> Map.new()
  end

  # ── Complex generators ────────────────────────────────────────────

  @doc """
  Generates territory metadata from `territoryInfo.json`,
  `currencyData.json`, and `measurementData.json`.

  Returns a map of territory atoms to maps containing GDP,
  population, literacy, currency history, measurement system,
  and language population data.

  """
  def generate_territories do
    territory_currencies = generate_territory_currencies_raw()
    measurement_systems = get_measurement_data()

    Localize.Data.read_json("territoryInfo.json")
    |> get_in(["supplemental", "territoryInfo"])
    |> LMap.remove_leading_underscores()
    |> LMap.underscore_keys()
    |> LMap.integerize_values()
    |> LMap.floatize_values()
    |> Enum.map(fn {code, rest} -> {String.upcase(code), rest} end)
    |> Enum.map(&normalize_language_codes/1)
    |> Map.new()
    |> add_currency_for_territories(territory_currencies)
    |> add_measurement_system(measurement_systems)
  end

  @doc """
  Generates language matching data from `languageMatching.json`.

  Returns a map with atom keys `:language_match`, `:match_variables`,
  and `:paradigm_locales`.

  """
  def generate_language_matching do
    Localize.Data.read_json("languageMatching.json")
    |> get_in(["supplemental", "languageMatching"])
    |> LMap.underscore_keys()
    |> LMap.rename_keys("_desired", "desired")
    |> LMap.rename_keys("_distance", "distance")
    |> LMap.rename_keys("_supported", "supported")
    |> LMap.rename_keys("_value", "value")
    |> LMap.rename_keys("_locales", "locales")
    |> LMap.rename_keys("_oneway", "one_way")
    |> LMap.deep_map(
      fn {"value", v} -> {"value", String.split(v, "+")} end,
      filter: "match_variables",
      only: "value"
    )
    |> parse_language_matches()
    |> expand_match_variables()
    |> level_up_paradigm_locales()
    |> LMap.atomize_keys()
    |> Map.fetch!(:written_new)
  end

  # ── Private helpers ─────────────────────────────────────────────

  defp normalize_territory_containers(content) do
    content
    |> Enum.map(fn
      {<<container::binary-size(3)>>, v} ->
        {container, Map.get(v, "_contains")}

      {<<container::binary-size(2)>>, v} ->
        {container, Map.get(v, "_contains")}

      {<<container::binary-size(3), "-status-grouping">>, v} ->
        {container, Map.get(v, "_contains")}

      _other ->
        nil
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort()
    |> merge_containers()
    |> Map.new()
  end

  defp merge_containers([]), do: []

  defp merge_containers([{container, values_1}, {container, values_2} | rest]) do
    values = Enum.uniq(values_1 ++ values_2)
    merge_containers([{container, values} | rest])
  end

  defp merge_containers([container | rest]) do
    [container | merge_containers(rest)]
  end

  defp build_tree(tree, leaf \\ "001", _level \\ 0) do
    if leaves = Map.get(tree, leaf) do
      Enum.map(leaves, &build_tree(tree, &1, 0))
    else
      leaf
    end
    |> merge_leaf(leaf)
  end

  defp merge_leaf([first | _rest] = subtree, leaf) when is_binary(first) do
    Enum.map(subtree, &[leaf, &1])
  end

  defp merge_leaf([[first | _] | _rest] = subtree, leaf) when is_binary(first) do
    Enum.map(subtree, &[leaf | &1])
  end

  defp merge_leaf(subtree, leaf) when is_list(subtree) do
    Enum.map(subtree, &merge_leaf(&1, leaf))
    |> combine_lists()
  end

  defp merge_leaf(leaf, leaf) do
    leaf
  end

  defp combine_lists([a]) when is_list(a), do: combine_lists(a)

  defp combine_lists([[a | _] | _rest] = list) when is_binary(a), do: list

  defp combine_lists([a, b | rest]) when is_list(a) and is_list(b) do
    combine_lists([a ++ b | rest])
  end

  defp combine_lists(a), do: a

  defp split_alternates({k, v}) when is_binary(v) do
    if String.contains?(v, " ") do
      {k, String.split(v, " ")}
    else
      {k, v}
    end
  end

  defp split_alternates(other), do: other

  @replacement "replacement"
  defp simplify_replacements({k, %{} = v}) do
    if Map.get(v, @replacement) do
      {k, Map.get(v, @replacement)}
    else
      replacements = Enum.map(v, &simplify_replacements/1) |> Map.new()
      {k, replacements}
    end
  end

  defp simplify_replacements({k, v}) when is_list(v) do
    {k, Enum.map(v, &simplify_replacements/1)}
  end

  defp simplify_replacements({k, v}), do: {k, v}

  defp parse_language_aliases(map) do
    language_aliases =
      Enum.map(Map.get(map, "language"), fn {k, v} ->
        [language | _rest] = String.split(v, " ")
        {k, parse_language_tag_to_alias(language)}
      end)
      |> Map.new()

    Map.put(map, "language", language_aliases)
  end

  defp parse_language_tag_to_alias(locale_string) do
    tag = Localize.LanguageTag.parse!(locale_string)

    %{
      language: to_string(tag.language),
      script: tag.script,
      territory: tag.territory,
      language_variants: tag.language_variants
    }
  end

  defp parse_locale_to_subtag_map(locale_string) do
    parts = String.split(locale_string, "-")

    case parts do
      [language, script, territory] ->
        %{
          language: language,
          script: String.to_atom(script),
          territory: String.to_atom(territory)
        }

      [language, second] ->
        if String.length(second) == 4 and String.match?(second, ~r/^[A-Z]/) do
          %{language: language, script: String.to_atom(second), territory: nil}
        else
          %{language: language, script: nil, territory: String.to_atom(second)}
        end

      [language] ->
        %{language: language, script: nil, territory: nil}
    end
  end

  defp adjust_day_names(content) do
    LMap.deep_map(content, fn
      {key, "sun"} -> {key, 7}
      {key, "mon"} -> {key, 1}
      {key, "tue"} -> {key, 2}
      {key, "wed"} -> {key, 3}
      {key, "thu"} -> {key, 4}
      {key, "fri"} -> {key, 5}
      {key, "sat"} -> {key, 6}
      other -> other
    end)
  end

  # Atomizes only top-level keys that look like territory codes
  # (2-3 uppercase characters or "001"-style codes). Leaves other
  # keys (like locale codes with hyphens) as strings. Also atomizes
  # all nested string keys.
  defp atomize_territory_keys(map) when is_map(map) do
    Enum.map(map, fn {k, v} ->
      if is_binary(k) and territory_code?(k) do
        {String.to_atom(k), LMap.atomize_keys(v)}
      else
        {k, LMap.atomize_keys(v)}
      end
    end)
    |> Map.new()
  end

  defp territory_code?(code) when is_binary(code) do
    String.length(code) <= 3 and not String.contains?(code, "-")
  end

  defp parse_currency_attrs(attrs) when is_map(attrs) do
    Enum.reduce(attrs, %{}, fn
      {"_from", from}, acc -> Map.put(acc, :from, Date.from_iso8601!(from))
      {"_to", to}, acc -> Map.put(acc, :to, Date.from_iso8601!(to))
      {"_tender", "false"}, acc -> Map.put(acc, :tender, false)
      {"_tender", "true"}, acc -> acc
      {"_" <> _key, _value}, acc -> acc
      _other, acc -> acc
    end)
  end

  # Raw territory currencies for use in territories generation
  # Returns the intermediate format (with string keys) needed by add_currency_for_territories
  defp generate_territory_currencies_raw do
    Localize.Data.read_json("currencyData.json")
    |> get_in(["supplemental", "currencyData", "region"])
    |> LMap.rename_keys("_from", "from")
    |> LMap.rename_keys("_to", "to")
    |> LMap.rename_keys("_tender", "tender")
  end

  @language_population_key "language_population"
  defp normalize_language_codes({k, v}) do
    if language_population = Map.get(v, @language_population_key) do
      language_population =
        language_population
        |> Enum.map(fn {k1, v1} ->
          {canonical_locale_name(k1), LMap.atomize_keys(v1)}
        end)
        |> Map.new()

      {k, Map.put(v, @language_population_key, language_population)}
    else
      {k, v}
    end
  end

  defp canonical_locale_name(name) do
    name
    |> Localize.LanguageTag.parse!()
    |> Localize.LanguageTag.to_string()
  end

  defp add_currency_for_territories(territories, currencies) do
    territories
    |> Enum.map(fn {territory, map} ->
      {territory, Map.put(map, "currency", Map.get(currencies, territory))}
    end)
    |> Map.new()
  end

  defp add_measurement_system(territories, systems) do
    territories
    |> Enum.map(fn {territory, map} ->
      territory_atom = String.to_atom(territory)

      measurement_system =
        %{}
        |> Map.put(
          :default,
          (get_in(systems, [:measurement_system, territory_atom]) ||
             get_in(systems, [:measurement_system, :"001"]))
          |> canonicalize_measurement_system()
        )
        |> Map.put(
          :paper_size,
          (get_in(systems, [:paper_size, territory_atom]) ||
             get_in(systems, [:paper_size, :"001"]))
          |> canonicalize_measurement_system()
        )
        |> Map.put(
          :temperature,
          (get_in(systems, [:measurement_system_category_temperature, territory_atom]) ||
             get_in(systems, [:measurement_system, territory_atom]) ||
             get_in(systems, [:measurement_system, :"001"]))
          |> canonicalize_measurement_system()
        )

      {territory_atom, Map.put(map, :measurement_system, measurement_system)}
    end)
    |> Map.new()
    |> atomize_territory_data()
  end

  defp atomize_territory_data(territories) do
    Enum.map(territories, fn {territory, data} ->
      data = atomize_territory_values(data)
      {territory, data}
    end)
    |> Map.new()
  end

  defp atomize_territory_values(data) when is_map(data) do
    data
    |> Map.put_new("language_population", %{})
    |> Enum.map(fn
      {"currency", nil} ->
        {:currency, []}

      {"currency", currency_list} when is_list(currency_list) ->
        currencies =
          Enum.flat_map(currency_list, fn currency_map ->
            Enum.map(currency_map, fn {currency_code, attrs} ->
              parsed_attrs = parse_territory_currency_attrs(attrs)
              {String.to_atom(currency_code), parsed_attrs}
            end)
          end)

        {:currency, currencies}

      {"language_population", nil} ->
        {:language_population, %{}}

      {key, value} when is_binary(key) ->
        {String.to_atom(key), value}

      {key, value} ->
        {key, value}
    end)
    |> Map.new()
  end

  defp parse_territory_currency_attrs(attrs) when is_map(attrs) do
    attrs
    |> Enum.reduce(%{}, fn
      {"from", from}, acc -> Map.put(acc, :from, Date.from_iso8601!(from))
      {"to", to}, acc -> Map.put(acc, :to, Date.from_iso8601!(to))
      {"tender", "false"}, acc -> Map.put(acc, :tender, false)
      {_key, _value}, acc -> acc
    end)
  end

  defp get_measurement_data do
    Localize.Data.read_json("measurementData.json")
    |> get_in(["supplemental", "measurementData"])
    |> Enum.map(fn {k, v} ->
      key =
        k
        |> Localize.Utils.String.underscore()
        |> Localize.Utils.String.to_underscore()

      {key, v}
    end)
    |> Map.new()
    |> LMap.atomize_keys()
  end

  defp canonicalize_measurement_system(data) when is_map(data) do
    Enum.map(data, fn
      {k, "US"} -> {k, "ussystem"}
      {k, "UK"} -> {k, "uksystem"}
      {k, "A4"} -> {k, "a4"}
      {k, "US-Letter"} -> {k, "us_letter"}
      other -> other
    end)
    |> Map.new()
  end

  defp canonicalize_measurement_system(data) when is_binary(data) do
    case data do
      "US" -> :ussystem
      "UK" -> :uksystem
      "A4" -> :a4
      "US-Letter" -> :us_letter
      "metric" -> :metric
      other -> String.to_atom(other)
    end
  end

  defp canonicalize_measurement_system(nil), do: nil

  # ── Language matching helpers ───────────────────────────────────

  defp parse_language_matches(matching) do
    language_match =
      matching
      |> get_in(["written_new", "language_match"])
      |> Enum.map(&parse_match/1)

    put_in(matching, ["written_new", "language_match"], language_match)
  end

  defp parse_match(match) do
    supported = parse_match_skeleton(match["supported"])
    desired = parse_match_skeleton(match["desired"])

    match
    |> Map.put("supported", supported)
    |> Map.put("desired", desired)
  end

  defp parse_match_skeleton(skeleton) do
    parts =
      case String.split(skeleton, "-") do
        [language] ->
          [language]

        [language, script] ->
          [language, String.to_atom(script)]

        [language, script, territory] ->
          [language, String.to_atom(script), parse_territory_match(territory)]
      end

    case parts do
      ["*" | rest] -> [:* | rest]
      other -> other
    end
  end

  defp parse_territory_match("$!" <> match_variable) do
    {:not_in, String.to_atom("$" <> match_variable)}
  end

  defp parse_territory_match("$" <> _rest = variable) do
    {:in, String.to_atom(variable)}
  end

  defp parse_territory_match(territory) do
    String.to_atom(territory)
  end

  defp expand_match_variables(matching) do
    # Use Localize.SupplementalData to get territory containers
    # for expanding match variables
    containers = Localize.SupplementalData.territory_containers()

    variables =
      matching
      |> get_in(["written_new", "match_variables"])
      |> Enum.map(fn var -> expand_variable(var, containers) end)
      |> Map.new()

    put_in(matching, ["written_new", "match_variables"], variables)
  end

  defp expand_variable({"$en_us", value}, containers) do
    expand_variable({"$enUS", value}, containers)
  end

  defp expand_variable({variable, %{"value" => value}}, containers) do
    expanded =
      Enum.map(value, fn territory ->
        territory
        |> String.to_atom()
        |> expand_territory(containers)
      end)
      |> List.flatten()

    {variable, expanded}
  end

  defp expand_territory(territory, containers) do
    if contained = Map.get(containers, territory) do
      [territory | Enum.map(contained, &expand_territory(&1, containers))]
    else
      territory
    end
  end

  defp level_up_paradigm_locales(matching) do
    paradigm_locales =
      matching
      |> get_in(["written_new", "paradigm_locales", "locales"])

    matching
    |> Map.delete("paradigm_locales")
    |> put_in(["written_new", "paradigm_locales"], paradigm_locales)
  end
end
