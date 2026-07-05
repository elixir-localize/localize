defmodule Localize.Validity.U do
  @moduledoc false

  alias Localize.Validity.U.Fields

  # Map BCP47 string keys to their atom equivalents.
  # The struct fields use the original BCP47 key names.
  @field_mapping Fields.field_mapping()

  # The validity data is embedded at compile time, so an ETF
  # regeneration must trigger recompilation of this module.
  @external_resource Application.app_dir(:localize, "priv/localize/validity/validity_u.etf")
  @validity_data Localize.SupplementalData.validity(:u)
  @dont_process_keys ["vt", "rg", "sd", "dx", "kr"]
  @valid_keys Map.keys(@validity_data)
  @process_keys @valid_keys -- @dont_process_keys

  @region_subtag_filler "zzzz"

  @doc false
  def fields, do: Fields.fields()

  def field_mapping, do: Fields.field_mapping()

  @doc """
  Decodes and validates that a given value is valid
  for a given key.

  Returns both the canonical key
  and the canonical value or an error.

  """
  # Struct-field atom keys (`:ca`) are accepted alongside the BCP 47
  # string keys (`"ca"`) so consumers of `Localize.LanguageTag.U`
  # can decode with the same keys the struct uses.
  def decode(key, value) when is_atom(key) do
    decode(unmap(key), value)
  end

  @dont_atomize ["tz", "rg", "sd", "kr", "vt"]
  def decode(key, value) when key in @dont_atomize do
    case valid(key, value) do
      {:ok, value} ->
        {:ok, {map(key), value}}

      {:error, _value} ->
        {:error, invalid_value_error(key, value)}
    end
  end

  def decode(key, value) do
    case valid(key, value) do
      {:ok, value} ->
        {:ok, {map(key), atomize(value)}}

      {:error, _value} ->
        {:error, invalid_value_error(key, value)}
    end
  end

  @doc """
  Encodes a key and value into the
  form required for a string version
  of a language tag.

  """

  def encode(key, value) when is_binary(key) do
    encode(map(key), value)
  end

  # Calendar names may be compound like
  # islamic-rgsa
  def encode(:ca = key, value) do
    unmapped_key = unmap(key)

    value =
      unmapped_key
      |> encode_key(value)
      |> String.replace("_", "-")

    {unmapped_key, value}
  end

  def encode(key, value) do
    unmapped_key = unmap(key)
    {unmapped_key, encode_key(unmapped_key, value)}
  end

  # Encode key functions take the form that is
  # in the language tag locale struct and encodes it
  # back to what is required in a textual form of
  # the locale.

  # Deprecated spellings decode (see `get_value/3`) but are never
  # encode candidates: `:islamic_civil` encodes as "islamic-civil",
  # not the deprecated "islamicc".
  for {key, values} <- @validity_data, key in @process_keys do
    inverted_values =
      Enum.map(values, fn
        {_k, {:deprecated, _preferred}} -> []
        {k, v} when is_list(v) -> Enum.map(v, fn tz -> {tz, k} end)
        {k, nil} -> {String.to_atom(k), k}
        {k, v} -> {String.to_atom(v), k}
      end)
      |> Elixir.List.flatten()
      |> Map.new()

    defp encode_key(unquote(key), value) when value in unquote(Map.keys(inverted_values)) do
      unquote(Macro.escape(inverted_values))
      |> Map.fetch!(value)
    end
  end

  defp encode_key("cu", value) do
    value
    |> Atom.to_string()
    |> String.downcase()
  end

  # An `rg` region override is a 2-letter region suffixed with "zzzz"
  # (e.g. `:US` → "uszzzz"). A subdivision override (e.g. `:gbeng` for
  # GB-ENG) is emitted as-is — appending the filler would corrupt it into
  # an unresolvable value like "gbengzzzz".
  defp encode_key("rg", value) when is_atom(value) do
    encoded =
      value
      |> Atom.to_string()
      |> String.downcase()

    if String.length(encoded) == 2 do
      encoded <> @region_subtag_filler
    else
      encoded
    end
  end

  defp encode_key("rg", value) do
    value
  end

  defp encode_key("sd", value) do
    to_string(value)
  end

  defp encode_key("vt", value) do
    value
    |> String.downcase()
  end

  defp encode_key("kr", values) when is_list(values) do
    values
    |> Enum.map(&to_string/1)
    |> Enum.map_join("-", &String.downcase/1)
  end

  defp encode_key("dx", value) when is_atom(value) do
    value
    |> Atom.to_string()
    |> String.downcase()
  end

  defp encode_key("dx", values) when is_list(values) do
    values
    |> Enum.map(&to_string/1)
    |> Enum.map_join("-", &String.downcase/1)
  end

  # valid function check that the value provided
  # is acceptable for the given key.

  for {key, values} <- @validity_data, key in (@process_keys -- ["tz"]) do
    defp valid(unquote(key), value) when value in unquote(Map.keys(values)) do
      unquote(Macro.escape(values))
      |> get_value(unquote(key), value)
      |> maybe_get_list_head()
      |> wrap(:ok)
    end
  end

  # For timezones a nil value means its an acceptable
  # time zone name but it needs to be resolved to its
  # canonical version. For example, est5edt becomes usnyc
  @tz_values @validity_data["tz"]
  defp valid("tz", value) do
    case Map.fetch(@tz_values, value) do
      # A deprecated timezone id carries its preferred replacement
      # directly; resolve through the replacement's alias list.
      {:ok, {:deprecated, preferred}} ->
        case Map.fetch(@tz_values, preferred) do
          {:ok, values} when is_list(values) -> {:ok, hd(values)}
          _ -> {:ok, preferred}
        end

      {:ok, values} when is_list(values) ->
        {:ok, hd(values)}
    end
  end

  # Calendar names may be compound like
  # islamic-rgsa
  defp valid("ca", values) when is_list(values) do
    valid("ca", Enum.join(values, "_"))
  end

  # The canonical BCP 47 spelling of compound calendar values is
  # hyphenated ("islamic-civil"); the validity data stores them
  # underscored. Accept the hyphenated form directly so decode/2
  # round-trips encode/2 output.
  defp valid("ca", value) when is_binary(value) do
    case String.replace(value, "-", "_") do
      ^value -> {:error, value}
      underscored -> valid("ca", underscored)
    end
  end

  # Codepoints?
  defp valid("vt", value) do
    {:ok, value}
  end

  defp valid("rg", <<value::binary-size(2), "#{@region_subtag_filler}">>) do
    case Localize.Validity.Territory.validate(value) do
      {:ok, territory, _status} -> {:ok, territory}
      other -> other
    end
  end

  defp valid("rg", value) do
    case Localize.Validity.Subdivision.validate(value) do
      {:ok, subdivision, _status} -> {:ok, subdivision}
      other -> other
    end
  end

  defp valid("sd", value) do
    case Localize.Validity.Subdivision.validate(value) do
      {:ok, subdivision, _status} -> {:ok, subdivision}
      other -> other
    end
  end

  # dx can be more than one script
  defp valid("dx", value) when is_binary(value) do
    case Localize.Validity.Script.validate(value) do
      {:ok, script, _status} -> {:ok, script}
      other -> other
    end
  end

  defp valid("dx" = key, values) when is_list(values) do
    Enum.reduce_while(values, {:ok, []}, fn value, {:ok, acc} ->
      case Localize.Validity.Script.validate(value) do
        {:ok, script, _status} -> {:cont, {:ok, [script | acc]}}
        {:error, _script} -> {:halt, {:error, invalid_value_error(key, value)}}
      end
    end)
  end

  @kr_valid_values @validity_data["kr"] |> Map.delete("REORDER_CODE")
  defp valid("kr", value) when is_binary(value) do
    if Map.has_key?(@kr_valid_values, value) do
      {:ok, [atomize(value)]}
    else
      case Localize.Validity.Script.validate(value) do
        {:ok, script, _status} -> {:ok, [script]}
        other -> other
      end
    end
  end

  defp valid("kr" = key, values) when is_list(values) do
    Enum.reduce_while(values, {:ok, []}, fn value, {:ok, acc} ->
      case valid("kr", value) do
        {:ok, [reorder_code]} -> {:cont, {:ok, [reorder_code | acc]}}
        {:error, _reorder_code} -> {:halt, {:error, invalid_value_error(key, value)}}
      end
    end)
    |> case do
      {:ok, list} -> {:ok, Enum.reverse(list)}
      other -> other
    end
  end

  defp valid(key, value) when key in @valid_keys do
    {:error, invalid_value_error(key, value)}
  end

  defp valid(key, _value) do
    {:error, invalid_key_error(key)}
  end

  defp get_value(values_map, "cu", value) do
    case Map.get(values_map, value) do
      {:deprecated, preferred} -> String.upcase(preferred)
      nil -> String.upcase(value)
      other -> String.upcase(other)
    end
  end

  defp get_value(map, _key, value) do
    case Map.get(map, value) do
      {:deprecated, preferred} -> preferred
      nil -> value
      other -> other
    end
  end

  defp map(key) do
    Map.fetch!(@field_mapping, key)
  end

  defp unmap(key) when is_atom(key) do
    Atom.to_string(key)
  end

  defp wrap(term, atom) do
    {atom, term}
  end

  defp maybe_get_list_head([head | _rest]) do
    head
  end

  defp maybe_get_list_head(other) do
    other
  end

  defp atomize(value) when is_atom(value) do
    value
  end

  defp atomize(value) when is_binary(value) do
    String.to_atom(value)
  end

  defp atomize(other) do
    other
  end

  @doc false
  def invalid_value_error(key, value) do
    Localize.InvalidSubtagError.exception(key: key, value: value, reason: nil)
  end

  @doc false
  def invalid_key_error(key) do
    Localize.InvalidSubtagError.exception(
      key: key,
      value: nil,
      reason: :invalid_key
    )
  end
end
