defmodule Localize.Inflection.Synthesizer.Nl do
  @moduledoc false

  # The Dutch grammar synthesizer, ported from
  # `NlGrammarSynthesizer` and its lookup and inflection patterns.
  # Article choice is de/het (het for singular neuter or
  # diminutives); adjectives decline binary (declined/undeclined)
  # with Dutch spelling changes.

  @behaviour Localize.Inflection.Synthesizer

  alias Localize.Inflection.{
    Articles,
    Dictionary,
    DisplayValue,
    Inflector,
    Lookup,
    Tokenizer
  }

  import Bitwise

  @locale :nl

  @numbers ["singular", "plural"]
  @genders ["masculine", "feminine", "neuter"]

  @vowels ~c"aeiou"
  @possessive_pronouns %{
    "haar" => "haar",
    "hem" => "zijn",
    "hen" => "hun",
    "hij" => "zijn",
    "hun" => "hun",
    "ik" => "mijn",
    "je" => "jouw",
    "jij" => "jouw",
    "jou" => "jouw",
    "me" => "mijn",
    "mij" => "mijn"
  }

  @impl true
  def feature_value(feature, display_value, constraints)

  def feature_value("number", display_value, _constraints) do
    empty_to_nil(Lookup.determine(@locale, display_value.display_string, @numbers))
  end

  def feature_value("gender", display_value, _constraints) do
    empty_to_nil(Lookup.determine(@locale, display_value.display_string, @genders))
  end

  def feature_value("definiteness", display_value, _constraints) do
    display_string = display_value.display_string
    lowercased = String.downcase(display_string)

    cond do
      display_string == "" ->
        nil

      String.starts_with?(lowercased, ["de ", "het "]) ->
        "definite"

      String.starts_with?(lowercased, "een ") ->
        "indefinite"

      true ->
        empty_to_nil(Lookup.determine(@locale, display_string, ["definite", "indefinite"]))
    end
  end

  def feature_value("defArticle", display_value, _constraints) do
    definite_article(display_value, false)
  end

  def feature_value(_feature, _display_value, _constraints), do: nil

  # ── de/het article choice ────────────────────────────────────

  defp definite_article(display_value, include?) do
    count = parse(Map.get(display_value.constraints, "number"), @numbers)
    gender = parse(Map.get(display_value.constraints, "gender"), @genders)
    diminutive? = Map.get(display_value.constraints, "sizeness") == "diminutive"

    {count, gender, diminutive?} =
      if count == nil or gender == nil do
        deduce_article_features(display_value.display_string, count, gender, diminutive?)
      else
        {count, gender, diminutive?}
      end

    article =
      if count == "singular" and (gender == "neuter" or diminutive?) do
        "het"
      else
        "de"
      end

    Articles.create_preposition(display_value, article, include?)
  end

  defp deduce_article_features(display_string, count, gender, diminutive?) do
    phrase_type =
      case Dictionary.combined_grammemes(@locale, display_string) do
        nil ->
          case significant_noun(display_string) do
            "" ->
              0

            noun ->
              Dictionary.combined_grammemes(@locale, noun) ||
                Dictionary.combined_grammemes(@locale, decompound(noun)) || 0
          end

        properties ->
          properties
      end

    if phrase_type != 0 do
      plural = Dictionary.binary_properties(@locale, ["plural"]) || 0
      gender_mask = Dictionary.binary_properties(@locale, @genders) || 0

      count = count || if((phrase_type &&& plural) != 0, do: "plural", else: "singular")
      gender = gender || Dictionary.property_name(@locale, phrase_type &&& gender_mask)
      diminutive? = diminutive? or diminutive_word?(display_string, phrase_type)
      {count, gender, diminutive?}
    else
      {count, gender, diminutive?}
    end
  end

  defp diminutive_word?(word, phrase_type) do
    diminutive = Dictionary.binary_properties(@locale, ["diminutive"]) || 0

    if diminutive != 0 and (phrase_type &&& diminutive) != 0 do
      true
    else
      base = guess_diminutive(word)
      base != "" and Dictionary.combined_grammemes(@locale, base) != nil
    end
  end

  # The last noun of the leading adjective+noun(+s) run, or the
  # last word.
  defp significant_noun(phrase) do
    tokens = Tokenizer.word_tokens(@locale, phrase)
    words = Enum.map(tokens, & &1.value)

    if words == [] do
      ""
    else
      adjective = Dictionary.binary_properties(@locale, ["adjective"]) || 0
      noun = Dictionary.binary_properties(@locale, ["noun"]) || 0

      after_adjectives =
        Enum.drop_while(words, &Dictionary.has_all_properties?(@locale, &1, adjective))

      {noun_run, _rest} =
        Enum.split_while(after_adjectives, fn word ->
          noun_word(word, noun) != nil or word == "s"
        end)

      last_noun =
        noun_run
        |> Enum.reverse()
        |> Enum.find_value(&noun_word(&1, noun))

      last_noun || List.last(words)
    end
  end

  # A known noun, or an unknown compound whose decompounded suffix
  # is a known noun (returned as the noun to use).
  defp noun_word(word, noun_mask) do
    cond do
      Dictionary.has_all_properties?(@locale, word, noun_mask) ->
        word

      Dictionary.combined_grammemes(@locale, word) == nil ->
        suffix = decompound(word)

        if suffix != word and Dictionary.has_all_properties?(@locale, suffix, noun_mask) do
          suffix
        end

      true ->
        nil
    end
  end

  # The upstream Dutch tokenizer decompounds unknown words with a
  # dedicated dictionary; the longest known dictionary suffix (a
  # noun of a compound) is a workable approximation.
  defp decompound(word) do
    length = String.length(word)

    Enum.find_value(1..max(length - 3, 1), word, fn start ->
      suffix = String.slice(word, start, length - start)
      if Dictionary.combined_grammemes(@locale, suffix) != nil, do: suffix
    end)
  end

  # ── Diminutive stripping ─────────────────────────────────────

  @doc false
  def guess_diminutive(word) do
    guess =
      if String.ends_with?(word, "jes") do
        String.slice(word, 0..-2//1)
      else
        word
      end

    length = String.length(guess)

    if length > 2 and String.ends_with?(guess, "je") do
      strip_diminutive(guess, length)
    else
      ""
    end
  end

  defp strip_diminutive(guess, length) do
    at = fn index -> String.at(guess, length + index) end

    cond do
      length > 3 and at.(-3) == "p" and at.(-4) == "m" ->
        String.slice(guess, 0, length - 3)

      length > 4 and at.(-3) == "k" and at.(-4) == "n" and at.(-5) == "i" ->
        String.slice(guess, 0, length - 3) <> "g"

      length > 3 and at.(-3) == "t" ->
        strip_tje(guess, length, at)

      at.(-3) == "'" ->
        String.slice(guess, 0, length - 3)

      true ->
        String.slice(guess, 0, length - 2)
    end
  end

  defp strip_tje(guess, length, at) do
    blnmrp = ~w(b l n m r p g)

    cond do
      at.(-4) == "'" ->
        String.slice(guess, 0, length - 4)

      length > 7 and at.(-4) == "e" and
          (at.(-5) in blnmrp or (at.(-5) == "g" and at.(-6) == "n")) ->
        if at.(-6) == at.(-5) and vowel_at?(guess, length - 7) do
          String.slice(guess, 0, length - 5)
        else
          String.slice(guess, 0, length - 4)
        end

      vowel_at?(guess, length - 4) ->
        if length > 4 and at.(-4) == at.(-5) do
          String.slice(guess, 0, length - 4)
        else
          String.slice(guess, 0, length - 3)
        end

      at.(-4) in ~w(l r n) ->
        String.slice(guess, 0, length - 3)

      true ->
        ""
    end
  end

  defp vowel_at?(string, index) when index >= 0 do
    char = String.at(string, index)

    char in ~w(a e i o u) or
      (index > 0 and char == "j" and String.at(string, index - 1) == "i")
  end

  defp vowel_at?(_string, _index), do: false

  # ── Inflection patterns ──────────────────────────────────────

  defp noun_inflect(display_string, word_grammemes, constraints) do
    if genitive_requested?(display_string, constraints) do
      inflect_genitive(display_string, constraints)
    else
      pos = Map.get(constraints, "pos", "")
      count = parse(Map.get(constraints, "number"), @numbers)
      noun = Dictionary.binary_properties(@locale, ["noun"]) || 0

      cond do
        count == nil or (word_grammemes &&& noun) == 0 or (pos != "" and pos != "noun") ->
          ""

        map_size(constraints) == 1 and has_number?(word_grammemes, count) ->
          display_string

        true ->
          reinflect_with_pos(display_string, word_grammemes, count, "noun")
      end
    end
  end

  defp verb_inflect(display_string, word_grammemes, constraints) do
    pos = Map.get(constraints, "pos", "")
    count = parse(Map.get(constraints, "number"), @numbers)
    verb = Dictionary.binary_properties(@locale, ["verb"]) || 0

    cond do
      count == nil or (word_grammemes &&& verb) == 0 or (pos != "" and pos != "verb") ->
        ""

      map_size(constraints) == 1 and has_number?(word_grammemes, count) ->
        display_string

      true ->
        reinflect_with_pos(display_string, word_grammemes, count, "verb")
    end
  end

  defp has_number?(word_grammemes, count) do
    mask = Dictionary.binary_properties(@locale, [count]) || 0
    (word_grammemes &&& mask) == mask and mask != 0
  end

  defp reinflect_with_pos(display_string, word_grammemes, count, pos) do
    pos_mask = Dictionary.binary_properties(@locale, [pos]) || 0
    to_mask = Dictionary.binary_properties(@locale, [count]) || 0

    @locale
    |> Dictionary.patterns_for_word(display_string)
    |> Enum.filter(&((&1.pos_mask &&& pos_mask) != 0))
    |> Enum.find_value("", fn pattern ->
      case Inflector.reinflect(pattern, word_grammemes, to_mask, [], display_string) do
        {:ok, ""} -> nil
        {:ok, inflected} -> inflected
        :error -> nil
      end
    end)
  end

  defp adjective_inflect(display_string, word_grammemes, constraints) do
    declension = Map.get(constraints, "declension")
    adjective = Dictionary.binary_properties(@locale, ["adjective"]) || 0

    if declension in ["declined", "undeclined"] and (word_grammemes &&& adjective) != 0 do
      inflect_with_declension(display_string, declension)
    else
      ""
    end
  end

  defp inflect_with_declension(lemma, "undeclined"), do: lemma
  defp inflect_with_declension(lemma, "declined"), do: heuristic_declension(lemma)
  defp inflect_with_declension(_lemma, _declension), do: ""

  # Add "-e" with Dutch spelling adjustments (rood→rode, wit→witte,
  # boos→boze).
  defp heuristic_declension(lemma) do
    length = String.length(lemma)

    cond do
      length < 2 ->
        lemma

      String.ends_with?(lemma, ["en", "e"]) ->
        lemma

      length >= 3 ->
        c1 = String.at(lemma, length - 1)
        c2 = String.at(lemma, length - 2)
        c3 = String.at(lemma, length - 3)

        cond do
          combined_vowel?(c3, c2) and not simple_vowel?(c1) ->
            c1 = if c1 == "s", do: "z", else: c1

            if c2 == c3 do
              String.slice(lemma, 0, length - 2) <> c1 <> "e"
            else
              String.slice(lemma, 0, length - 1) <> c1 <> "e"
            end

          not String.ends_with?(lemma, "ij") and not simple_vowel?(c3) and simple_vowel?(c2) and
              not simple_vowel?(c1) ->
            lemma <> c1 <> "e"

          true ->
            lemma <> "e"
        end

      true ->
        lemma <> "e"
    end
  end

  defp simple_vowel?(char) when is_binary(char) and byte_size(char) == 1 do
    :binary.first(char) in @vowels
  end

  defp simple_vowel?(_char), do: false

  defp combined_vowel?(c1, c2) do
    (simple_vowel?(c1) and c1 == c2) or
      {c1, c2} in [{"i", "j"}, {"e", "i"}, {"i", "e"}, {"o", "e"}, {"o", "u"}, {"a", "u"}]
  end

  defp inflect_with_definiteness(word, noun_gender, definiteness, declension) do
    adjective = Dictionary.binary_properties(@locale, ["adjective"]) || 0

    from_dictionary =
      if definiteness != "" do
        to_mask =
          if noun_gender == "neuter" and definiteness == "indefinite" do
            Dictionary.binary_properties(@locale, ["indefinite", "neuter"]) || 0
          else
            Dictionary.binary_properties(@locale, ["definite"]) || 0
          end

        @locale
        |> Dictionary.patterns_for_word(word)
        |> Enum.filter(&((&1.pos_mask &&& adjective) != 0))
        |> Enum.find_value(fn pattern ->
          case Inflector.reinflect(pattern, 0, to_mask, [], word) do
            {:ok, ""} -> nil
            {:ok, inflected} -> inflected
            :error -> nil
          end
        end)
      end

    cond do
      from_dictionary ->
        from_dictionary

      declension == "undeclined" ->
        case undecline_adjective(word) do
          "" -> inflect_with_declension(word, declension)
          undeclined -> undeclined
        end

      true ->
        inflect_with_declension(word, declension)
    end
  end

  # Undeclension reverses spelling (rode→rood) so it must go
  # through the dictionary.
  defp undecline_adjective(word) do
    comparison =
      Dictionary.binary_properties(@locale, ["positive", "comparative", "superlative"]) || 0

    adjective = Dictionary.binary_properties(@locale, ["adjective"]) || 0
    degree = (Dictionary.combined_grammemes(@locale, word) || 0) &&& comparison

    if degree == 0 do
      ""
    else
      @locale
      |> Dictionary.patterns_for_word(word)
      |> Enum.filter(&((&1.pos_mask &&& adjective) != 0))
      |> Enum.find_value("", fn pattern ->
        case Inflector.reinflect(pattern, 0, degree, [], word) do
          {:ok, ""} -> nil
          {:ok, base} -> base
          :error -> nil
        end
      end)
    end
  end

  # ── Genitive (possessive) ────────────────────────────────────

  defp genitive_requested?(display_string, constraints) do
    Map.get(constraints, "case") == "genitive" and
      (display_string not in ["ze", "zij"] or Map.get(constraints, "number") != nil) and
      (display_string not in ["ons", "we", "wij"] or Map.get(constraints, "declension") != nil)
  end

  defp inflect_genitive(display_string, constraints) do
    cond do
      Map.has_key?(@possessive_pronouns, display_string) ->
        Map.fetch!(@possessive_pronouns, display_string)

      display_string in ["ze", "zij"] ->
        case Map.get(constraints, "number") do
          "singular" -> "haar"
          "plural" -> "hun"
          _other -> ""
        end

      display_string in ["ons", "we", "wij"] ->
        case Map.get(constraints, "declension") do
          "undeclined" -> "ons"
          "declined" -> "onze"
          _other -> ""
        end

      String.length(display_string) > 2 ->
        name_possessive(display_string)

      true ->
        ""
    end
  end

  defp name_possessive(name) do
    cond do
      possessive?(name) -> name
      String.ends_with?(name, ["'", "’"]) -> name <> "s"
      dutch_s_sound?(name) -> name <> "’"
      true -> name <> "’s"
    end
  end

  defp possessive?(text) do
    lowercased = String.downcase(text)

    String.ends_with?(lowercased, ["'s", "’s"]) or
      (String.ends_with?(lowercased, ["'", "’"]) and
         dutch_s_sound?(String.slice(lowercased, 0..-2//1)))
  end

  defp dutch_s_sound?(text) do
    text |> String.downcase() |> String.ends_with?(["s", "z", "sch", "x", "sh"])
  end

  # ── Display function ─────────────────────────────────────────

  @impl true
  def display_value(display_data, constraints, _guess?) do
    with %DisplayValue{} = display_value <- List.first(display_data),
         display_string when display_string != "" <- display_value.display_string do
      display_string =
        if map_size(constraints) > 0 do
          word_grammemes = Dictionary.combined_grammemes(@locale, display_string) || 0

          inflected =
            first_non_empty([
              fn -> noun_inflect(display_string, word_grammemes, constraints) end,
              fn -> adjective_inflect(display_string, word_grammemes, constraints) end,
              fn -> verb_inflect(display_string, word_grammemes, constraints) end,
              fn ->
                if word_grammemes == 0 do
                  inflect_phrase(display_string, constraints)
                else
                  ""
                end
              end
            ])

          if inflected == "", do: display_string, else: inflected
        else
          display_string
        end

      Articles.add_definiteness(
        %DisplayValue{display_string: display_string, constraints: constraints},
        constraints,
        Articles.article_prefixes(@locale, ["de"]),
        Articles.article_prefixes(@locale, ["indefArticle"]),
        fn base, _constraints -> definite_article(base, true) end,
        fn base, _constraints -> static_indefinite_article(base) end
      )
    else
      _other -> nil
    end
  end

  defp static_indefinite_article(display_value) do
    display_string = display_value.display_string

    if display_string != "" and
         not String.starts_with?(String.downcase(display_string), "een ") do
      Articles.create_preposition(display_value, "een", true)
    else
      Articles.create_preposition(display_value, "", true)
    end
  end

  defp first_non_empty(functions) do
    Enum.find_value(functions, "", fn function ->
      case function.() do
        "" -> nil
        result -> result
      end
    end)
  end

  defp inflect_phrase(display_string, constraints) do
    tokens = Tokenizer.word_tokens(@locale, display_string)
    noun = Dictionary.binary_properties(@locale, ["noun"]) || 0
    adjective = Dictionary.binary_properties(@locale, ["adjective"]) || 0

    analysis =
      Enum.reduce_while(tokens, {false, false}, fn token, {last_noun?, adjectives?} ->
        grammemes = Dictionary.combined_grammemes(@locale, token.value)

        cond do
          grammemes == nil or (grammemes &&& (noun ||| adjective)) == 0 ->
            {:halt, :unsupported}

          (grammemes &&& adjective) != 0 and last_noun? ->
            {:halt, :unsupported}

          (grammemes &&& adjective) != 0 ->
            {:cont, {last_noun?, true}}

          last_noun? ->
            {:halt, :unsupported}

          true ->
            {:cont, {true, adjectives?}}
        end
      end)

    case analysis do
      :unsupported ->
        ""

      {true, _adjectives?} ->
        inflect_adjectives_and_noun(display_string, tokens, constraints)

      {false, true} ->
        inflect_adjectives_only(display_string, tokens, constraints)

      _other ->
        ""
    end
  end

  defp inflect_adjectives_and_noun(display_string, tokens, constraints) do
    head_token = List.last(tokens)
    head_grammemes = Dictionary.combined_grammemes(@locale, head_token.value) || 0

    head_inflection = noun_inflect(head_token.value, head_grammemes, constraints)
    head = if head_inflection == "", do: head_token.value, else: head_inflection

    count = parse(Map.get(constraints, "number"), @numbers)
    gender_mask = Dictionary.binary_properties(@locale, @genders) || 0
    gender = Dictionary.property_name(@locale, head_grammemes &&& gender_mask)
    definiteness = Map.get(constraints, "definiteness", "")
    declension = adjective_declension(count, gender, definiteness)

    adjectives =
      Enum.reduce_while(Enum.slice(tokens, 0..-2//1), [], fn token, acc ->
        inflected = inflect_with_definiteness(token.value, gender, definiteness, declension)

        if inflected == "" do
          {:halt, :error}
        else
          {:cont, [inflected | acc]}
        end
      end)

    case adjectives do
      :error ->
        ""

      list ->
        words = Enum.reverse([head | list])
        rebuild(display_string, tokens, words)
    end
  end

  defp inflect_adjectives_only(display_string, tokens, constraints) do
    declension = Map.get(constraints, "declension")

    words =
      Enum.map(tokens, fn token ->
        case inflect_with_declension(token.value, declension) do
          "" -> token.value
          inflected -> inflected
        end
      end)

    rebuild(display_string, tokens, words)
  end

  defp adjective_declension(count, gender, definiteness) do
    cond do
      definiteness == "definite" -> "declined"
      definiteness == "indefinite" and gender == "neuter" and count != "plural" -> "undeclined"
      definiteness == "indefinite" -> "declined"
      count == nil -> nil
      count == "plural" -> "declined"
      count == "singular" and gender == nil -> nil
      count == "singular" and gender == "neuter" -> "undeclined"
      count == "singular" -> "declined"
      true -> nil
    end
  end

  defp rebuild(display_string, tokens, words) do
    {output, position} =
      tokens
      |> Enum.zip(words)
      |> Enum.reduce({"", 0}, fn {token, word}, {output, position} ->
        separator = binary_part(display_string, position, token.start - position)
        {output <> separator <> word, token.stop}
      end)

    output <> binary_part(display_string, position, byte_size(display_string) - position)
  end

  defp parse(value, _allowed) when value in [nil, ""], do: nil
  defp parse(value, allowed), do: if(value in allowed, do: value)

  defp empty_to_nil(""), do: nil
  defp empty_to_nil(value), do: value
end
