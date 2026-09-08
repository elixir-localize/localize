defmodule Localize.Inflection.Synthesizer.Fi do
  @moduledoc false

  # The per-language synthesizers and conformance harnesses are ported
  # from the upstream C++ linguistic rule tables; their branchiness and
  # nesting mirror the reference implementation they are verified
  # against (see guides/inflection.md).
  # credo:disable-for-this-file Credo.Check.Refactor.CyclomaticComplexity
  # credo:disable-for-this-file Credo.Check.Refactor.Nesting

  # The Finnish grammar synthesizer, ported from
  # `FiGrammarSynthesizer`. Eleven-case inflection through suffix
  # exemplars, possessive suffixes by string surgery on other case
  # forms, and inner/outer locative features driven by the
  # dictionary `outer` property.

  @behaviour Localize.Inflection.Synthesizer

  alias Localize.Inflection.{
    Data,
    Dictionary,
    DisplayValue,
    Inflector,
    Lookup,
    PhraseProperties
  }

  import Bitwise

  @locale :fi

  @cases ~w(nominative genitive partitive inessive elative illative adessive ablative allative essive translative)

  @priorities [
    ["numeral", "noun", "proper-noun", "adjective", "verb"],
    @cases,
    ["singular", "plural"],
    ["present", "past"],
    ["infinitive"]
  ]

  @ignore_sets [["verb", "passive"]]

  @max_suffix_length 8
  @min_stem_length 2

  @impl true
  def feature_value(feature, display_value, constraints)

  def feature_value("number", display_value, _constraints) do
    determine_count(display_value.display_string)
  end

  def feature_value("residing", display_value, _constraints) do
    locative(display_value.display_string, "inessive", "adessive")
  end

  def feature_value("exiting", display_value, _constraints) do
    locative(display_value.display_string, "elative", "ablative")
  end

  def feature_value("entering", display_value, _constraints) do
    locative(display_value.display_string, "illative", "allative")
  end

  def feature_value("withHyphenSuffix", display_value, _constraints) do
    display_string = display_value.display_string

    if String.contains?(display_string, " ") do
      display_string <> " "
    else
      display_string
    end
  end

  def feature_value(_feature, _display_value, _constraints), do: nil

  defp determine_count(word) do
    case Lookup.determine(@locale, word, ["singular", "plural"],
           disambiguation: ["noun", "adjective"]
         ) do
      "" ->
        with exemplar when is_binary(exemplar) <- exemplar_for(word),
             out when out != "" <-
               Lookup.determine(@locale, exemplar, ["singular", "plural"],
                 disambiguation: ["noun", "adjective"]
               ) do
          out
        else
          _other -> "singular"
        end

      out ->
        out
    end
  end

  # ── Display function ─────────────────────────────────────────

  @impl true
  def display_value(display_data, constraints, guess?) do
    case List.first(display_data) do
      %DisplayValue{} = display_value ->
        inflect_display(display_value, constraints, guess?)

      _other ->
        nil
    end
  end

  defp inflect_display(display_value, constraints, guess?) do
    display_string = display_value.display_string

    case_ = parse(Map.get(constraints, "case"), @cases)
    count = parse(Map.get(constraints, "number"), ["singular", "plural"])
    pos = Map.get(constraints, "pos", "")
    person = parse(Map.get(constraints, "person"), ["first", "second", "third"])

    inflected =
      if display_string != "" and (case_ != nil or count != nil) do
        case_ = case_ || "nominative"
        count = count || "singular"
        inflect_phrase(display_string, pos, case_, count, person, guess?)
      else
        ""
      end

    if inflected == "" do
      %DisplayValue{display_string: display_string, constraints: constraints}
    else
      %DisplayValue{display_string: inflected, constraints: constraints}
    end
  end

  defp inflect_phrase(display_string, pos, case_, count, person, guess?) do
    words = display_string |> String.trim() |> String.split(" ", trim: true)

    special =
      if String.contains?(display_string, " ") and length(words) == 2 do
        [dependant, head] = words

        cond do
          dependant =~ ~r/^[[:digit:]]+$/u ->
            dependant <> " " <> inflect_string(head, pos, case_, count, person, guess?)

          adjective_noun_pair?(dependant, head) ->
            inflect_string(dependant, pos, case_, count, nil, guess?) <>
              " " <> inflect_string(head, pos, case_, count, person, guess?)

          true ->
            nil
        end
      end

    special || inflect_string(display_string, pos, case_, count, person, guess?)
  end

  defp adjective_noun_pair?(dependant, head) do
    adjective = Dictionary.binary_properties(@locale, ["adjective"]) || 0
    head_type = Dictionary.combined_grammemes(@locale, head)
    dependant_type = Dictionary.combined_grammemes(@locale, dependant)

    (head_type == nil or (head_type &&& inflectable_mask()) != 0) and
      dependant_type != nil and (dependant_type &&& adjective) != 0
  end

  defp inflectable_mask do
    Dictionary.binary_properties(@locale, ["adjective", "noun", "numeral", "proper-noun", "verb"]) ||
      0
  end

  defp outer_mask, do: Dictionary.binary_properties(@locale, ["outer"]) || 0

  # ── Core inflection ──────────────────────────────────────────

  @doc false
  def inflect_string(lemma, pos, case_, count, person, guess?) do
    binary_type = (Dictionary.combined_grammemes(@locale, lemma) || 0) &&& bnot(outer_mask())

    if binary_type != 0 and (binary_type &&& inflectable_mask()) == 0 do
      lemma
    else
      if person != nil do
        possessive_inflection(lemma, pos, case_, count, person, guess?)
      else
        plain_inflection(lemma, binary_type, pos, case_, count, guess?)
      end
    end
  end

  # Possessive suffixes are synthesized by surgery on other case
  # forms.
  defp possessive_inflection(lemma, pos, case_, count, person, guess?) do
    suffix = possessive_suffix(person, has_back_vowels?(lemma))

    cond do
      case_ == "nominative" or (case_ == "genitive" and count == "singular") ->
        essive = inflect_string(lemma, pos, "essive", "singular", nil, guess?)
        String.slice(essive, 0..-3//1) <> suffix

      case_ == "illative" or (case_ == "genitive" and count == "plural") ->
        inflected = inflect_string(lemma, pos, case_, count, nil, guess?)
        String.slice(inflected, 0..-2//1) <> suffix

      case_ == "translative" ->
        inflected = inflect_string(lemma, pos, case_, count, nil, guess?)
        String.slice(inflected, 0..-2//1) <> "e" <> suffix

      true ->
        inflect_string(lemma, pos, case_, count, nil, guess?) <> suffix
    end
  end

  defp possessive_suffix("second", _back?), do: "si"
  defp possessive_suffix("third", true), do: "nsa"
  defp possessive_suffix("third", false), do: "nsä"
  defp possessive_suffix(_person, _back?), do: ""

  # An unknown word requested in citation form stays unchanged.
  defp plain_inflection(lemma, 0, _pos, "nominative", "singular", _guess?), do: lemma

  defp plain_inflection(lemma, binary_type, pos, case_, count, guess?) do
    disambiguation = if pos == "", do: [], else: [pos]
    constraint_values = Enum.reject([case_, count], &(&1 in [nil, ""]))

    {exemplar, binary_type} = resolve_exemplar(lemma, binary_type, guess?, case_ != "nominative")

    if binary_type != 0 do
      result =
        inflect_exemplar(lemma, exemplar, binary_type, constraint_values, disambiguation) ||
          if guess? and case_ != nil and count != nil do
            inflect_exemplar(lemma, exemplar, binary_type, [case_], disambiguation)
          end

      result || lemma
    else
      lemma
    end
  end

  defp resolve_exemplar(lemma, 0, guess?, phrase_guess?) do
    # Unknown as a whole: try the last word of the phrase (when it
    # reads as a nominative head), then the longest known suffix
    # word of an unknown compound, then the suffix map, then the
    # fallback exemplars. Phrase-level suffix guessing runs only
    # for oblique cases (Monte Carlossa) — nominative phrase
    # requests keep the original.
    single_word? = not String.contains?(String.trim(lemma), " ")

    from_tail =
      case lemma |> String.trim() |> String.split(" ", trim: true) |> List.last() do
        nil ->
          nil

        last ->
          nominative = Dictionary.binary_properties(@locale, ["nominative"]) || 0
          grammemes = (Dictionary.combined_grammemes(@locale, last) || 0) &&& bnot(outer_mask())

          if Dictionary.patterns_for_word(@locale, last) != [] and
               (grammemes &&& nominative) != 0 do
            {last, grammemes}
          end
      end

    cond do
      match?({_exemplar, type} when type != 0, from_tail) ->
        from_tail

      guess? and single_word? ->
        suffix_word(lemma) || from_suffix_map(lemma) || from_fallback(lemma)

      guess? and phrase_guess? ->
        from_suffix_map(lemma) || {lemma, 0}

      true ->
        {lemma, 0}
    end
  end

  defp resolve_exemplar(lemma, binary_type, _guess?, _phrase_guess?), do: {lemma, binary_type}

  # The longest dictionary noun (in citation form, at least three
  # characters) that is a proper suffix of an unknown compound
  # (tekstiseikkailupeli → peli).
  defp suffix_word(lemma) do
    length = String.length(lemma)
    nouns = Dictionary.binary_properties(@locale, ["noun", "proper-noun"]) || 0
    nominative = Dictionary.binary_properties(@locale, ["nominative"]) || 0

    if length > 5 do
      Enum.find_value(3..(length - 3)//1, fn start ->
        suffix = String.slice(lemma, start, length - start)

        with grammemes when is_integer(grammemes) <-
               Dictionary.combined_grammemes(@locale, suffix),
             true <- (grammemes &&& nouns) != 0,
             true <- (grammemes &&& nominative) != 0,
             true <- Dictionary.patterns_for_word(@locale, suffix) != [] do
          {suffix, grammemes &&& bnot(outer_mask())}
        else
          _other -> nil
        end
      end)
    end
  end

  defp from_suffix_map(lemma) do
    case exemplar_for(lemma) do
      nil ->
        nil

      exemplar ->
        case Dictionary.combined_grammemes(@locale, exemplar) do
          nil -> nil
          grammemes -> {exemplar, grammemes}
        end
    end
  end

  defp from_fallback(lemma) do
    fallback = fallback_lemma(lemma)
    {fallback, Dictionary.combined_grammemes(@locale, fallback) || 0}
  end

  defp inflect_exemplar(word, exemplar, binary_type, constraint_values, disambiguation) do
    options = [
      disambiguation: disambiguation,
      priorities: @priorities,
      ignore: @ignore_sets
    ]

    case Inflector.inflect(@locale, exemplar, binary_type, constraint_values, options) do
      {:ok, inflected} when word == exemplar ->
        inflected

      {:ok, inflected} ->
        splice(word, exemplar, inflected)

      :error ->
        nil
    end
  end

  defp splice(word, exemplar, inflected) do
    common = common_prefix_length(inflected, exemplar, 0)
    stem_length = String.length(word) - (String.length(exemplar) - common)
    String.slice(word, 0, stem_length) <> String.slice(inflected, common..-1//1)
  end

  defp common_prefix_length(<<c::utf8, rest_a::binary>>, <<c::utf8, rest_b::binary>>, count) do
    common_prefix_length(rest_a, rest_b, count + 1)
  end

  defp common_prefix_length(_a, _b, count), do: count

  # ── Exemplar and vowel-harmony helpers ───────────────────────

  # Candidates matching the word's vowel harmony are preferred so
  # the exemplar's endings agree (-ssä vs -ssa).
  defp exemplar_for(word) do
    exemplars = Data.metadata!(@locale).suffix_exemplars
    length = String.length(word)
    upper = min(@max_suffix_length, length - @min_stem_length)
    harmony = final_harmony(word)

    if upper >= 1 do
      Enum.find_value(upper..1//-1, fn suffix_length ->
        case Map.get(exemplars, String.slice(word, length - suffix_length, suffix_length), []) do
          [] ->
            nil

          candidates ->
            matching = Enum.filter(candidates, &(final_harmony(&1) == harmony))
            pool = if matching == [], do: candidates, else: matching
            Enum.find(pool, &citation_form?/1) || List.first(pool)
        end
      end)
    end
  end

  defp citation_form?(word) do
    mask = Dictionary.binary_properties(@locale, ["nominative", "singular"]) || 0
    mask != 0 and Dictionary.has_all_properties?(@locale, word, mask)
  end

  # Finnish compound harmony follows the final component: the last
  # non-neutral vowel decides (neutral e/i alone → front).
  defp final_harmony(word) do
    word
    |> :unicode.characters_to_nfkc_binary()
    |> String.downcase()
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.find_value(:front, fn grapheme ->
      cond do
        grapheme in ["a", "o", "u"] -> :back
        grapheme in ["ä", "ö", "y"] -> :front
        true -> nil
      end
    end)
  end

  # The upstream fallback exemplars (Abreu, Sund, kennel, perhe,
  # rehentely, kylkirivi) are absent from the published lexicon;
  # these in-lexicon words decline in the same families.
  defp fallback_lemma(lemma) do
    if PhraseProperties.ends_with_vowel?(@locale, lemma) do
      if has_back_vowels?(lemma) do
        "aamu"
      else
        case String.last(lemma) do
          "y" -> "keräily"
          "i" -> "filmi"
          "e" -> "ihme"
          _other -> "aamu"
        end
      end
    else
      if has_back_vowels?(lemma), do: "aapelus", else: "diesel"
    end
  end

  @doc false
  def has_back_vowels?(lemma) do
    lemma
    |> :unicode.characters_to_nfkc_binary()
    |> scan_back_vowels(false)
  end

  defp scan_back_vowels(<<codepoint::utf8, rest::binary>>, found?) do
    char = <<codepoint::utf8>>

    if found? and char =~ ~r/[[:alnum:]\p{Mc}]/u do
      true
    else
      lowercased = String.downcase(char)
      scan_back_vowels(rest, lowercased in ["a", "o", "u"])
    end
  end

  defp scan_back_vowels(<<>>, found?), do: found?

  # ── Locative features (residing / exiting / entering) ────────

  defp locative(display_string, inner_case, outer_case) do
    comma? = String.contains?(display_string, ",")
    words = display_string |> String.trim() |> String.split(" ", trim: true)

    result =
      cond do
        comma? ->
          display_string
          |> String.split(",")
          |> Enum.map(&String.trim/1)
          |> inflect_units(inner_case, outer_case)
          |> Enum.join(", ")

        length(words) > 1 ->
          words
          |> best_combination()
          |> inflect_units(inner_case, outer_case)
          |> Enum.join(" ")

        true ->
          locative_string(display_string, display_string, inner_case, outer_case)
      end

    if String.trim(result) == "", do: display_string, else: result
  end

  defp inflect_units([attribute, head] = units, inner_case, outer_case) do
    nouns = Dictionary.binary_properties(@locale, ["noun", "proper-noun"]) || 0
    adjectives = Dictionary.binary_properties(@locale, ["adjective", "participle"]) || 0
    attribute_type = Dictionary.combined_grammemes(@locale, attribute) || 0
    head_type = Dictionary.combined_grammemes(@locale, head) || 0

    first =
      cond do
        (attribute_type &&& nouns) != 0 and (head_type &&& adjectives) != 0 ->
          attribute

        (attribute_type &&& adjectives) != 0 and (head_type &&& nouns) != 0 ->
          locative_string(attribute, head, inner_case, outer_case)

        true ->
          locative_string(attribute, attribute, inner_case, outer_case)
      end

    _ = units
    [first, locative_string(head, head, inner_case, outer_case)]
  end

  defp inflect_units(units, inner_case, outer_case) do
    Enum.map(units, &locative_string(&1, &1, inner_case, outer_case))
  end

  defp locative_string(attribute, head, inner_case, outer_case) do
    plural = Dictionary.binary_properties(@locale, ["plural"]) || 0

    count =
      if plural != 0 and Dictionary.has_all_properties?(@locale, head, plural) do
        "plural"
      else
        "singular"
      end

    case_ =
      if outer_mask() != 0 and Dictionary.has_all_properties?(@locale, head, outer_mask()) do
        outer_case
      else
        inner_case
      end

    inflect_string(attribute, "noun", case_, count, nil, true)
  end

  # All ordered partitions of the word list; prefer the partition
  # with every group in the dictionary and the fewest groups.
  defp best_combination(words) do
    combinations = partitions(words)

    dictionary_combinations =
      Enum.filter(combinations, fn groups ->
        Enum.all?(groups, fn group ->
          Dictionary.combined_grammemes(@locale, Enum.join(group, " ")) != nil
        end)
      end)

    chosen =
      case dictionary_combinations do
        [] -> List.first(combinations)
        [single] -> single
        many -> Enum.min_by(many, &length/1)
      end

    Enum.map(chosen, &Enum.join(&1, " "))
  end

  defp partitions([_single] = words), do: [[words]]

  defp partitions(words) do
    whole = [[words]]

    splits =
      for i <- 1..(length(words) - 1),
          tails <- partitions(Enum.drop(words, i)) do
        [Enum.take(words, i) | tails]
      end

    whole ++ splits
  end

  defp parse(value, allowed) when is_binary(value) do
    if value in allowed, do: value
  end

  defp parse(_value, _allowed), do: nil
end
