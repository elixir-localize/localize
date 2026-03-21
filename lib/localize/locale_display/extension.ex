defmodule Localize.LocaleDisplay.Extension do
  @moduledoc false

  import Localize.LocaleDisplay, only: [join_field_values: 2]

  # # display_name/3
  #
  # Returns a display name for generic extensions (not U or T).
  #
  # ### Arguments
  #
  # * `extensions` is a map of extension key => value pairs.
  #
  # * `locale_id` is a locale identifier atom.
  #
  # * `display_names` is the display names data map.
  #
  # ### Returns
  #
  # * A formatted string, or `[]` if no extensions.
  #
  def display_name(extensions, _locale_id, display_names) do
    key_type_pattern = get_in(display_names, [:locale_display_pattern, :locale_key_type_pattern])

    extensions
    |> Enum.sort()
    |> Enum.map(fn
      {"x", private_use} ->
        value_names = Enum.join(private_use, "-")
        Localize.Substitution.substitute(["x", value_names], key_type_pattern)

      {extension, key_value_pairs} when is_list(key_value_pairs) ->
        value_names =
          key_value_pairs
          |> Enum.chunk_every(2)
          |> Enum.map(fn [key, value] -> "#{key}-#{value}" end)
          |> join_field_values(display_names)

        Localize.Substitution.substitute([extension, value_names], key_type_pattern)

      {extension, value} when is_binary(value) ->
        Localize.Substitution.substitute([extension, value], key_type_pattern)
    end)
    |> join_field_values(display_names)
  end
end
