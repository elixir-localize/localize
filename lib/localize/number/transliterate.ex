defmodule Localize.Number.Transliterate do
  @moduledoc """
  Functions to transliterate digits between number systems.

  Transliteration replaces each digit character in a string with
  the corresponding digit from another number system using a
  precomputed mapping.

  """

  @doc """
  Transliterates digit characters in a string using a
  transliteration map.

  Non-digit characters (separators, signs, etc.) are passed
  through unchanged.

  ### Arguments

  * `string` is the string containing digits to transliterate.

  * `transliteration_map` is a map of `%{from_grapheme => to_grapheme}`.

  ### Returns

  * A new string with digits replaced according to the map.

  ### Examples

      iex> map = %{"0" => "٠", "1" => "١", "2" => "٢", "3" => "٣"}
      iex> Localize.Number.Transliterate.transliterate_digits("123", map)
      "١٢٣"

  """
  @spec transliterate_digits(String.t(), map()) :: String.t() | {:error, Exception.t()}
  def transliterate_digits(string, transliteration_map)
      when is_binary(string) and is_map(transliteration_map) do
    string
    |> String.graphemes()
    |> Enum.map_join(fn grapheme ->
      Map.get(transliteration_map, grapheme, grapheme)
    end)
  end

  def transliterate_digits(string, transliteration_map) when is_binary(string),
    do: {:error, Localize.Utils.Helpers.invalid_value(transliteration_map, "a map of digits")}

  def transliterate_digits(string, _transliteration_map),
    do: {:error, Localize.Utils.Helpers.invalid_value(string, "a string")}
end
