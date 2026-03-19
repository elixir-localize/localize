defmodule Localize.Locale do
  @moduledoc """
  Provides locale utility functions for working with
  BCP 47 language tags and POSIX locale identifiers.

  This module contains functions previously delegated to
  `Cldr.Locale`, adapted for use within the `Localize`
  library without external dependencies.

  """

  @typedoc "A BCP 47 language subtag as an atom."
  @type language :: atom() | nil

  @typedoc "A BCP 47 script subtag as an atom."
  @type script :: atom() | nil

  @typedoc "A BCP 47 region/territory subtag as an atom."
  @type territory_code :: atom() | nil

  @typedoc "A locale name as an atom."
  @type locale_name :: atom()

  @doc """
  Convert a POSIX locale name to a BCP 47 locale name
  by replacing underscores with hyphens.

  ### Arguments

  * `locale_name` is a string locale identifier, potentially
    in POSIX format using underscores.

  ### Returns

  * A string with underscores replaced by hyphens.

  ### Examples

      iex> Localize.Locale.locale_name_from_posix("en_US")
      "en-US"

      iex> Localize.Locale.locale_name_from_posix("zh_Hant_TW")
      "zh-Hant-TW"

      iex> Localize.Locale.locale_name_from_posix("en")
      "en"

  """
  @spec locale_name_from_posix(String.t()) :: String.t()
  def locale_name_from_posix(locale_name) when is_binary(locale_name) do
    String.replace(locale_name, "_", "-")
  end

  @doc """
  Build a locale name string from its component parts.

  Assembles a BCP 47 locale name from language, script,
  territory, and variant subtags, omitting nil components.

  ### Arguments

  * `language` is a language subtag (string or atom).

  * `script` is an optional script subtag (string, atom, or nil).

  * `territory` is an optional territory subtag (string, atom, or nil).

  * `variants` is a list of variant subtag strings.

  ### Returns

  * A BCP 47 locale name string.

  ### Examples

      iex> Localize.Locale.locale_name_from(:en, nil, :US, [])
      "en-US"

      iex> Localize.Locale.locale_name_from(:zh, :Hant, :TW, [])
      "zh-Hant-TW"

      iex> Localize.Locale.locale_name_from(:en, nil, nil, [])
      "en"

  """
  @spec locale_name_from(language(), script(), territory_code(), [String.t()]) :: String.t()
  def locale_name_from(language, script, territory, variants) do
    [to_string(language)]
    |> maybe_append(script)
    |> maybe_append(territory)
    |> append_variants(variants)
    |> Enum.join("-")
  end

  defp maybe_append(parts, nil), do: parts
  defp maybe_append(parts, value), do: parts ++ [to_string(value)]

  defp append_variants(parts, []), do: parts
  defp append_variants(parts, variants), do: parts ++ Enum.map(variants, &to_string/1)
end
