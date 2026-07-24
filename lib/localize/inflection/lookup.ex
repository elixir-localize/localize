defmodule Localize.Inflection.Lookup do
  @moduledoc false

  # Port of the upstream `DictionaryLookupFunction`: determines the
  # value of one grammatical category (such as number or gender) for
  # a word or phrase from the dictionary, with optional
  # part-of-speech disambiguation.

  alias Localize.Inflection.{Dictionary, Tokenizer}

  import Bitwise

  @doc """
  Determines the single grammeme of `word` within the category
  masked by `tags`, or "" when unknown or ambiguous.

  ### Options

  * `:disambiguation` is a list of part-of-speech grammeme names in
    priority order. When given, ambiguous words are resolved by
    grouping readings by part of speech.

  """
  def determine(locale, word, tags, options \\ []) do
    mask = Dictionary.binary_properties(locale, tags) || 0
    disambiguation = Keyword.get(options, :disambiguation, [])
    properties = Dictionary.combined_grammemes(locale, word) || 0

    if disambiguation != [] and not single_bit?(properties) do
      determine_with_disambiguation(locale, word, mask, disambiguation)
    else
      masked_name(locale, properties &&& mask)
    end
  end

  @doc """
  Determines the category value for a phrase. When the phrase is
  unknown, the first relevant word (or first word) decides when
  `first_word_determines?` is true.

  """
  def determine_phrase(locale, phrase, tags, first_word_determines?, options \\ []) do
    mask = Dictionary.binary_properties(locale, tags) || 0
    properties = Dictionary.combined_grammemes(locale, phrase) || 0

    cond do
      single_bit?(properties) ->
        masked_name(locale, properties &&& mask)

      properties == 0 ->
        determine_unknown_phrase(locale, phrase, mask, first_word_determines?, options)

      true ->
        determine_with_disambiguation(
          locale,
          phrase,
          mask,
          Keyword.get(options, :disambiguation, [])
        )
    end
  end

  defp determine_unknown_phrase(locale, phrase, mask, first_word_determines?, options) do
    tokens = Tokenizer.word_tokens(locale, phrase)

    if length(tokens) > 1 do
      first_relevant = find_relevant_token(locale, tokens, mask, first_word_determines?)

      result =
        (first_relevant && determine_word(locale, first_relevant.value, mask, options)) || ""

      first_word = List.first(tokens)

      if result == "" and first_word do
        determine_word(locale, first_word.value, mask, options)
      else
        result
      end
    else
      ""
    end
  end

  defp find_relevant_token(locale, tokens, mask, first_word_determines?) do
    Enum.reduce_while(tokens, nil, fn token, acc ->
      properties = Dictionary.combined_grammemes(locale, token.clean) || 0

      cond do
        (properties &&& mask) == 0 -> {:cont, acc}
        first_word_determines? -> {:halt, token}
        true -> {:cont, acc || token}
      end
    end)
  end

  defp determine_word(locale, word, mask, options) do
    properties = Dictionary.combined_grammemes(locale, word) || 0
    disambiguation = Keyword.get(options, :disambiguation, [])

    if disambiguation != [] and not single_bit?(properties) do
      determine_with_disambiguation(locale, word, mask, disambiguation)
    else
      masked_name(locale, properties &&& mask)
    end
  end

  @doc """
  Resolves an ambiguous word by grouping its readings by the
  disambiguation parts of speech, in priority order, and returning
  the single category value of the first non-empty group.

  """
  def determine_with_disambiguation(locale, word, mask, disambiguation) do
    case Dictionary.grammeme_sets(locale, word) do
      [] ->
        ""

      sets ->
        pos_masks =
          for name <- disambiguation, do: Dictionary.binary_properties(locale, [name]) || 0

        buckets = List.duplicate(0, length(pos_masks) + 1)

        buckets =
          Enum.reduce(sets, buckets, fn properties, buckets ->
            index =
              Enum.find_index(pos_masks, fn pos -> (properties &&& pos) != 0 end) ||
                length(pos_masks)

            List.update_at(buckets, index, &(&1 ||| properties))
          end)

        Enum.find_value(buckets, "", fn bucket ->
          if bucket != 0, do: masked_name(locale, bucket &&& mask)
        end)
    end
  end

  defp masked_name(locale, masked) do
    Dictionary.property_name(locale, masked) || ""
  end

  defp single_bit?(0), do: false
  defp single_bit?(mask), do: (mask &&& mask - 1) == 0
end
