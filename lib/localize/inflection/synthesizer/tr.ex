defmodule Localize.Inflection.Synthesizer.Tr do
  @moduledoc false

  # The per-language synthesizers and conformance harnesses are ported
  # from the upstream C++ linguistic rule tables; their branchiness and
  # nesting mirror the reference implementation they are verified
  # against (see guides/inflection.md).
  # credo:disable-for-this-file Credo.Check.Refactor.CyclomaticComplexity
  # credo:disable-for-this-file Credo.Check.Refactor.Nesting

  # The Turkish grammar synthesizer, ported from
  # `TrGrammarSynthesizer`. Turkish is agglutinative: suffixes are
  # synthesized (plural → possessive → case → copula) with vowel
  # harmony, buffer consonants and consonant assimilation, and
  # appended to the last word.

  @behaviour Localize.Inflection.Synthesizer

  alias Localize.Inflection.{
    Dictionary,
    DisplayValue,
    PhraseProperties,
    Tokenizer,
    TurkishNumbers
  }

  import Bitwise

  @locale :tr

  # Vowel groups: 0 front unrounded, 1 front rounded, 2 back
  # unrounded, 3 back rounded. Affix vowel per group:
  @affix {"i", "ü", "ı", "u"}

  @cases %{
    "ablative" => 1,
    "accusative" => 2,
    "dative" => 3,
    "genitive" => 4,
    "locative" => 5,
    "instrumental" => 6
  }

  # Buffer consonant when the current tail ends with a vowel:
  # {possessive, plain} per case index.
  @case_buffer {{"", ""}, {"n", ""}, {"n", "y"}, {"n", "y"}, {"n", "n"}, {"n", ""}, {"y", "y"}}

  # Case ending {front, back} per case index.
  @case_ending {{"", ""}, {"den", "dan"}, {"", ""}, {"e", "a"}, {"n", "n"}, {"de", "da"},
                {"le", "la"}}

  # Copula tables indexed [tense][copula] (0 undefined, tense:
  # 1 present 2 past; copula: 1 first 2 second 3 third).
  @copula_before_consonant {{"", "", "", ""}, {"", "y", "", ""}, {"", "y", "y", "y"}}
  @copula_before_vowel {{"", "", "", ""}, {"", "", "s", "d"}, {"", "d", "d", "d"}}
  @copula_after_vowel {{"", "", "", ""}, {"", "m", "n", "r"}, {"", "m", "n", ""}}

  @possessive_compound_suffixes ~w(ları leri sı si su sü ı i u ü)

  @hard_consonants ~w(ç k p t)
  @continuous_hard ~w(f h s ş q x)

  # Front unrounded vowels (e i ä é è ë ě í ï ý) are the default
  # group when no other class matches.
  @front_rounded_vowels ~w(ö ü ø)
  @back_unrounded_vowels ~w(a ı ă á ã)
  @back_rounded_vowels ~w(o u ó ô ú ů ū)

  @impl true
  def feature_value(feature, display_value, constraints)

  def feature_value("interrogativeArticle", display_value, _constraints) do
    display_string = display_value.display_string
    group = vowel_group(last_word(display_string))
    display_string <> " m" <> elem(@affix, group)
  end

  def feature_value("deConjunction", display_value, _constraints) do
    display_string = display_value.display_string

    suffix =
      if vowel_group(last_word(display_string)) in [0, 1], do: " de", else: " da"

    display_string <> suffix
  end

  def feature_value(_feature, _display_value, _constraints), do: nil

  # ── Display function ─────────────────────────────────────────

  @impl true
  def display_value(display_data, constraints, _guess?) do
    with %DisplayValue{} = display_value <- List.first(display_data),
         display_string when display_string != "" <- display_value.display_string do
      %DisplayValue{
        display_string: inflect(display_string, constraints),
        constraints: constraints
      }
    else
      _other -> nil
    end
  end

  defp inflect(display_string, constraints) do
    normalized = normalize_last_word(display_string)

    case_value = Map.get(@cases, Map.get(constraints, "case", ""), 0)
    number = parse(Map.get(constraints, "number"), ["singular", "plural"])
    person = parse(Map.get(constraints, "person"), ["first", "second", "third"])
    copula = parse(Map.get(constraints, "copula"), ["first", "second", "third"])
    tense = parse(Map.get(constraints, "tense"), ["present", "past"])

    pronoun =
      parse(
        Map.get(constraints, "pronounNumber") || Map.get(constraints, "pronoun"),
        ["singular", "plural"]
      )

    ends_number? = ends_with_number?(display_string)
    compound? = compound_word?(normalized)

    possessive_suffix =
      possessive_compound_suffix(String.contains?(display_string, " "), normalized)

    foreign? = foreign_word?(normalized)

    retarget? = number == "plural" or person != nil or pronoun != nil

    {display_string, normalized, possessive_compound?} =
      strip_possessive_compound(
        display_string,
        normalized,
        foreign?,
        compound?,
        ends_number?,
        possessive_suffix,
        retarget?
      )

    group = vowel_group(normalized)
    foreign? = foreign_word?(normalized)
    exception? = exception_word?(normalized)

    {suffix, group, last_part, possessive?} =
      build_plural(number, group, possessive_compound?, normalized)

    {suffix, group, last_part, possessive?} =
      build_possessive(
        suffix,
        group,
        last_part,
        possessive?,
        number,
        person,
        pronoun,
        possessive_compound?
      )

    {case_suffix, group} = case_suffixes(case_value, possessive?, group, last_part)
    suffix = suffix <> case_suffix

    copula_base =
      cond do
        case_suffix == "" and suffix == "" -> normalized
        case_suffix == "" -> suffix
        true -> case_suffix
      end

    suffix = suffix <> copula_suffixes(copula, tense, group, copula_base)

    assemble(display_string, normalized, suffix, ends_number?, foreign?, exception?)
  end

  defp parse(value, allowed) when is_binary(value) do
    if value in allowed, do: value
  end

  defp parse(_value, _allowed), do: nil

  # ── Pipeline steps ───────────────────────────────────────────

  defp strip_possessive_compound(
         display_string,
         normalized,
         foreign?,
         compound?,
         ends_number?,
         possessive_suffix,
         retarget?
       ) do
    possessive_compound? =
      not foreign? and (compound? or (not ends_number? and possessive_suffix != ""))

    strip? =
      possessive_compound? and last_word(display_string) == normalized and retarget?

    if strip? and possessive_suffix != "" do
      length = byte_size(possessive_suffix)
      normalized = binary_part(normalized, 0, byte_size(normalized) - length)
      display_string = binary_part(display_string, 0, byte_size(display_string) - length)
      lemmatized = revert_assimilation(normalized)

      if lemmatized != normalized do
        {revert_assimilation(display_string), lemmatized, possessive_compound?}
      else
        {display_string, normalized, possessive_compound?}
      end
    else
      {display_string, normalized, possessive_compound?}
    end
  end

  defp build_plural(number, group, possessive_compound?, normalized) do
    if number == "plural" do
      {plural, group} =
        if group in [2, 3] do
          {"lar" <> if(possessive_compound?, do: "ı", else: ""), 2}
        else
          {"ler" <> if(possessive_compound?, do: "i", else: ""), 0}
        end

      {plural, group, plural, possessive_compound?}
    else
      {"", group, normalized, possessive_compound?}
    end
  end

  defp build_possessive(suffix, group, last_part, possessive?, number, person, pronoun, compound?) do
    if person != nil or pronoun != nil do
      {addition, group} =
        possessive_suffixes(number, person, pronoun || "singular", compound?, group, last_part)

      {suffix <> addition, group, addition, true}
    else
      {suffix, group, last_part, possessive?}
    end
  end

  defp possessive_suffixes(number, person, pronoun, compound?, group, last_part) do
    cond do
      person == "third" and pronoun == "singular" ->
        buffer = if tail_ends_with_vowel?(last_part), do: "s", else: ""
        {buffer <> elem(@affix, group), group}

      person == "third" and pronoun == "plural" ->
        if number == "plural" do
          if compound? do
            {"", group}
          else
            if group == 2, do: {"ı", 2}, else: {"i", 0}
          end
        else
          if group in [2, 3], do: {"ları", 2}, else: {"leri", 0}
        end

      true ->
        buffer = if tail_ends_with_vowel?(last_part), do: "", else: elem(@affix, group)
        personal = if person == "first", do: "m", else: "n"
        plural_part = if pronoun == "plural", do: elem(@affix, group) <> "z", else: ""
        {buffer <> personal <> plural_part, group}
    end
  end

  defp case_suffixes(0, _possessive?, group, _last_part), do: {"", group}

  defp case_suffixes(case_value, possessive?, group, last_part) do
    buffer =
      if tail_ends_with_vowel?(last_part) do
        @case_buffer |> elem(case_value) |> elem(if possessive?, do: 0, else: 1)
      else
        ""
      end

    front? = group in [0, 1]

    {vowel, group} =
      cond do
        case_value in [2, 4] -> {elem(@affix, group), group}
        case_value in [1, 3, 5, 6] -> {"", if(front?, do: 0, else: 2)}
        true -> {"", group}
      end

    ending = @case_ending |> elem(case_value) |> elem(if front?, do: 0, else: 1)
    {buffer <> vowel <> ending, group}
  end

  defp copula_suffixes(nil, nil, _group, _base), do: ""

  defp copula_suffixes(copula, tense, group, base) do
    copula = copula || "third"
    tense = tense || "present"
    tense_index = if tense == "past", do: 2, else: 1

    copula_index =
      case copula do
        "first" -> 1
        "second" -> 2
        "third" -> 3
      end

    before_consonant =
      if tail_ends_with_vowel?(base) do
        @copula_before_consonant |> elem(tense_index) |> elem(copula_index)
      else
        ""
      end

    before_vowel = @copula_before_vowel |> elem(tense_index) |> elem(copula_index)
    after_vowel = @copula_after_vowel |> elem(tense_index) |> elem(copula_index)
    before_consonant <> before_vowel <> elem(@affix, group) <> after_vowel
  end

  defp tail_ends_with_vowel?(""), do: false
  defp tail_ends_with_vowel?(tail), do: PhraseProperties.ends_with_vowel?(@locale, tail)

  # ── Final assembly ───────────────────────────────────────────

  defp assemble(display_string, normalized, suffix, ends_number?, foreign?, exception?) do
    display_string =
      voice_final_consonant(display_string, normalized, suffix, foreign?, exception?)

    suffix =
      if suffix != "" and hard_final?(normalized) do
        assimilate_first(suffix)
      else
        suffix
      end

    join_suffix(display_string, suffix, ends_number?, foreign?)
  end

  # Stem-final consonant voicing (kitap+ı → kitabı) before a
  # vowel-initial suffix.
  defp voice_final_consonant(display_string, normalized, suffix, foreign?, exception?) do
    cond do
      display_string == "" ->
        display_string

      last_word(display_string) == normalized and not foreign? and not exception? ->
        if suffix != "" and starts_with_vowel?(suffix) and
             ends_with_hard_consonant?(display_string, true) and
             not one_vowel_word?(normalized) do
          assimilate_last(display_string, false)
        else
          display_string
        end

      exception? and has_property?(normalized, "hard-consonant") and suffix != "" and
          starts_with_vowel?(suffix) ->
        assimilate_last(display_string, one_vowel_word?(normalized))

      true ->
        display_string
    end
  end

  # Foreign words and digit-final strings take suffixes after ’.
  defp join_suffix(display_string, suffix, ends_number?, foreign?) do
    if suffix != "" and (foreign? or ends_number?) and display_string != "" and
         String.last(display_string) not in ["\"", "”"] do
      display_string =
        if String.last(display_string) in ["'", "’"] do
          String.slice(display_string, 0..-2//1)
        else
          display_string
        end

      display_string <> "’" <> suffix
    else
      display_string <> suffix
    end
  end

  # ── Word analysis ────────────────────────────────────────────

  defp last_word(string) do
    trimmed = String.trim(string)

    case String.split(trimmed, " ") do
      [] -> trimmed
      words -> List.last(words)
    end
  end

  defp trim_end(word) do
    String.replace(word, ~r/[^[:alnum:]]+$/u, "")
  end

  defp ends_with_number?(word) do
    trimmed = trim_end(word)
    trimmed != "" and String.last(trimmed) =~ ~r/[[:digit:]]/
  end

  defp normalize_last_word(display_string) do
    word = last_word(display_string)

    if foreign_word?(word) do
      word
    else
      trimmed = trim_end(word)

      if byte_size(word) != byte_size(trimmed) and foreign_word?(trimmed) do
        trimmed
      else
        normalize_string(word)
      end
    end
  end

  # Digit-final words harmonize over their Turkish spellout.
  defp normalize_string(""), do: ""

  defp normalize_string(original) do
    ends_with_period? = String.ends_with?(original, ".")
    word = trim_end(original)

    if word == "" or foreign_word?(word) or not (String.last(word) =~ ~r/[[:digit:]]/) do
      word
    else
      case last_number(word) do
        nil ->
          word

        number ->
          if ends_with_period? do
            TurkishNumbers.ordinal(number)
          else
            TurkishNumbers.cardinal(number)
          end
      end
    end
  end

  # The rightmost positive number segment (segments split on
  # '/', ':' or whitespace); when every segment parses to zero the
  # last parse wins, and a failed parse falls back to the final
  # digit alone.
  defp last_number(word) do
    word
    |> String.split(~r{[/:\s]+})
    |> Enum.reverse()
    |> Enum.reduce_while(nil, fn segment, last_parsed ->
      case parse_turkish_number(segment) do
        number when is_number(number) and number > 0 ->
          {:halt, number}

        number when is_number(number) ->
          {:cont, number}

        nil ->
          fallback =
            with last when last != nil and last != "0" <- String.last(segment),
                 {digit, _rest} <- Integer.parse(last) do
              digit
            else
              _other -> last_parsed
            end

          {:halt, fallback}
      end
    end)
  end

  defp parse_turkish_number(segment) do
    normalized = segment |> String.replace(".", "") |> String.replace(",", ".")

    case Float.parse(normalized) do
      {number, _rest} -> number
      :error -> nil
    end
  end

  defp one_vowel_word?(word) do
    count =
      word
      |> String.graphemes()
      |> Enum.count(fn grapheme ->
        PhraseProperties.ends_with_vowel?(@locale, grapheme)
      end)

    count <= 1
  end

  defp starts_with_vowel?(word), do: PhraseProperties.starts_with_vowel?(@locale, word)

  # ── Possessive compound detection ────────────────────────────

  defp possessive_compound_suffix(false, _word), do: ""

  defp possessive_compound_suffix(true, word) do
    Enum.find_value(@possessive_compound_suffixes, "", fn suffix ->
      if String.ends_with?(word, suffix) do
        trimmed = binary_part(word, 0, byte_size(word) - byte_size(suffix))

        cond do
          ends_with_number?(trimmed) ->
            ""

          compound_candidate?(trimmed, word, suffix) ->
            suffix

          compound_candidate?(revert_assimilation(trimmed), word, suffix) and
              revert_assimilation(trimmed) != trimmed ->
            suffix

          true ->
            nil
        end
      end
    end)
  end

  defp compound_candidate?(stem, word, suffix) do
    (one_token?(stem) or exception_word?(stem) or compound_word?(stem)) and
      Dictionary.combined_grammemes(@locale, stem) != nil and
      not exception_word?(word) and
      (String.length(suffix) > 2 or not one_token?(word))
  end

  defp one_token?(word) do
    length(Tokenizer.word_tokens(@locale, word)) == 1
  end

  # ── Consonant phonology ──────────────────────────────────────

  defp ends_with_hard_consonant?(word, discontinuous?) do
    case String.last(word) do
      nil ->
        false

      last ->
        lowercased = String.downcase(last, :turkic)

        cond do
          lowercased in @hard_consonants -> true
          not discontinuous? and lowercased in @continuous_hard -> true
          String.length(word) >= 2 and lowercased in ["ć", "č"] -> true
          String.length(word) >= 2 and not discontinuous? and lowercased == "š" -> true
          true -> false
        end
    end
  end

  defp hard_final?(word) do
    cond do
      has_property?(word, "soft-consonant") -> false
      ends_with_hard_consonant?(word, false) -> true
      has_property?(word, "hard-consonant") -> true
      true -> false
    end
  end

  defp assimilate_last(word, one_word?) do
    {head, last} = String.split_at(word, -1)

    replacement =
      case last do
        "ç" -> "c"
        "k" -> if one_word?, do: "g", else: "ğ"
        "g" -> if one_word?, do: "g", else: "ğ"
        "p" -> "b"
        "t" -> "d"
        other -> other
      end

    head <> replacement
  end

  defp revert_assimilation(word) do
    case String.split_at(word, -1) do
      {head, last} when last in ["b", "c", "d", "ğ"] ->
        head <>
          case last do
            "b" -> "p"
            "c" -> "ç"
            "d" -> "t"
            "ğ" -> "k"
          end

      _other ->
        word
    end
  end

  defp assimilate_first(word) do
    case String.next_codepoint(word) do
      {first, rest} when first in ["b", "c", "d", "g"] ->
        replacement =
          case first do
            "b" -> "p"
            "c" -> "ç"
            "d" -> "t"
            "g" -> "k"
          end

        replacement <> rest

      _other ->
        word
    end
  end

  # ── Vowel harmony classification ─────────────────────────────

  @doc false
  def vowel_group(word) do
    from_dictionary =
      case Dictionary.combined_grammemes(@locale, word) do
        nil ->
          nil

        properties ->
          Enum.find_value(
            [{"front-round", 1}, {"front-unround", 0}, {"back-round", 3}, {"back-unround", 2}],
            fn {property, group} ->
              mask = Dictionary.binary_properties(@locale, [property]) || 0
              if mask != 0 and (properties &&& mask) == mask, do: group
            end
          )
      end

    from_dictionary || heuristic_vowel_group(String.downcase(word, :turkic))
  end

  defp heuristic_vowel_group(word) do
    case last_vowel(word) do
      vowel when vowel in @front_rounded_vowels -> 1
      vowel when vowel in @back_unrounded_vowels -> 2
      vowel when vowel in @back_rounded_vowels -> 3
      _other -> 0
    end
  end

  defp last_vowel(word) do
    normalized = normalize_string(word)
    graphemes = String.graphemes(normalized)

    graphemes
    |> Enum.reverse()
    |> Enum.find("i", fn grapheme ->
      PhraseProperties.ends_with_vowel?(@locale, grapheme)
    end)
  end

  defp has_property?(word, property) do
    mask = Dictionary.binary_properties(@locale, [property]) || 0
    mask != 0 and Dictionary.has_all_properties?(@locale, word, mask)
  end

  defp foreign_word?(word), do: has_property?(word, "foreign")
  defp exception_word?(word), do: has_property?(word, "exception")
  defp compound_word?(word), do: has_property?(word, "compound")
end
