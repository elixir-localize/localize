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
  @type territory :: atom() | nil

  @typedoc "A locale identifier as an atom."
  @type locale_id :: atom()

  @doc """
  Convert a POSIX locale identifier to a BCP 47 locale identifier
  by replacing underscores with hyphens.

  ### Arguments

  * `locale_id` is a string locale identifier, potentially
    in POSIX format using underscores.

  ### Returns

  * A string with underscores replaced by hyphens.

  ### Examples

      iex> Localize.Locale.locale_id_from_posix("en_US")
      "en-US"

      iex> Localize.Locale.locale_id_from_posix("zh_Hant_TW")
      "zh-Hant-TW"

      iex> Localize.Locale.locale_id_from_posix("en")
      "en"

  """
  @spec locale_id_from_posix(String.t()) :: String.t()
  def locale_id_from_posix(locale_id) when is_binary(locale_id) do
    String.replace(locale_id, "_", "-")
  end

  @doc """
  Build a locale identifier string from its component parts.

  Assembles a BCP 47 locale identifier from language, script,
  territory, and variant subtags, omitting nil components.

  ### Arguments

  * `language` is a language subtag (string or atom).

  * `script` is an optional script subtag (string, atom, or nil).

  * `territory` is an optional territory subtag (string, atom, or nil).

  * `variants` is a list of variant subtag strings.

  ### Returns

  * A BCP 47 locale identifier string.

  ### Examples

      iex> Localize.Locale.locale_id_from(:en, nil, :US, [])
      "en-US"

      iex> Localize.Locale.locale_id_from(:zh, :Hant, :TW, [])
      "zh-Hant-TW"

      iex> Localize.Locale.locale_id_from(:en, nil, nil, [])
      "en"

  """
  @spec locale_id_from(language(), script(), territory(), [String.t()]) :: String.t()
  def locale_id_from(language, script, territory, variants) do
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
