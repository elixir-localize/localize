defmodule Localize.Locale.LocaleDisplay.T do
  @moduledoc false

  alias Localize.Utils.Helpers

  import Localize.Locale.LocaleDisplay,
    only: [get_display_preference: 2, join_field_values: 2, replace_nested_brackets: 2]

  # # display_name/4
  #
  # Returns a display name for the Transform extension (T).
  #
  # ### Arguments
  #
  # * `transform` is the transform extension struct or map.
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
  def display_name(transform, locale_id, display_names, options) do
    prefer = Keyword.get(options, :prefer, :standard)
    language_display = Keyword.get(options, :language_display, :standard)

    # Get T extension fields, excluding h0 (handled specially)
    fields = get_fields(transform)

    for {_key, field} <- fields, !is_nil(value = get_field(transform, field)) do
      format_key_value(
        field,
        value,
        transform,
        locale_id,
        display_names,
        prefer,
        language_display
      )
    end
    |> join_field_values(display_names)
  end

  defp get_fields(%Localize.LanguageTag.T{}) do
    Localize.Validity.T.field_mapping() |> Map.delete("h0") |> Enum.sort()
  end

  defp get_fields(map) when is_map(map) do
    Localize.Validity.T.field_mapping()
    |> Map.delete("h0")
    |> Enum.filter(fn {key, _field} -> Map.has_key?(map, key) end)
    |> Enum.sort()
  end

  defp get_field(%Localize.LanguageTag.T{} = struct, field) do
    Map.get(struct, field)
  end

  defp get_field(map, field) when is_map(map) do
    inverse = Localize.Validity.T.field_mapping()
    key = Enum.find_value(inverse, fn {k, v} -> if v == field, do: k end)
    Map.get(map, key) || Map.get(map, to_string(field))
  end

  def format_key_value(
        field,
        value,
        transform,
        locale_id,
        display_names,
        prefer,
        language_display \\ :standard
      ) do
    canonical_value = canonicalize_value(field, value)

    if value_name = get_type(field, canonical_value, display_names) do
      replace_nested_brackets(value_name, display_names)
    else
      # CLDR 48.2: fall back to key identifier when translation is missing
      key_name = get_in(display_names, [:keys, field]) || bcp47_key_for(field)

      display_value(
        field,
        key_name,
        canonical_value,
        transform,
        locale_id,
        display_names,
        prefer,
        language_display
      )
    end
  end

  defp canonicalize_value(_field, value) when is_atom(value), do: value

  defp canonicalize_value(field, value) when is_binary(value) do
    # Try to convert to existing atom for type lookup
    _bcp47_key =
      Enum.find_value(Localize.Validity.T.field_mapping(), fn {k, v} ->
        if v == field, do: k
      end)

    # T extension validity data is a flat list of valid values
    # (no canonical mappings like U extension). Just convert
    # hyphens to underscores and atomize for type key lookup.
    value
    |> String.replace("-", "_")
    |> then(&(Helpers.existing_atom(&1) || &1))
  end

  defp canonicalize_value(_field, value), do: value

  defp display_value(
         :language,
         _key_name,
         value,
         transform,
         locale_id,
         display_names,
         prefer,
         language_display
       ) do
    h0 = get_field(transform, :h0)

    key_name =
      if h0 == :hybrid do
        get_in(display_names, [:types, :h0, :hybrid])
      else
        nil
      end

    # CLDR 48.2: fall back to key identifier when translation is missing
    key_name = key_name || get_in(display_names, [:keys, :t]) || "t"

    # CLDR 48.2: Flatten the T language — do not use localePattern.
    # Instead, get the language name and append subtag display names
    # directly as a flat list.
    value_parts =
      flatten_t_language(value, locale_id, display_names, prefer, language_display)

    value_name =
      value_parts
      |> join_field_values(display_names)
      |> :erlang.iolist_to_binary()
      |> replace_nested_brackets(display_names)

    display_pattern = get_in(display_names, [:locale_display_pattern, :locale_key_type_pattern])
    Localize.Substitution.substitute([key_name, value_name], display_pattern)
  end

  defp display_value(
         _key,
         nil,
         value,
         _transform,
         _locale_id,
         display_names,
         _prefer,
         _language_display
       )
       when is_binary(value) do
    replace_nested_brackets(value, display_names)
  end

  defp display_value(
         _key,
         nil,
         value,
         _transform,
         _locale_id,
         display_names,
         _prefer,
         _language_display
       )
       when is_atom(value) do
    value |> to_string() |> replace_nested_brackets(display_names)
  end

  defp display_value(
         key,
         key_name,
         value,
         transform,
         locale_id,
         display_names,
         prefer,
         _language_display
       ) do
    value_name =
      key
      |> get_special(key_name, value, transform, locale_id, display_names)
      |> Kernel.||(value)
      |> get_display_preference(prefer)
      |> :erlang.iolist_to_binary()
      |> replace_nested_brackets(display_names)

    display_pattern = get_in(display_names, [:locale_display_pattern, :locale_key_type_pattern])
    Localize.Substitution.substitute([key_name, value_name], display_pattern)
  end

  # Flatten a T language tag into a list of display name parts:
  # [language_name, script_name, region_name, variant1, variant2, ...]
  # CLDR 48.2: Do not use localePattern; append subtag display names directly.
  # Use longest locale name match (e.g., "fr-CA" → "Canadian French"),
  # then only include subtags NOT consumed by the match.
  # CLDR 48.2 T-extension display: dialect vs standard mode plus
  # consumed/unconsumed branching for each of script, territory, variants.
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp flatten_t_language(
         %Localize.LanguageTag{} = tag,
         _locale_id,
         display_names,
         prefer,
         language_display
       ) do
    # CLDR 48.2: Flatten the T language — do not use localePattern.
    # In dialect mode: use longest language match (e.g., "fr-CA" → "Canadian French"),
    # then only show unconsumed subtags.
    # In standard mode: use language-only match, show all subtags separately.
    {language_name, consumed} =
      if language_display == :dialect do
        find_longest_language_match(tag, display_names, prefer)
      else
        lang_key = to_string(tag.language)

        name =
          get_display_preference(get_in(display_names, [:language, lang_key]), prefer) || lang_key

        {name, []}
      end

    script = if tag.script, do: tag.script |> to_string() |> capitalize_script() |> to_atom_safe()
    territory = if tag.territory, do: normalize_territory(tag.territory)

    subtags =
      [
        if(script && :script not in consumed,
          do:
            get_display_preference(get_in(display_names, [:script, script]), prefer) ||
              to_string(tag.script)
        ),
        if(territory && :territory not in consumed,
          do:
            get_display_preference(get_in(display_names, [:territory, territory]), prefer) ||
              to_string(tag.territory)
        )
      ]
      |> Enum.reject(&is_nil/1)

    variant_names =
      (tag.language_variants || [])
      |> Enum.map(fn v ->
        v_str = to_string(v)

        get_display_preference(
          get_in(display_names, [:language_variants, v_str]),
          prefer
        ) || v_str
      end)

    [language_name | subtags ++ variant_names]
  end

  defp flatten_t_language(value, _locale_id, display_names, prefer, _language_display)
       when is_atom(value) do
    language_name =
      get_display_preference(get_in(display_names, [:language, value]), prefer) ||
        to_string(value)

    [language_name]
  end

  defp find_longest_language_match(tag, display_names, prefer) do
    lang = to_string(tag.language)
    script_str = if tag.script, do: tag.script |> to_string() |> capitalize_script()
    territory_str = if tag.territory, do: normalize_territory_string(tag.territory)

    candidates =
      [
        if(script_str && territory_str,
          do: {"#{lang}-#{script_str}-#{territory_str}", [:script, :territory]}
        ),
        if(territory_str, do: {"#{lang}-#{territory_str}", [:territory]}),
        if(script_str, do: {"#{lang}-#{script_str}", [:script]}),
        {lang, []}
      ]
      |> Enum.reject(&is_nil/1)

    Enum.find_value(candidates, {lang, []}, fn {key, consumed} ->
      case get_display_preference(get_in(display_names, [:language, key]), prefer) do
        nil -> nil
        name -> {name, consumed}
      end
    end)
  end

  defp normalize_territory_string(t) when is_integer(t) do
    t |> Integer.to_string() |> String.pad_leading(3, "0")
  end

  defp normalize_territory_string(t), do: t |> to_string() |> String.upcase()

  defp get_special(:x0, _key_name, values, _transform, _locale_id, display_names)
       when is_list(values) do
    join_field_values(values, display_names)
  end

  defp get_special(:x0, _key_name, value, _transform, _locale_id, _display_names) do
    value
  end

  defp get_special(_key, key_name, value, _transform, _locale_id, display_names) do
    get_in(display_names, [:types, key_name, value])
  end

  defp get_type(field, [value], display_names) do
    get_in(display_names, [:types, field, value])
  end

  defp get_type(field, value, display_names) do
    get_in(display_names, [:types, field, value])
  end

  # Normalize territory: integers get zero-padded to 3 digits, strings get uppercased
  defp normalize_territory(t) when is_integer(t) do
    t |> Integer.to_string() |> String.pad_leading(3, "0") |> to_atom_safe()
  end

  defp normalize_territory(t) when is_atom(t), do: t

  defp normalize_territory(t) when is_binary(t) do
    t |> String.upcase() |> to_atom_safe()
  end

  defp capitalize_script(<<first::binary-size(1), rest::binary>>),
    do: String.upcase(first) <> String.downcase(rest)

  defp capitalize_script(s), do: s

  # Return the existing atom for the binary, OR the binary itself when
  # no such atom exists. Callers use the result as a key into atom-keyed
  # display-name maps; a string passed through `get_in` simply misses
  # the lookup and falls back to the raw binary, which is the desired
  # behaviour for unknown subtags. Falling through to `String.to_atom/1`
  # here was an atom-table DOS vector since callers pass `-t-` extension
  # values that originate in untrusted input.
  defp to_atom_safe(value) when is_binary(value),
    do: Helpers.existing_atom(value) || value

  # CLDR 48.2: when key translation is missing, fall back to the
  # BCP47 key identifier string.
  defp bcp47_key_for(field) do
    mapping = Localize.Validity.T.field_mapping()

    Enum.find_value(mapping, to_string(field), fn {key, f} ->
      if f == field, do: key
    end)
  end
end
