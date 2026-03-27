defmodule Localize.Data.Normalize.Helpers do
  @moduledoc false

  alias Localize.Utils.Map, as: LMap

  @doc """
  Returns a default value if the input is nil.

  """
  def default(nil, default_value), do: default_value
  def default(value, _default_value), do: value

  @doc """
  Groups map entries by alternate key variants.

  For a key like `"am"` and variant `"am_alt_variant"`, produces:
  `%{"am" => %{"default" => value1, "variant" => value2}}`.

  """
  def group_by_alt(map, key, options \\ [])
  def group_by_alt(nil, _key, _options), do: nil

  def group_by_alt(map, key, options) when is_map(map) and is_binary(key) do
    default_key = Keyword.get(options, :default, "default")
    alt = "_" <> Keyword.get(options, :alt, "alt") <> "_"

    grouped =
      map
      |> Enum.filter(fn
        {^key, _v} -> true
        {k, _v} -> String.starts_with?(k, key <> alt)
      end)
      |> Enum.group_by(
        fn {k, _value} ->
          String.split(k, alt) |> hd()
        end,
        fn {k, v} ->
          case String.split(k, alt) do
            [_] -> {default_key, v}
            [_, type] -> {type, v}
          end
        end
      )
      |> Enum.map(fn {k, v} -> {k, Map.new(v)} end)
      |> Map.new()

    map
    |> Map.merge(grouped)
    |> Map.reject(&String.starts_with?(elem(&1, 0), key <> alt))
  end

  @doc """
  Groups map entries that have `_alt_` or `_menu_` variants.

  Collects entries like `"en"`, `"en_alt_long"`, `"en_menu_alt"` into
  a nested structure grouped by the base key.

  """
  def group_alt_content(map, normalizer_fun \\ & &1) do
    map
    |> default([])
    |> Enum.map(fn {code, value} ->
      case String.split(code, ~r/(_alt_|_menu_)/, include_captures: true) do
        [lang] ->
          {[normalizer_fun.(lang)], value}

        [lang, "_alt_", "menu"] ->
          {[normalizer_fun.(lang), "_menu_", "alt"], value}

        [lang, alt, alt_value] ->
          {[normalizer_fun.(lang), alt, alt_value], value}
      end
    end)
    |> Enum.group_by(fn {k, _v} -> hd(k) end, fn {k, v} ->
      case k do
        [_lang] ->
          %{"default" => v}

        [_lang, "_alt_", alt] ->
          %{alt => v}

        [_lang, "_menu_", menu] ->
          %{"menu" => %{menu => v}}
      end
    end)
    |> Enum.map(fn {k, v} -> {k, LMap.merge_map_list(v)} end)
    |> Map.new()
  end

  @doc """
  Groups prefixed content with alt variants.

  """
  def group_prefixed_content(map, prefix, normalizer_fun \\ & &1) do
    map
    |> default([])
    |> Enum.map(fn
      {^prefix, value} -> {prefix <> "_alt_default", value}
      other -> other
    end)
    |> Map.new()
    |> group_alt_content(normalizer_fun)
  end

  @doc """
  Unnest single-element maps for the given keys.

  If a key maps to a map with exactly one entry, replace
  it with just that entry's value.

  """
  def unnest_if_only_one(map, keys) do
    Enum.reduce(keys, map, fn k, acc ->
      if is_map(acc[k]) and map_size(acc[k]) == 1 do
        Map.put(acc, k, hd(Map.values(acc[k])))
      else
        acc
      end
    end)
  end
end
