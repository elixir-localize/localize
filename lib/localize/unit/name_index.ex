defmodule Localize.Unit.NameIndex do
  @moduledoc false

  # An inverted index from localized unit names to unit identifiers,
  # backing `Localize.Unit.parse/2` and `parse_unit_name/2`.
  #
  # For a locale, every unit contributes its `display_name` and the
  # literal text of each plural/grammatical-case pattern across the
  # long, short and narrow styles: the pattern `[0, " kilograms"]`
  # contributes "kilograms", `[0, "W"]` contributes "W". Lookup is
  # case-insensitive — CLDR distinguishes narrow week "w" from watt
  # "W" only by case, and requiring exact case would make ordinary
  # user input ("1KG") fail — so such collisions surface as multiple
  # candidates for the caller to disambiguate with :only/:except.
  #
  # The CLDR-derived index is cached per locale in :persistent_term
  # (locale data is immutable for the life of the release). Custom
  # units from `Localize.Unit.CustomRegistry` are merged at query
  # time so `define_unit/2` needs no cache invalidation.

  @styles [:long, :short, :narrow]

  @doc false
  # Returns the candidate units for a localized unit name: a list of
  # `%{unit: String.t(), category: String.t()}`, sorted by unit name,
  # empty when nothing matches.
  def candidates(text, locale_id) do
    normalized = normalize(text)

    cldr = Map.get(cldr_index(locale_id), normalized, [])
    custom = Map.get(custom_index(), normalized, [])

    (cldr ++ custom)
    |> Enum.uniq_by(& &1.unit)
    |> Enum.sort_by(& &1.unit)
  end

  defp normalize(text) do
    text
    |> String.trim()
    |> String.downcase()
  end

  # ── CLDR index ─────────────────────────────────────────────

  defp cldr_index(locale_id) do
    key = {__MODULE__, locale_id}

    case :persistent_term.get(key, nil) do
      nil ->
        index = build_cldr_index(locale_id)
        :persistent_term.put(key, index)
        index

      index ->
        index
    end
  end

  defp build_cldr_index(locale_id) do
    (locale_entries(locale_id) ++ canonical_entries())
    |> Enum.reduce(%{}, fn {name, candidate}, index ->
      Map.update(index, name, [candidate], &[candidate | &1])
    end)
  end

  defp locale_entries(locale_id) do
    case Localize.Locale.get(locale_id, [:units]) do
      {:ok, units} ->
        for style <- @styles,
            {category, category_units} <- Map.get(units, style, %{}),
            {unit, unit_data} <- category_units,
            name <- unit_names(unit_data),
            do: {normalize(name), %{unit: unit_identifier(unit), category: to_string(category)}}

      {:error, _} ->
        []
    end
  end

  # Locale unit data keys compound identifiers with underscores
  # (`:meter_per_second`, `:kilowatt_hour`), but the canonical CLDR
  # identifier that the parser and `new/1` accept uses hyphens
  # (`meter-per-second`, `kilowatt-hour`). Emit the canonical form so
  # a symbol like "m/s" or "kWh" resolves to a parseable identifier.
  # The transformation is the exact inverse of the identifier→key
  # mapping CLDR applies, so it round-trips every real unit; the only
  # underscore-free pseudo-units ("per", "times", "power2") are never
  # valid identifiers either way.
  defp unit_identifier(unit) do
    unit |> to_string() |> String.replace("_", "-")
  end

  # The canonical identifiers themselves always parse, in every
  # locale: "kilogram" resolves even when the locale's display data
  # calls it something else.
  defp canonical_entries do
    for {category, units} <- Localize.Unit.known_units_by_category(),
        unit <- units,
        do: {normalize(unit), %{unit: to_string(unit), category: to_string(category)}}
  end

  # A unit's names are its display name plus the literal remainder
  # of each pattern once the numeric placeholder is removed. Pattern
  # values are pre-parsed substitution lists such as [0, " kg"];
  # non-map fields (per_unit_pattern is a bare list) and non-pattern
  # values are skipped.
  defp unit_names(%{} = unit_data) do
    display_name =
      case Map.get(unit_data, :display_name) do
        name when is_binary(name) -> [name]
        _other -> []
      end

    pattern_names =
      for {_case_or_field, %{} = plural_patterns} <- unit_data,
          {_plural, pattern} <- plural_patterns,
          is_list(pattern),
          name = pattern_literal(pattern),
          name != "",
          do: name

    display_name ++ pattern_names
  end

  defp unit_names(_other), do: []

  defp pattern_literal(pattern) do
    pattern
    |> Enum.filter(&is_binary/1)
    |> Enum.join()
    |> String.trim()
  end

  # ── Custom units ───────────────────────────────────────────

  defp custom_index do
    Localize.Unit.CustomRegistry.all()
    |> Enum.flat_map(fn {name, definition} ->
      category = to_string(Map.get(definition, :category, "custom"))
      candidate = %{unit: to_string(name), category: category}

      display_names =
        for {_locale, styles} <- Map.get(definition, :display, %{}),
            {_style, plural_patterns} <- styles,
            {_plural, pattern} <- plural_patterns,
            is_binary(pattern),
            literal = pattern |> String.replace("{0}", "") |> String.trim(),
            literal != "",
            do: literal

      for unit_name <- [to_string(name) | display_names],
          do: {normalize(unit_name), candidate}
    end)
    |> Enum.reduce(%{}, fn {name, candidate}, index ->
      Map.update(index, name, [candidate], &[candidate | &1])
    end)
  end
end
