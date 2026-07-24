defmodule Localize.Inflection.DataGen.Generate do
  @moduledoc false

  # Compiles the parsed upstream source data into a per-locale
  # artifact stored as compressed ETF under `priv/data/`.
  #
  # The artifact assigns every grammeme name a bit index so word
  # properties and inflection grammemes can be represented and
  # compared as integer bitmasks, mirroring the upstream C++
  # implementation (without its 64-bit limit).

  alias Localize.Inflection.DataGen.{Features, Lexicon, Paradigms}

  @source_dir "data/source"

  @doc """
  Generates the artifact for one locale and writes it to
  `priv/data/<locale>.etf`. Returns the artifact.

  """
  def generate(locale) when is_binary(locale) do
    dictionary_path = source_path("dictionary/dictionary_#{locale}.lst")

    lexicon =
      if File.exists?(dictionary_path) do
        dictionary_path
        |> Lexicon.parse_file()
        |> merge_supplemental(locale)
      else
        # Features-only languages (yue) ship no dictionary; the
        # artifact still carries the grammar.xml feature model.
        []
      end

    paradigms_path = source_path("dictionary/inflectional_#{locale}.xml")

    paradigms =
      if File.exists?(paradigms_path) do
        Paradigms.parse_file(paradigms_path)
      else
        # Uninflected languages (Thai and friends) ship no paradigm
        # file.
        []
      end

    features = Features.parse_file(source_path("features/grammar.xml"))[locale]

    grammeme_names = collect_grammeme_names(lexicon, paradigms)
    grammeme_bits = grammeme_names |> Enum.with_index() |> Map.new()

    pattern_index =
      paradigms
      |> Enum.with_index()
      |> Map.new(fn {pattern, index} -> {pattern.name, index} end)

    patterns =
      paradigms
      |> Enum.map(&compile_pattern(&1, grammeme_bits))
      |> List.to_tuple()

    lexicon_entries =
      lexicon
      |> Enum.map(fn {word, grammemes, pattern_names} ->
        mask = mask_for(grammemes, grammeme_bits)
        indexes = Enum.map(pattern_names, &Map.fetch!(pattern_index, &1))
        {word, mask, indexes}
      end)
      |> add_lowercase_variants()

    artifact = %{
      locale: locale,
      grammeme_names: List.to_tuple(grammeme_names),
      grammeme_bits: grammeme_bits,
      patterns: patterns,
      pattern_index: pattern_index,
      features: features,
      contractions: contractions(locale),
      suffix_exemplars: suffix_exemplars(locale, lexicon_entries),
      lexicon: lexicon_entries
    }

    write_artifact(locale, artifact)
    artifact
  end

  defp source_path(relative) do
    Path.join(@source_dir, relative)
  end

  # The upstream build merges supplemental_<locale>.lst (curated
  # entries such as proper nouns) into the dictionary. Entries for
  # an existing surface form combine their grammemes and patterns.
  defp merge_supplemental(lexicon, locale) do
    path = source_path("dictionary/supplemental_#{locale}.lst")

    if File.exists?(path) do
      supplemental = Lexicon.parse_file(path)
      by_surface = Map.new(supplemental, fn {surface, _g, _p} = entry -> {surface, entry} end)

      merged =
        Enum.map(lexicon, fn {surface, grammemes, patterns} = entry ->
          case Map.get(by_surface, surface) do
            nil ->
              entry

            {_surface, extra_grammemes, extra_patterns} ->
              {surface, Enum.uniq(grammemes ++ extra_grammemes),
               Enum.uniq(patterns ++ extra_patterns)}
          end
        end)

      existing = MapSet.new(lexicon, fn {surface, _g, _p} -> surface end)
      additions = Enum.reject(supplemental, fn {surface, _g, _p} -> surface in existing end)
      merged ++ additions
    else
      lexicon
    end
  end

  defp collect_grammeme_names(lexicon, paradigms) do
    from_lexicon =
      Enum.reduce(lexicon, MapSet.new(), fn {_word, grammemes, _patterns}, acc ->
        Enum.into(grammemes, acc)
      end)

    from_paradigms =
      Enum.reduce(paradigms, MapSet.new(), fn pattern, acc ->
        acc = Enum.into(pattern.pos, acc)

        Enum.reduce(pattern.inflections, acc, fn {grammemes, _suffix}, inner ->
          Enum.into(grammemes, inner)
        end)
      end)

    from_lexicon
    |> MapSet.union(from_paradigms)
    |> Enum.sort()
  end

  defp compile_pattern(pattern, grammeme_bits) do
    pos_mask = mask_for(pattern.pos, grammeme_bits)

    inflections =
      Enum.map(pattern.inflections, fn {grammemes, suffix} ->
        {mask_for(grammemes, grammeme_bits), suffix}
      end)

    %{
      name: pattern.name,
      pos_mask: pos_mask,
      lemma_suffix: pattern.lemma_suffix,
      inflections: inflections
    }
  end

  # The upstream dictionary builder also inserts each entry under
  # its lowercased key so that "albanischs" finds "Albanischs".
  # Exact entries win over lowercased variants, and the first
  # lowercased variant wins over later ones.
  defp add_lowercase_variants(entries) do
    existing = MapSet.new(entries, fn {word, _mask, _patterns} -> word end)

    variants =
      entries
      |> Enum.flat_map(fn {word, mask, patterns} ->
        lowercased = String.downcase(word)

        if lowercased != word and not MapSet.member?(existing, lowercased) do
          [{lowercased, mask, patterns}]
        else
          []
        end
      end)
      |> Enum.uniq_by(fn {word, _mask, _patterns} -> word end)

    entries ++ variants
  end

  defp mask_for(grammemes, grammeme_bits) do
    Enum.reduce(grammemes, 0, fn grammeme, acc ->
      Bitwise.bor(acc, Bitwise.bsl(1, Map.fetch!(grammeme_bits, grammeme)))
    end)
  end

  defp contractions(locale) do
    path = source_path("contraction/contractionExpandingTable_#{locale}.csv")

    if File.exists?(path) do
      path
      |> File.stream!()
      |> Enum.map(fn line ->
        line
        |> String.trim()
        |> String.split(",")
        |> List.first()
      end)
      |> Enum.reject(&(&1 in [nil, ""]))
    else
      []
    end
  end

  # `suffix,=,exemplarWord` rows mapping an inflectional suffix to a
  # dictionary word that declines the same way (used for guessing).
  # Exemplar targets missing from the lexicon are replaced with a
  # lexicon word sharing the suffix (same declension family), since
  # the guess algorithm only uses the exemplar's inflection ending.
  defp suffix_exemplars(locale, lexicon_entries) do
    path = source_path("exemplar/suffix_#{locale}.csv")

    if File.exists?(path) do
      exemplars =
        path
        |> File.stream!()
        |> Enum.reduce(%{}, fn line, acc ->
          case line |> String.trim() |> String.split(",") do
            [suffix, "=", exemplar] -> Map.put_new(acc, suffix, exemplar)
            _other -> acc
          end
        end)

      surfaces = MapSet.new(lexicon_entries, fn {word, _mask, _patterns} -> word end)
      suffixes = exemplars |> Map.keys() |> MapSet.new()

      # Per suffix, one candidate of each vowel-harmony class (some
      # languages need harmony-matched exemplars).
      substitutes =
        Enum.reduce(lexicon_entries, %{}, fn {word, _mask, patterns}, acc ->
          if patterns == [] do
            acc
          else
            word_length = String.length(word)
            harmony = if back_vowels?(word), do: :back, else: :front

            Enum.reduce(1..min(8, max(word_length - 1, 1))//1, acc, fn suffix_length, inner ->
              suffix = String.slice(word, word_length - suffix_length, suffix_length)

              if MapSet.member?(suffixes, suffix) do
                Map.update(inner, suffix, %{harmony => word}, &Map.put_new(&1, harmony, word))
              else
                inner
              end
            end)
          end
        end)

      Map.new(exemplars, fn {suffix, target} ->
        alternates = Map.get(substitutes, suffix, %{}) |> Map.values()

        candidates =
          if MapSet.member?(surfaces, target) do
            [target | alternates]
          else
            alternates
          end

        {suffix, Enum.uniq(candidates)}
      end)
    else
      %{}
    end
  end

  defp back_vowels?(word) do
    word
    |> :unicode.characters_to_nfkc_binary()
    |> String.downcase()
    |> String.graphemes()
    |> Enum.any?(&(&1 in ["a", "o", "u"]))
  end

  defp write_artifact(locale, artifact) do
    directory = Path.join([File.cwd!(), "priv", "data"])
    File.mkdir_p!(directory)
    binary = :erlang.term_to_binary(artifact, [:compressed])
    File.write!(Path.join(directory, "#{locale}.etf"), binary)
  end
end
