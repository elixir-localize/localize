defmodule Localize.Data.Normalize.Units do
  @moduledoc false

  alias Localize.Utils.Map, as: LMap

  @unit_types ["short", "long", "narrow"]

  def normalize(content, locale) do
    units =
      units_for_locale(locale)
      |> get_in(["main", locale, "units"])
      |> LMap.underscore_keys()

    normalized_units =
      units
      |> Enum.filter(fn {k, _v} -> k in @unit_types end)
      |> Map.new()
      |> process_unit_types(@unit_types)
      |> Enum.map(fn {style, units_data} -> {style, group_units(units_data)} end)
      |> Map.new()
      |> deep_atomize_unit_keys()

    Map.put(content, "units", normalized_units)
  end

  defp process_unit_types(%{} = content, unit_types) do
    Enum.reduce(unit_types, content, &process_unit_type(&1, &2))
  end

  defp process_unit_type(type, %{} = content) do
    updated_format =
      get_in(content, [type])
      |> Enum.map(&process_formats/1)
      |> LMap.merge_map_list()

    put_in(content, [type], updated_format)
  end

  defp process_formats({unit, formats}) do
    parsed_formats =
      Enum.map(formats, fn
        {"unit_pattern_count_" <> count, template} ->
          {:nominative, {count, Localize.Substitution.parse(template)}}

        {"genitive_count_" <> count, template} ->
          {:genitive, {count, Localize.Substitution.parse(template)}}

        {"accusative_count_" <> count, template} ->
          {:accusative, {count, Localize.Substitution.parse(template)}}

        {"dative_count_" <> count, template} ->
          {:dative, {count, Localize.Substitution.parse(template)}}

        {"locative_count_" <> count, template} ->
          {:locative, {count, Localize.Substitution.parse(template)}}

        {"instrumental_count_" <> count, template} ->
          {:instrumental, {count, Localize.Substitution.parse(template)}}

        {"vocative_count_" <> count, template} ->
          {:vocative, {count, Localize.Substitution.parse(template)}}

        {"display_name", display_name} ->
          {"display_name", display_name}

        {"gender", gender} ->
          {"gender", gender}

        {"compound_unit_pattern1" <> rest, template} ->
          {"compound_unit_pattern", compound_unit(rest, template)}

        {type, template} ->
          {type, Localize.Substitution.parse(template)}
      end)
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Enum.map(fn
        {k, v} when is_atom(k) ->
          {k, Map.new(v)}

        {k, [v]} ->
          {k, v}

        {k, v} when is_list(v) ->
          {k, map_nested_compounds(v)}
      end)
      |> Map.new()

    %{unit => parsed_formats}
  end

  def compound_unit("_" <> rest, template), do: compound_unit(rest, template)
  def compound_unit("", template), do: {:nominative, template}

  def compound_unit("count_" <> rest, template) do
    case String.split(rest, "_", parts: 2) do
      [count] -> {count, template}
      [count, rest] -> {count, compound_unit(rest, template)}
    end
  end

  def compound_unit("case_" <> grammatical_case, template) do
    {grammatical_case, template}
  end

  def compound_unit("gender_" <> rest, template) do
    [gender, rest] = String.split(rest, "_", parts: 2)
    {gender, compound_unit(rest, template)}
  end

  def map_nested_compounds(list, acc \\ Map.new())
  def map_nested_compounds([], acc), do: acc

  def map_nested_compounds(value, %{} = _acc) when is_binary(value) do
    Localize.Substitution.parse(value)
  end

  def map_nested_compounds({key, value}, acc) do
    Map.put(acc, key, map_nested_compounds(value))
  end

  def map_nested_compounds([{key, value} | rest], acc) do
    mapped_value = map_nested_compounds(value)

    acc =
      Map.update(acc, key, mapped_value, fn
        current when is_map(current) and is_map(mapped_value) ->
          Map.merge(current, mapped_value)

        current when is_map(current) ->
          Map.put(current, :nominative, mapped_value)

        current when is_list(current) ->
          value
          |> map_nested_compounds()
          |> Map.put(:nominative, current)
      end)

    map_nested_compounds(rest, acc)
  end

  defp units_for_locale(locale) do
    path = units_locale_path(locale)

    if File.exists?(path) do
      path |> File.read!() |> :json.decode()
    else
      %{}
    end
  end

  defp units_locale_path(locale) do
    Path.join([Localize.Data.cldr_source_dir(), "cldr-units-full", "main", locale, "units.json"])
  end

  defp group_units(units) do
    units
    |> Enum.map(fn {k, v} ->
      [group | key] =
        cond do
          String.starts_with?(k, "10p") -> [k | []]
          String.starts_with?(k, "1024p") -> [k | []]
          true -> String.split(k, "_", parts: 2)
        end

      if key == [] do
        {"compound", group, v}
      else
        [key] = key
        {group, key, v}
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.group_by(
      fn {group, _key, _value} -> group end,
      fn {_group, key, value} -> {key, atomize_gender(value)} end
    )
    |> Enum.map(fn {k, v} -> {k, Map.new(v)} end)
    |> Map.new()
  end

  defp atomize_gender(map) when is_map(map) do
    map
    |> Enum.map(&atomize_gender/1)
    |> Map.new()
  end

  defp atomize_gender({"gender" = key, [gender]}), do: {key, gender}
  defp atomize_gender({"gender" = key, gender}), do: {key, gender}
  defp atomize_gender(other), do: other

  defp deep_atomize_unit_keys(map) when is_map(map) do
    Enum.map(map, fn {k, v} ->
      key = if is_binary(k), do: String.to_atom(k), else: k
      {key, deep_atomize_unit_keys(v)}
    end)
    |> Map.new()
  end

  defp deep_atomize_unit_keys(list) when is_list(list), do: list
  defp deep_atomize_unit_keys(other), do: other
end
