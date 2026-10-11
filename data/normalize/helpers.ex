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
    |> Enum.map(&alt_path(&1, normalizer_fun))
    |> Enum.sort_by(&merge_precedence/1)
    |> Enum.group_by(fn {path, _code, _value} -> hd(path) end, &alt_content/1)
    |> Enum.map(fn {key, contents} -> {key, LMap.merge_map_list(contents)} end)
    |> Map.new()
  end

  defp alt_path({code, value}, normalizer_fun) do
    case String.split(code, ~r/(_alt_|_menu_)/, include_captures: true) do
      [lang] ->
        {[normalizer_fun.(lang)], lang, value}

      [lang, "_alt_", "menu"] ->
        {[normalizer_fun.(lang), "_menu_", "alt"], lang, value}

      [lang, alt, alt_value] ->
        {[normalizer_fun.(lang), alt, alt_value], lang, value}
    end
  end

  # Several source codes can normalize onto one key: CLDR names `fil` and its
  # deprecated alias `tl`, and `ak` and `tw`, and all four are display names in
  # every locale. `merge_map_list/1` takes the last of them, so the arrival
  # order picks the winner — and mapping straight over the source map left that
  # to the map's internal order, which differs between OTP releases. A 668-key
  # language map is a hashmap, so the same CLDR data gave `fil` the alias's
  # "Tagalog" on OTP 28 and "Filipino" on OTP 29, while `ak` took `tw`'s "Twi"
  # on both and shipped that way.
  #
  # Sorting makes the order the data's rather than the runtime's, and ordering
  # the entry whose own code is the key last makes that one win: `fil` is
  # "Filipino" and `ak` is "Akan", not the names of the codes CLDR retired in
  # their favour.
  defp merge_precedence({[key | _rest], code, _value}), do: {code == key, code}

  defp alt_content({[_key], _code, value}), do: %{"default" => value}
  defp alt_content({[_key, "_alt_", alt], _code, value}), do: %{alt => value}
  defp alt_content({[_key, "_menu_", menu], _code, value}), do: %{"menu" => %{menu => value}}

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
