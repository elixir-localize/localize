defmodule Localize.Inflection.Inflector do
  @moduledoc """
  Inflects words to a target set of grammatical constraints using
  the lexical dictionary and its inflection patterns.

  This module mirrors the upstream `Inflector_InflectionPattern`,
  `MorphologicalAnalyzer` and `DictionaryLookupInflector` behavior:
  a word's candidate readings are ranked (optionally biased by
  disambiguation grammemes and per-language priority tables) and the
  best matching inflection row supplies the replacement suffix.

  """

  # The per-language synthesizers and conformance harnesses are ported
  # from the upstream C++ linguistic rule tables; their branchiness and
  # nesting mirror the reference implementation they are verified
  # against (see guides/inflection.md).
  # credo:disable-for-this-file Credo.Check.Refactor.CyclomaticComplexity
  # credo:disable-for-this-file Credo.Check.Refactor.Nesting

  alias Localize.Inflection.{Data, Dictionary}

  import Bitwise

  @doc """
  Inflects a word to the given constraints.

  ### Arguments

  * `locale` is any locale atom for which data has been generated.

  * `word` is the word to inflect.

  * `word_grammemes` is the combined grammeme mask for `word` (from
    `Localize.Inflection.Dictionary.combined_grammemes/2`).

  * `constraints` is a list of grammeme names to inflect to, such
    as `["plural"]`.

  ### Options

  * `:disambiguation` is a list of grammeme names used to prefer
    readings, in priority order (for example `["noun"]`).

  * `:optional_constraints` is a list of grammeme names preferred
    but not required in the target inflection row.

  * `:priorities` is a list of grammeme-name lists used to rank
    readings when disambiguation does not decide, mirroring the
    upstream per-language priority tables.

  * `:fallback` when true (the default) tries further readings when
    the best reading cannot be inflected.

  ### Returns

  * `{:ok, inflected}` or `:error` when the word cannot be
    inflected to the constraints.

  ### Examples

      iex> grammemes = Localize.Inflection.Dictionary.combined_grammemes(:en, "cat")
      iex> Localize.Inflection.Inflector.inflect(:en, "cat", grammemes, ["plural"])
      {:ok, "cats"}

  """
  def inflect(locale, word, word_grammemes, constraints, options \\ []) do
    if Enum.all?(constraints, &(&1 in [nil, ""])) do
      {:ok, word}
    else
      all_caps? = all_caps?(word)

      result =
        if all_caps? do
          :error
        else
          inflect_word(locale, word, word_grammemes, constraints, options)
        end

      with :error <- result,
           lowercased = String.downcase(word),
           {:ok, inflected} <-
             inflect_word(locale, lowercased, word_grammemes, constraints, options) do
        {:ok, match_case(word, inflected, all_caps?)}
      end
    end
  end

  @doc """
  Inflects a word without trying case variants.

  See `inflect/5` for arguments and options.

  """
  def inflect_word(_locale, _word, 0, _constraints, _options), do: :error
  def inflect_word(_locale, _word, nil, _constraints, _options), do: :error

  def inflect_word(locale, word, word_grammemes, constraints, options) do
    case Dictionary.patterns_for_word(locale, word) do
      [] ->
        :error

      patterns ->
        candidates = candidate_readings(locale, word, word_grammemes, patterns, options)
        to_mask = Dictionary.binary_properties(locale, constraints) || 0

        optional_masks =
          for name <- Keyword.get(options, :optional_constraints, []),
              do: Dictionary.binary_properties(locale, [name]) || 0

        fallback? = Keyword.get(options, :fallback, true)
        tie_break = Keyword.get(options, :tie_break, :first)
        try_candidates(candidates, to_mask, optional_masks, word, fallback?, tie_break)
    end
  end

  defp try_candidates([], _to_mask, _optional_masks, _word, _fallback?, _tie_break), do: :error

  defp try_candidates([candidate | rest], to_mask, optional_masks, word, fallback?, tie_break) do
    case candidate do
      {_grammemes, nil, _pattern} ->
        {:ok, word}

      {grammemes, _inflection, pattern} ->
        case reinflect(pattern, grammemes, to_mask, optional_masks, word, tie_break) do
          {:ok, inflected} ->
            {:ok, inflected}

          :error ->
            if fallback? do
              try_candidates(rest, to_mask, optional_masks, word, fallback?, tie_break)
            else
              :error
            end
        end
    end
  end

  @doc """
  Reinflects a surface form within one pattern from its current
  grammemes to the target constraint mask.

  Returns `{:ok, inflected}` or `:error` when the pattern has no
  row satisfying the constraints.

  """
  def reinflect(
        pattern,
        from_grammemes,
        to_mask,
        optional_masks \\ [],
        surface_form,
        tie_break \\ :first
      )

  def reinflect(_pattern, _from, 0, _optional, surface_form, _tie_break), do: {:ok, surface_form}

  def reinflect(pattern, from_grammemes, to_mask, optional_masks, surface_form, tie_break) do
    if contains_all?(from_grammemes, to_mask) do
      {:ok, surface_form}
    else
      to_bit_count = bit_count(to_mask)

      {strip_length, best} =
        Enum.reduce(pattern.inflections, {0, nil}, fn {grammemes, suffix}, {strip, best} ->
          strip = update_strip(strip, grammemes, suffix, from_grammemes, surface_form)

          best =
            update_best(
              best,
              grammemes,
              suffix,
              from_grammemes,
              to_mask,
              to_bit_count,
              optional_masks,
              tie_break
            )

          {strip, best}
        end)

      case best do
        nil ->
          :error

        {_score, suffix} ->
          stem = binary_part(surface_form, 0, byte_size(surface_form) - strip_length)
          {:ok, stem <> suffix}
      end
    end
  end

  defp update_strip(strip, grammemes, suffix, from_grammemes, surface_form) do
    if (from_grammemes == 0 or contains_all?(from_grammemes, grammemes)) and
         byte_size(suffix) > strip and String.ends_with?(surface_form, suffix) do
      byte_size(suffix)
    else
      strip
    end
  end

  defp update_best(
         best,
         grammemes,
         suffix,
         from_grammemes,
         to_mask,
         to_bit_count,
         optional_masks,
         tie_break
       ) do
    if contains_all?(grammemes, to_mask) do
      score = {
        optional_score(grammemes, optional_masks),
        bit_count(grammemes &&& from_grammemes),
        to_bit_count - bit_count(grammemes)
      }

      better? =
        case {best, tie_break} do
          {nil, _tie} -> true
          {{best_score, _}, :last} -> score >= best_score
          {{best_score, _}, _first} -> score > best_score
        end

      if better?, do: {score, suffix}, else: best
    else
      best
    end
  end

  defp candidate_readings(locale, word, word_grammemes, patterns, options) do
    ignore_masks =
      for set <- Keyword.get(options, :ignore, []),
          mask = Dictionary.binary_properties(locale, set) || 0,
          mask != 0,
          do: mask

    disambiguation_masks =
      for name <- Keyword.get(options, :disambiguation, []),
          do: Dictionary.binary_properties(locale, [name]) || 0

    priority_tables =
      for table <- Keyword.get(options, :priorities, []) do
        for names <- table, do: Dictionary.binary_properties(locale, [names]) || 0
      end

    candidates =
      Enum.flat_map(patterns, fn pattern ->
        case pattern.inflections do
          [] ->
            [{pattern.pos_mask, nil, pattern}]

          _inflections ->
            word
            |> Dictionary.matching_inflections(word_grammemes, pattern)
            |> Enum.map(fn {grammemes, _suffix} = inflection ->
              {grammemes ||| pattern.pos_mask, inflection, pattern}
            end)
        end
      end)

    candidates =
      Enum.reject(candidates, fn {grammemes, _inflection, _pattern} ->
        Enum.any?(ignore_masks, fn mask -> (grammemes &&& mask) == mask end)
      end)

    Enum.sort_by(candidates, &reading_sort_key(&1, disambiguation_masks, priority_tables))
  end

  # Readings without an inflection row sort last; fewer grammemes
  # and larger patterns are preferred, as upstream.
  defp reading_sort_key({grammemes, inflection, pattern}, disambiguation_masks, priority_tables) do
    disambiguation = -disambiguation_score(grammemes, disambiguation_masks)

    priorities =
      for table <- priority_tables do
        Enum.find_index(table, &contains_all?(grammemes, &1)) || length(table)
      end

    {disambiguation, priorities, is_nil(inflection), bit_count(grammemes),
     if(inflection, do: -length(pattern.inflections), else: 0)}
  end

  defp disambiguation_score(grammemes, masks) do
    Enum.reduce(masks, 0, fn mask, acc ->
      acc * 2 + if (grammemes &&& mask) != 0, do: 1, else: 0
    end)
  end

  defp optional_score(grammemes, masks) do
    Enum.reduce(masks, 0, fn mask, acc ->
      acc * 2 + if (grammemes &&& mask) != 0, do: 1, else: 0
    end)
  end

  defp contains_all?(superset, subset), do: (superset &&& subset) == subset

  defp bit_count(mask) when mask >= 0, do: bit_count(mask, 0)
  defp bit_count(0, count), do: count
  defp bit_count(mask, count), do: bit_count(mask >>> 1, count + (mask &&& 1))

  defp all_caps?(word) do
    String.upcase(word) == word and String.downcase(word) != word
  end

  defp match_case(original, inflected, true = _all_caps?) do
    _ = original
    String.upcase(inflected)
  end

  defp match_case(original, inflected, false) do
    first = String.first(original)

    if (first && String.upcase(first) == first) and String.downcase(first) != first do
      {head, rest} = String.split_at(inflected, 1)
      String.upcase(head) <> rest
    else
      inflected
    end
  end

  @doc false
  def metadata(locale), do: Data.metadata!(locale)
end
