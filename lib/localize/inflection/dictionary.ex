defmodule Localize.Inflection.Dictionary do
  @moduledoc """
  Low-level access to the lexical dictionary for a locale.

  Words map to grammatical properties (grammemes) represented as
  integer bitmasks, and to the inflection patterns they belong to.
  This module mirrors the upstream `DictionaryMetaData` and
  `DictionaryExposableMorphology` APIs.

  """

  alias Localize.Inflection.Data

  import Bitwise

  @doc """
  Returns the combined grammeme bitmask for a surface form, or nil
  if the word is not in the dictionary.

  ### Arguments

  * `locale` is any locale atom for which data has been generated.

  * `word` is the surface form to look up.

  ### Returns

  * The combined bitmask of all grammemes of all readings of
    `word`, or nil if `word` is unknown.

  ### Examples

      iex> mask = Localize.Inflection.Dictionary.combined_grammemes(:en, "cats")
      iex> Enum.sort(Localize.Inflection.Dictionary.property_names(:en, mask))
      ["consonant-start", "noun", "plural", "present", "simple", "singular", "third", "verb"]

      iex> Localize.Inflection.Dictionary.combined_grammemes(:en, "xyzzy")
      nil

  """
  def combined_grammemes(locale, word) do
    case Data.lookup(locale, word) do
      {mask, _patterns} -> mask
      nil -> nil
    end
  end

  @doc """
  Returns the combined bitmask for a list of grammeme names.

  Names unknown to the locale are skipped, as upstream: the Arabic
  definiteness lookup asks for "definite" although no dictionary
  entry carries it. Returns nil when none of the names are known.

  ### Examples

      iex> mask = Localize.Inflection.Dictionary.binary_properties(:en, ["noun", "plural"])
      iex> Localize.Inflection.Dictionary.has_all_properties?(:en, "cats", mask)
      true

      iex> Localize.Inflection.Dictionary.binary_properties(:en, ["not-a-grammeme"])
      nil

  """
  def binary_properties(locale, names) when is_list(names) do
    bits = Data.metadata!(locale).grammeme_bits

    mask =
      Enum.reduce(names, 0, fn name, acc ->
        case Map.fetch(bits, name) do
          {:ok, bit} -> acc ||| 1 <<< bit
          :error -> acc
        end
      end)

    if mask == 0, do: nil, else: mask
  end

  @doc """
  Returns the grammeme name for a mask with exactly one bit set,
  or nil otherwise.

  ### Examples

      iex> mask = Localize.Inflection.Dictionary.binary_properties(:en, ["plural"])
      iex> Localize.Inflection.Dictionary.property_name(:en, mask)
      "plural"

  """
  def property_name(_locale, 0), do: nil

  def property_name(locale, mask) when is_integer(mask) do
    if single_bit?(mask) do
      names = Data.metadata!(locale).grammeme_names
      elem(names, bit_index(mask))
    end
  end

  @doc """
  Returns the list of grammeme names present in `mask`.

  """
  def property_names(locale, mask) when is_integer(mask) do
    names = Data.metadata!(locale).grammeme_names

    for bit <- 0..(tuple_size(names) - 1), (mask >>> bit &&& 1) == 1 do
      elem(names, bit)
    end
  end

  @doc """
  Returns true if the word has all the properties in `mask`.

  """
  def has_all_properties?(locale, word, mask) do
    case combined_grammemes(locale, word) do
      nil -> false
      combined -> (combined &&& mask) == mask
    end
  end

  @doc """
  Returns the inflection patterns for a word as a list of pattern
  maps, or [] if the word is unknown or uninflectable.

  """
  def patterns_for_word(locale, word) do
    case Data.lookup(locale, word) do
      {_mask, pattern_indexes} ->
        patterns = Data.metadata!(locale).patterns
        Enum.map(pattern_indexes, &elem(patterns, &1))

      nil ->
        []
    end
  end

  @doc """
  Returns the grammeme bitmask sets for each reading of a word.

  A word that belongs to inflection patterns gets one grammeme set
  per matching inflection row (the row grammemes combined with the
  pattern part of speech). A word without patterns returns its
  combined grammemes as the single set. Unknown words return [].

  """
  def grammeme_sets(locale, word) do
    case Data.lookup(locale, word) do
      nil ->
        []

      {combined, []} ->
        [combined]

      {combined, pattern_indexes} ->
        patterns = Data.metadata!(locale).patterns

        sets =
          Enum.flat_map(pattern_indexes, fn index ->
            pattern = elem(patterns, index)

            case pattern.inflections do
              [] ->
                [pattern.pos_mask]

              _inflections ->
                word
                |> matching_inflections(combined, pattern)
                |> Enum.map(fn {grammemes, _suffix} -> grammemes ||| pattern.pos_mask end)
            end
          end)

        if sets == [], do: [combined], else: sets
    end
  end

  @doc """
  Returns the inflection rows of `pattern` that could have produced
  `surface_form` given the word's combined grammemes.

  Only rows whose grammemes are a subset of `from_grammemes` and
  whose suffix is a suffix of the surface form qualify; among those,
  only the rows with the longest matching suffix are returned.

  """
  def matching_inflections(surface_form, from_grammemes, pattern) do
    {matches, _max_length} =
      Enum.reduce(pattern.inflections, {[], -1}, fn {grammemes, suffix} = inflection,
                                                    {matches, max_length} = acc ->
        length = byte_size(suffix)

        cond do
          (from_grammemes &&& grammemes) != grammemes -> acc
          length < max_length or not String.ends_with?(surface_form, suffix) -> acc
          length > max_length -> {[inflection], length}
          true -> {[inflection | matches], max_length}
        end
      end)

    Enum.reverse(matches)
  end

  defp single_bit?(mask), do: (mask &&& mask - 1) == 0

  defp bit_index(mask), do: bit_index(mask, 0)
  defp bit_index(1, index), do: index
  defp bit_index(mask, index), do: bit_index(mask >>> 1, index + 1)
end
