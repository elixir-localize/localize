defmodule Localize.LocaleDisplay.U do
  @moduledoc false

  import Localize.LocaleDisplay,
    only: [get_display_preference: 2, join_field_values: 2, replace_parens_with_brackets: 1]

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
      replace_parens_with_brackets(value_name)
    else
      key_name = get_in(display_names, [:keys, display_key])

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

    canonical =
      if bcp47_key do
        validity = Localize.SupplementalData.validity(:u)
        # Try the value as-is first (short BCP47 alias like "islamicc")
        # Then try the de-hyphenated form
        dehyphenated = String.replace(value, "-", "")

        case get_in(validity, [bcp47_key, value]) do
          nil ->
            case get_in(validity, [bcp47_key, dehyphenated]) do
              nil -> value
              c -> c
            end

          c ->
            c
        end
      else
        value
      end

    # Convert hyphens to underscores for CLDR type key lookup
    canonical = String.replace(canonical, "-", "_")
    safe_to_atom(canonical)
  end

  defp canonicalize_value(_field, value) when is_atom(value), do: value
  defp canonicalize_value(_field, value), do: value

  defp safe_to_atom(string) when is_binary(string) do
    String.to_existing_atom(string)
  rescue
    ArgumentError -> string
  end

  # Returns the localized value when key_name is nil
  defp display_value(_key, nil, value, _locale_ext, _locale_id, _display_names, _prefer)
       when is_binary(value) do
    replace_parens_with_brackets(value)
  end

  defp display_value(_key, nil, value, _locale_ext, _locale_id, _display_names, _prefer)
       when is_atom(value) do
    value |> to_string() |> replace_parens_with_brackets()
  end

  defp display_value(key, key_name, value, locale_ext, locale_id, display_names, prefer) do
    value_name =
      key
      |> get_special(key_name, value, locale_ext, locale_id, display_names)
      |> Kernel.||(value)
      |> get_display_preference(prefer)
      |> :erlang.iolist_to_binary()
      |> replace_parens_with_brackets()

    if key_name do
      display_pattern = get_in(display_names, [:locale_display_pattern, :locale_key_type_pattern])
      Localize.Substitution.substitute([key_name, value_name], display_pattern)
    else
      replace_parens_with_brackets(value_name)
    end
  end

  # Special handling for certain fields

  # These match on the struct field name (BCP47 key atom), not display key name
  defp get_special(:rg, _key_name, value, _locale_ext, _locale_id, display_names) do
    get_territory(value, display_names)
  end

  defp get_special(:sd, _key_name, value, _locale_ext, locale_id, display_names) do
    get_subdivision(value, locale_id, display_names)
  end

  defp get_special(:dx, _key_name, value, _locale_ext, _locale_id, display_names) do
    case get_script(value, display_names) do
      nil -> nil
      %{standard: script} -> String.downcase(script)
      script when is_binary(script) -> String.downcase(script)
    end
  end

  defp get_special(:cu, _key_name, value, _locale_ext, locale_id, _display_names) do
    get_currency(value, locale_id)
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
    atom_territory =
      try do
        String.to_existing_atom(String.upcase(territory))
      rescue
        ArgumentError -> nil
      end

    if atom_territory, do: get_in(display_names, [:territory, atom_territory])
  end

  defp get_script(script, display_names) do
    get_in(display_names, [:script, script])
  end

  defp get_subdivision(subdivision, locale_id, _display_names) do
    with {:ok, subdivisions} <-
           Localize.Locale.get(locale_id, [:locale_display_names, :subdivisions]) do
      Map.get(subdivisions, subdivision)
    else
      _ -> nil
    end
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
    upcase = String.upcase(currency)

    atom_currency =
      try do
        String.to_existing_atom(upcase)
      rescue
        ArgumentError -> nil
      end

    if atom_currency do
      case Localize.Currency.currency_for_code(atom_currency) do
        {:ok, currency_struct} -> currency_struct.symbol
        _other -> nil
      end
    end
  end
end
