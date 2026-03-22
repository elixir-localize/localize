defmodule Localize.LocaleDisplay.T do
  @moduledoc false

  import Localize.LocaleDisplay,
    only: [get_display_preference: 2, join_field_values: 2, replace_parens_with_brackets: 1]

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

    # Get T extension fields, excluding h0 (handled specially)
    fields = get_fields(transform)

    for {_key, field} <- fields, !is_nil(value = get_field(transform, field)) do
      format_key_value(field, value, transform, locale_id, display_names, prefer)
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

  def format_key_value(field, value, transform, locale_id, display_names, prefer) do
    canonical_value = canonicalize_value(field, value)

    if value_name = get_type(field, canonical_value, display_names) do
      replace_parens_with_brackets(value_name)
    else
      key_name = get_in(display_names, [:keys, field])
      display_value(field, key_name, canonical_value, transform, locale_id, display_names, prefer)
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
    |> safe_to_atom()
  end

  defp canonicalize_value(_field, value), do: value

  defp safe_to_atom(string) when is_binary(string) do
    String.to_existing_atom(string)
  rescue
    ArgumentError -> string
  end

  defp display_value(:language, _key_name, value, transform, locale_id, display_names, prefer) do
    h0 = get_field(transform, :h0) || Map.get(transform, "h0")

    key_name =
      if h0 == :hybrid or h0 == "hybrid" do
        get_in(display_names, [:types, :h0, :hybrid])
      else
        get_in(display_names, [:keys, :t])
      end

    value_name =
      value
      |> Localize.LocaleDisplay.display_name!(prefer: prefer, locale: locale_id)
      |> replace_parens_with_brackets()

    if key_name do
      display_pattern = get_in(display_names, [:locale_display_pattern, :locale_key_type_pattern])
      Localize.Substitution.substitute([key_name, value_name], display_pattern)
    else
      value_name
    end
  end

  defp display_value(_key, nil, value, _transform, _locale_id, _display_names, _prefer)
       when is_binary(value) do
    replace_parens_with_brackets(value)
  end

  defp display_value(_key, nil, value, _transform, _locale_id, _display_names, _prefer)
       when is_atom(value) do
    value |> to_string() |> replace_parens_with_brackets()
  end

  defp display_value(key, key_name, value, transform, locale_id, display_names, prefer) do
    value_name =
      key
      |> get_special(key_name, value, transform, locale_id, display_names)
      |> Kernel.||(value)
      |> get_display_preference(prefer)
      |> :erlang.iolist_to_binary()
      |> replace_parens_with_brackets()

    display_pattern = get_in(display_names, [:locale_display_pattern, :locale_key_type_pattern])
    Localize.Substitution.substitute([key_name, value_name], display_pattern)
  end

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
end
