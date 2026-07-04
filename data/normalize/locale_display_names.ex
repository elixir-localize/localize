defmodule Localize.Data.Normalize.LocaleDisplayNames do
  @moduledoc false

  alias Localize.Data.Normalize.Helpers
  alias Localize.Utils.Map, as: LMap

  def normalize(content, _locale) do
    locale_display_names =
      content
      |> Map.fetch!("locale_display_names")
      |> Helpers.default([])

    scripts =
      locale_display_names
      |> Map.get("scripts", %{})
      |> Helpers.group_alt_content(&String.capitalize/1)
      |> LMap.rename_keys("default", "standard")
      |> LMap.atomize_keys()

    locale_display_pattern =
      case Map.get(locale_display_names, "locale_display_pattern") do
        nil ->
          %{}

        pattern ->
          pattern
          |> Enum.map(fn {k, v} -> {k, Localize.Substitution.parse(v)} end)
          |> Map.new()
          |> LMap.atomize_keys()
      end

    code_patterns =
      case Map.get(locale_display_names, "code_patterns") do
        nil ->
          nil

        patterns ->
          patterns
          |> Enum.map(fn {k, v} -> {k, Localize.Substitution.parse(v)} end)
          |> Map.new()
          |> LMap.atomize_keys()
      end

    measurement_systems =
      locale_display_names
      |> Map.get("types", %{})
      |> Map.get("ms", %{})
      |> Enum.map(fn
        {"uksystem", description} -> {"imperial", description}
        other -> other
      end)
      |> Map.new()
      |> LMap.atomize_keys()

    types =
      locale_display_names
      |> Map.get("types", %{})
      |> Map.put("ms", measurement_systems)
      |> LMap.atomize_keys()

    # Only include keys/subdivisions/measurement_system_names if they exist in source
    optional_fields =
      [
        {"keys", &atomize_if_present/1},
        {"subdivisions", &atomize_if_present/1},
        {"measurement_system_names", &atomize_if_present/1}
      ]
      |> Enum.reduce(%{}, fn {field, transform}, acc ->
        case Map.get(locale_display_names, field) do
          nil -> acc
          value -> Map.put(acc, field, transform.(value))
        end
      end)

    locale_display_names =
      locale_display_names
      |> LMap.rename_keys("variants", "language_variants")
      |> Map.delete("languages")
      |> Map.delete("scripts")
      |> Map.delete("territories")
      |> Map.put("script", scripts)
      |> Map.put("types", types)
      |> Map.put("locale_display_pattern", locale_display_pattern)
      |> then(fn m ->
        if code_patterns, do: Map.put(m, "code_patterns", code_patterns), else: m
      end)
      |> Map.merge(optional_fields)
      |> LMap.atomize_keys(level: 1)

    Map.put(content, "locale_display_names", locale_display_names)
  end

  defp atomize_if_present(map) when is_map(map), do: LMap.atomize_keys(map)
  defp atomize_if_present(other), do: other
end
