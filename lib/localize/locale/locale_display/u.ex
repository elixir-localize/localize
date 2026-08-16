defmodule Localize.Locale.LocaleDisplay.U do
  @moduledoc false

  import Localize.Locale.LocaleDisplay,
    only: [get_display_preference: 2, join_field_values: 2, replace_nested_brackets: 2]

  alias Localize.DateTime.Timezone

  # Mapping from BCP47 U extension struct field atoms to the
  # CLDR key names used in locale_display_names[:keys] and [:types].
  # Fields not in this map use the field atom directly.
  @field_to_display_key %{
    ca: :calendar,
    co: :collation,
    cu: :currency,
    nu: :numbers,
    tz: :timezone,
    ks: :col_strength,
    ka: :col_alternate,
    kb: :col_backwards,
    kc: :col_case_level,
    kf: :col_case_first,
    kh: :col_normalization,
    kk: :col_normalization,
    kn: :col_numeric,
    kr: :col_reorder
  }

  # # display_name/4
  #
  # Returns a display name for the Unicode locale extension (U).
  #
  # ### Arguments
  #
  # * `locale_ext` is the locale extension struct or map.
  #
  # * `locale_id` is a locale identifier atom.
  #
  # * `display_names` is the display names data map.
  #
  # * `options` is a keyword list of options.
  #
  # ### Returns
  #
  # * A formatted display string, or `[]` if empty.
  #
  def display_name(locale_ext, locale_id, display_names, options) do
    prefer = Keyword.get(options, :prefer, :standard)

    # Handle both LanguageTag.U structs and plain maps
    fields = get_fields(locale_ext)

    for {_key, field} <- fields, !is_nil(value = get_field(locale_ext, field)) do
      format_key_value(field, value, locale_ext, locale_id, display_names, prefer)
    end
    |> join_field_values(display_names)
  end

  defp get_fields(%Localize.LanguageTag.U{}) do
    Localize.Validity.U.field_mapping() |> Enum.sort()
  end

  defp get_fields(map) when is_map(map) do
    # Plain map from parsed tag — keys are strings like "ca", "cu"
    # Map them to the field_mapping format
    Localize.Validity.U.field_mapping()
    |> Enum.filter(fn {key, _field} -> Map.has_key?(map, key) end)
    |> Enum.sort()
  end

  defp get_field(%Localize.LanguageTag.U{} = struct, field) do
    Map.get(struct, field)
  end

  defp get_field(map, field) when is_map(map) do
    # Try the atom field name first, then the string key
    inverse = Localize.Validity.U.field_mapping()
    key = Enum.find_value(inverse, fn {k, v} -> if v == field, do: k end)
    value = Map.get(map, key) || Map.get(map, to_string(field))

    # BCP47 U extension values can be multi-part lists (e.g., ["islamic", "civil"])
    # Join them with hyphens to form the canonical BCP47 value
    case value do
      parts when is_list(parts) -> Enum.join(parts, "-")
      other -> other
    end
  end

  def format_key_value(field, value, locale_ext, locale_id, display_names, prefer) do
    display_key = Map.get(@field_to_display_key, field, field)
    canonical_value = canonicalize_value(field, value)

    if value_name = get_type(display_key, canonical_value, display_names) do
      replace_nested_brackets(value_name, display_names)
    else
      # CLDR 48.2: fall back to key identifier when translation is missing
      key_name = get_in(display_names, [:keys, display_key]) || to_string(display_key)

      display_value(
        field,
        key_name,
        canonical_value,
        locale_ext,
        locale_id,
        display_names,
        prefer
      )
    end
  end

  # Canonicalize a BCP47 value using validity data.
  # BCP47 values use hyphens (e.g., "islamic-civil") while CLDR
  # type keys use underscores (e.g., :islamic_civil). The validity
  # data maps short aliases (e.g., "islamicc") to canonical forms.
  defp canonicalize_value(field, value) when is_binary(value) do
    bcp47_key =
      Enum.find_value(Localize.Validity.U.field_mapping(), fn {k, v} ->
        if v == field, do: k
      end)

    canonical = canonical_validity_value(bcp47_key, value)

    # Convert hyphens to underscores for CLDR type key lookup
    canonical = String.replace(canonical, "-", "_")
    safe_to_atom(canonical)
  end

  defp canonicalize_value(_field, value) when is_atom(value), do: value
  defp canonicalize_value(_field, value), do: value

  # Look up the canonical form of a value in the validity data.
  # Try the value as-is first (short BCP47 alias like "islamicc"),
  # then try the de-hyphenated form.
  defp canonical_validity_value(nil, value), do: value

  defp canonical_validity_value(bcp47_key, value) do
    validity = Localize.SupplementalData.validity(:u)

    case get_in(validity, [bcp47_key, value]) do
      nil -> canonical_dehyphenated_value(validity, bcp47_key, value)
      canonical -> unwrap_deprecated(canonical)
    end
  end

  defp canonical_dehyphenated_value(validity, bcp47_key, value) do
    dehyphenated = String.replace(value, "-", "")

    case get_in(validity, [bcp47_key, dehyphenated]) do
      nil -> value
      canonical -> unwrap_deprecated(canonical)
    end
  end

  defp safe_to_atom(string) when is_binary(string) do
    Localize.Utils.Helpers.existing_atom(string) || string
  end

  # Returns the localized value when key_name is nil
  defp display_value(_key, nil, value, _locale_ext, _locale_id, display_names, _prefer)
       when is_binary(value) do
    replace_nested_brackets(value, display_names)
  end

  defp display_value(_key, nil, value, _locale_ext, _locale_id, display_names, _prefer)
       when is_atom(value) do
    value |> to_string() |> replace_nested_brackets(display_names)
  end

  defp display_value(key, key_name, value, locale_ext, locale_id, display_names, prefer) do
    value_name =
      key
      |> get_special(key_name, value, locale_ext, locale_id, display_names)
      |> Kernel.||(value)
      |> get_display_preference(prefer)
      |> :erlang.iolist_to_binary()
      |> replace_nested_brackets(display_names)

    if key_name do
      display_pattern = get_in(display_names, [:locale_display_pattern, :locale_key_type_pattern])
      Localize.Substitution.substitute([key_name, value_name], display_pattern)
    else
      replace_nested_brackets(value_name, display_names)
    end
  end

  # Special handling for certain fields

  # These match on the struct field name (BCP47 key atom), not display key name
  defp get_special(:rg, _key_name, value, _locale_ext, locale_id, display_names) do
    get_subdivision(value, locale_id, display_names) ||
      get_territory(value, display_names)
  end

  defp get_special(:sd, _key_name, value, _locale_ext, locale_id, display_names) do
    get_subdivision(value, locale_id, display_names) ||
      get_territory(value, display_names)
  end

  defp get_special(:dx, _key_name, values, _locale_ext, _locale_id, display_names)
       when is_list(values) do
    Enum.map(values, fn value ->
      get_script(value, display_names) || to_string(value)
    end)
    |> join_field_values(display_names)
  end

  defp get_special(:dx, _key_name, value, _locale_ext, _locale_id, display_names) do
    case get_script(value, display_names) do
      nil -> nil
      %{standard: script} -> String.downcase(script)
      script when is_binary(script) -> String.downcase(script)
    end
  end

  defp get_special(:tz, _key_name, value, _locale_ext, locale_id, _display_names)
       when is_binary(value) do
    get_timezone_display_name(value, locale_id)
  end

  defp get_special(:cu, _key_name, value, _locale_ext, locale_id, _display_names) do
    get_currency(value, locale_id)
  end

  defp get_special(:kr, key_name, values, locale_ext, locale_id, display_names)
       when is_list(values) do
    get_special(:col_reorder, key_name, values, locale_ext, locale_id, display_names)
  end

  defp get_special(:col_reorder, _key_name, values, _locale_ext, _locale_id, display_names)
       when is_list(values) do
    Enum.map(values, fn value ->
      get_script(value, display_names) ||
        get_in(display_names, [:types, :col_reorder, value]) ||
        to_string(value)
    end)
    |> join_field_values(display_names)
  end

  defp get_special(key, key_name, value, _locale_ext, _locale_id, display_names) do
    display_key = Map.get(@field_to_display_key, key, key)

    get_in(display_names, [:types, display_key, value]) ||
      get_in(display_names, [:types, key_name, value])
  end

  # Type lookup for simple key-value pairs
  defp get_type(:col_reorder, [value], display_names) do
    get_in(display_names, [:types, :col_reorder, value])
  end

  defp get_type(display_key, [value], display_names) do
    get_in(display_names, [:types, display_key, value])
  end

  defp get_type(display_key, value, display_names) do
    get_in(display_names, [:types, display_key, value])
  end

  defp get_territory(territory, display_names) when is_atom(territory) do
    get_in(display_names, [:territory, territory])
  end

  defp get_territory(territory, display_names) when is_binary(territory) do
    atom_territory = Localize.Utils.Helpers.existing_atom(String.upcase(territory))
    if atom_territory, do: get_in(display_names, [:territory, atom_territory])
  end

  defp get_script(script, display_names) do
    case get_in(display_names, [:script, script]) do
      %{standard: name} -> name
      name when is_binary(name) -> name
      _ -> nil
    end
  end

  defp get_subdivision(subdivision, _locale_id, display_names) do
    sub_atom =
      if is_binary(subdivision) do
        Localize.Utils.Helpers.existing_atom(subdivision)
      else
        subdivision
      end

    if sub_atom, do: get_in(display_names, [:subdivisions, sub_atom])
  end

  defp get_currency(currency, locale_id) when is_atom(currency) do
    # Currency codes are uppercase atoms like :AUD
    upcase_currency =
      currency
      |> Atom.to_string()
      |> String.upcase()
      |> safe_to_atom()

    if is_atom(upcase_currency) do
      case Localize.Currency.currency_for_code(upcase_currency) do
        {:ok, currency_struct} -> currency_struct.symbol
        _other -> nil
      end
    else
      get_currency(Atom.to_string(currency), locale_id)
    end
  end

  defp get_currency(currency, _locale_id) when is_binary(currency) do
    atom_currency = Localize.Utils.Helpers.existing_atom(String.upcase(currency))

    if atom_currency do
      case Localize.Currency.currency_for_code(atom_currency) do
        {:ok, currency_struct} -> currency_struct.symbol
        _other -> nil
      end
    end
  end

  # Timezone display names.
  #
  # Implements the CLDR non-location format algorithm:
  # 1. Find the territory for the IANA timezone ID.
  # 2. If the territory has only one timezone, use the territory
  #    (country) display name as the location (e.g., "United Kingdom").
  # 3. Otherwise, use the exemplar city name (e.g., "Los Angeles").
  # 4. Format using the locale's regionFormat pattern
  #    (e.g., "{0} Time").
  defp get_timezone_display_name(iana_id, locale_id) when is_binary(iana_id) do
    case Localize.Locale.get(locale_id, [:dates, :time_zone_names]) do
      {:ok, tz_data} ->
        region_format = get_in(tz_data, [:region_format, :generic])
        territory = Map.get(Timezone.territories_by_timezone(), iana_id)

        location = timezone_location(iana_id, territory, locale_id)

        if location && region_format do
          Localize.Substitution.substitute(location, region_format)
          |> :erlang.iolist_to_binary()
        else
          nil
        end

      _ ->
        nil
    end
  end

  # Steps 2 and 3 of the non-location format algorithm: a territory with only
  # one timezone is named by the country, and anything else by the zone's
  # exemplar city.
  defp timezone_location(iana_id, territory, locale_id) do
    if territory && Timezone.timezone_count_for_territory(territory) == {:ok, 1} do
      get_territory_name(territory, locale_id)
    else
      case Timezone.exemplar_city(iana_id, locale_id) do
        {:ok, city} -> city
        {:error, _reason} -> nil
      end
    end
  end

  # Look up the display name for a territory.
  defp get_territory_name(territory, locale_id) do
    case Localize.Territory.display_name(territory, locale: locale_id) do
      {:ok, name} -> name
      _ -> Atom.to_string(territory)
    end
  end

  # Validity values for deprecated spellings are tagged
  # `{:deprecated, preferred}`; display always uses the preferred
  # form.
  defp unwrap_deprecated({:deprecated, preferred}), do: preferred
  defp unwrap_deprecated(value), do: value
end
