defmodule Localize.Inflection.Synthesizer.It do
  @moduledoc false

  # The per-language synthesizers and conformance harnesses are ported
  # from the upstream C++ linguistic rule tables; their branchiness and
  # nesting mirror the reference implementation they are verified
  # against (see guides/inflection.md).
  # credo:disable-for-this-file Credo.Check.Refactor.CyclomaticComplexity
  # credo:disable-for-this-file Credo.Check.Refactor.Nesting

  # The Italian grammar synthesizer, ported from
  # `ItGrammarSynthesizer` and its lookup and display functions.
  # Masculine articles are three-way (il/lo/l’) driven by s-impura
  # and elision phonology, with digit pronunciation awareness.

  @behaviour Localize.Inflection.Synthesizer

  alias Localize.Inflection.{
    Articles,
    Dictionary,
    DisplayValue,
    GrammemeLookup,
    Inflector,
    PhraseProperties,
    Tokenizer
  }

  import Bitwise

  @locale :it

  @number_tags ["singular", "plural"]
  @gender_tags ["masculine", "feminine"]
  @number_disambiguation ["noun", "adjective", "article", "verb"]
  @gender_disambiguation ["noun", "adjective"]

  @priorities [
    ["noun", "adjective", "article", "verb"],
    ["third", "first", "second"],
    ["singular", "plural"],
    ["masculine", "feminine"]
  ]

  # {derived, simple, sg_m, sg_m_cons, sg_f, sg_vowel, pl_m, pl_m_cons, pl_f}
  @definite_articles %{
    "defArticle" => {nil, "", "il ", "lo ", "la ", "l’", "i ", "gli ", "le "},
    "aPrepArticle" => {nil, "a ", "al ", "allo ", "alla ", "all’", "ai ", "agli ", "alle "},
    "withAPrepArticle" =>
      {"aPrepArticle", "a ", "al ", "allo ", "alla ", "all’", "ai ", "agli ", "alle "},
    "daPrepArticle" =>
      {nil, "da ", "dal ", "dallo ", "dalla ", "dall’", "dai ", "dagli ", "dalle "},
    "withDaPrepArticle" =>
      {"daPrepArticle", "da ", "dal ", "dallo ", "dalla ", "dall’", "dai ", "dagli ", "dalle "},
    "dePrepArticle" =>
      {nil, "di ", "del ", "dello ", "della ", "dell’", "dei ", "degli ", "delle "},
    "withDePrepArticle" =>
      {"dePrepArticle", "di ", "del ", "dello ", "della ", "dell’", "dei ", "degli ", "delle "},
    "inPrepArticle" =>
      {nil, "in ", "nel ", "nello ", "nella ", "nell’", "nei ", "negli ", "nelle "},
    "withInPrepArticle" =>
      {"inPrepArticle", "in ", "nel ", "nello ", "nella ", "nell’", "nei ", "negli ", "nelle "},
    "suPrepArticle" =>
      {nil, "su ", "sul ", "sullo ", "sulla ", "sull’", "sui ", "sugli ", "sulle "},
    "withSuPrepArticle" =>
      {"suPrepArticle", "su ", "sul ", "sullo ", "sulla ", "sull’", "sui ", "sugli ", "sulle "}
  }

  @impl true
  def feature_value(feature, display_value, constraints)

  def feature_value("number", display_value, _constraints) do
    empty_to_nil(determine_number(display_value.display_string))
  end

  def feature_value("gender", display_value, _constraints) do
    empty_to_nil(determine_gender(display_value.display_string))
  end

  def feature_value("definiteness", display_value, _constraints) do
    Articles.detect_definiteness(
      @locale,
      display_value,
      Articles.article_prefixes(
        @locale,
        [
          "defArticle",
          "dePrepArticle",
          "aPrepArticle",
          "daPrepArticle",
          "inPrepArticle",
          "suPrepArticle"
        ],
        ["a ", "da ", "de ", "di ", "in ", "su "]
      ),
      Articles.article_prefixes(@locale, ["indefArticle"])
    )
  end

  def feature_value("indefArticle", display_value, _constraints) do
    indefinite_article(display_value, false)
  end

  def feature_value(feature, display_value, _constraints)
      when is_map_key(@definite_articles, feature) do
    {derived, _simple, _sm, _smc, _sf, _sv, _pm, _pmc, _pf} =
      Map.fetch!(@definite_articles, feature)

    definite_article(feature, display_value, derived != nil)
  end

  def feature_value(_feature, _display_value, _constraints), do: nil

  defp determine_number(phrase) do
    GrammemeLookup.determine(@locale, phrase, @number_tags,
      disambiguation: @number_disambiguation,
      first_word_determines?: true,
      suffix_function: &guess_number_by_suffix/1
    )
  end

  defp guess_number_by_suffix(word) do
    cond do
      digit_start?(word) -> "singular"
      String.ends_with?(word, ["a", "o"]) -> "singular"
      String.ends_with?(word, "i") -> "plural"
      true -> ""
    end
  end

  defp determine_gender(phrase) do
    GrammemeLookup.determine(@locale, phrase, @gender_tags,
      disambiguation: @gender_disambiguation,
      first_word_determines?: true,
      suffix_function: &guess_gender_by_suffix/1
    )
  end

  defp guess_gender_by_suffix(word) do
    cond do
      digit_start?(word) ->
        if feminine_ordinal_suffix?(word), do: "feminine", else: "masculine"

      String.ends_with?(word, ["zione", "sione", "gione", "si", "à", "ù", "trice", "tudine"]) ->
        "feminine"

      String.ends_with?(word, ["amma", "ema", "ore", "è", "ì", "ò", "i", "o"]) ->
        "masculine"

      String.ends_with?(word, ["a", "e"]) ->
        "feminine"

      true ->
        ""
    end
  end

  # ── Phonology ────────────────────────────────────────────────

  defp digit_start?(<<c::utf8, _rest::binary>>) when c in ?0..?9, do: true
  defp digit_start?(_word), do: false

  defp leading_number(word) do
    case Integer.parse(word) do
      {number, _rest} when number >= 0 -> number
      _other -> -1
    end
  end

  defp ordinal_suffix?(word), do: after_digits(word) in ["º", "ª"]

  defp feminine_ordinal_suffix?(word), do: after_digits(word) == "ª"

  defp after_digits(<<c::utf8, rest::binary>>) when c in ?0..?9, do: after_digits(rest)
  defp after_digits(<<c::utf8, _rest::binary>>), do: <<c::utf8>>
  defp after_digits(<<>>), do: ""

  # Whether a leading number is pronounced with an initial vowel
  # (otto, undici, ottanta…).
  defp vowel_digits?(word) do
    number = leading_number(word)

    if number < 0 do
      false
    else
      number = reduce_millions(number)

      if number >= 1000 and number < 2000 do
        false
      else
        number = if number >= 1000, do: div(number, 1000), else: number

        if number >= 100 and number < 200 do
          false
        else
          vowel_number?(if(number >= 100, do: div(number, 100), else: number), word)
        end
      end
    end
  end

  defp reduce_millions(number) when number >= 1_000_000,
    do: reduce_millions(div(number, 1_000_000))

  defp reduce_millions(number), do: number

  defp vowel_number?(1, word), do: not ordinal_suffix?(word)
  defp vowel_number?(number, _word), do: number == 8 or number == 11 or number in 80..89

  # s-impura, gn-, ps-, pn-, x/y/z — the lo/gli/uno trigger.
  defp consonant_subset?(word) do
    case String.next_codepoint(word) do
      nil ->
        false

      {<<c::utf8>>, rest} when c in ?0..?9 ->
        _ = rest
        leading_number(word) == 0

      {first, rest} ->
        case {rest, String.next_codepoint(rest)} do
          {"", _next} ->
            false

          {_rest, {second, _tail}} ->
            <<c1::utf8>> = String.downcase(first)
            <<c2::utf8>> = String.downcase(second)

            (c1 == ?p and c2 in [?n, ?s]) or (c1 == ?g and c2 == ?n) or c1 in [?x, ?y, ?z] or
              (c1 == ?s and not PhraseProperties.default_vowel?(c2))

          _other ->
            false
        end
    end
  end

  # Elision (l’, all’, un’) phonology.
  defp vowel_for_elision?(""), do: false

  defp vowel_for_elision?(word) do
    {first, rest} = String.next_codepoint(word)
    <<c1::utf8>> = String.downcase(first)

    cond do
      c1 in ?0..?9 ->
        vowel_digits?(word)

      rest == "" ->
        false

      c1 == ?i ->
        {second, _rest} = String.next_codepoint(rest)
        <<c2::utf8>> = String.downcase(second)
        not PhraseProperties.default_vowel?(c2)

      c1 == ?h ->
        {second, _rest} = String.next_codepoint(rest)
        <<c2::utf8>> = String.downcase(second)
        PhraseProperties.default_vowel?(c2)

      true ->
        PhraseProperties.starts_with_vowel?(@locale, word)
    end
  end

  # ── Article selection ────────────────────────────────────────

  defp definite_article(feature, display_value, include?) do
    {derived, _simple, sg_m, sg_m_cons, sg_f, sg_vowel, pl_m, pl_m_cons, pl_f} =
      Map.fetch!(@definite_articles, feature)

    derived_value = derived && Map.get(display_value.constraints, derived)

    if derived_value do
      Articles.create_preposition(display_value, derived_value, include?, false)
    else
      {count, gender} = count_and_gender(display_value)
      forms = {sg_m, sg_m_cons, sg_f, sg_vowel, pl_m, pl_m_cons, pl_f}
      article = select_definite_article(count, gender, display_value.display_string, forms)
      Articles.create_preposition(display_value, article, include?, false)
    end
  end

  defp select_definite_article(count, gender, display_string, forms) do
    {sg_m, sg_m_cons, sg_f, sg_vowel, pl_m, pl_m_cons, pl_f} = forms

    cond do
      gender == "feminine" and count == "plural" ->
        pl_f

      gender == "feminine" and vowel_for_elision?(display_string) ->
        sg_vowel

      gender == "feminine" ->
        sg_f

      count == "plural" and
          (PhraseProperties.starts_with_vowel?(@locale, display_string) or
             consonant_subset?(display_string)) ->
        pl_m_cons

      count == "plural" ->
        pl_m

      vowel_for_elision?(display_string) ->
        sg_vowel

      consonant_subset?(display_string) ->
        sg_m_cons

      count == "singular" and gender == "masculine" ->
        sg_m

      true ->
        ""
    end
  end

  defp indefinite_article(display_value, include?) do
    {count, gender} = count_and_gender(display_value)
    display_string = display_value.display_string

    article =
      cond do
        gender == "feminine" and count == "plural" ->
          "delle "

        gender == "feminine" and PhraseProperties.starts_with_vowel?(@locale, display_string) ->
          "un’"

        gender == "feminine" ->
          "una "

        count == "plural" and
            (PhraseProperties.starts_with_vowel?(@locale, display_string) or
               consonant_subset?(display_string)) ->
          "degli "

        count == "plural" ->
          "dei "

        consonant_subset?(display_string) ->
          "uno "

        count == "singular" and gender == "masculine" ->
          "un "

        true ->
          ""
      end

    Articles.create_preposition(display_value, article, include?, false)
  end

  defp count_and_gender(display_value) do
    display_string = display_value.display_string

    count =
      parse(Map.get(display_value.constraints, "number"), @number_tags) ||
        parse(determine_number(display_string), @number_tags)

    gender =
      parse(Map.get(display_value.constraints, "gender"), @gender_tags) ||
        parse(determine_gender(display_string), @gender_tags)

    {count, gender}
  end

  defp parse(value, _allowed) when value in [nil, ""], do: nil
  defp parse(value, allowed), do: if(value in allowed, do: value)

  # ── Display function ─────────────────────────────────────────

  @impl true
  def display_value(display_data, constraints, guess?) do
    with %DisplayValue{} = display_value <- List.first(display_data),
         display_string when display_string != "" <- display_value.display_string do
      value_constraints = Map.merge(display_value.constraints, constraints)

      inflected =
        if Map.get(constraints, "number") || Map.get(constraints, "gender") do
          inflect_string(display_string, constraints, value_constraints, guess?)
        else
          {:ok, display_string}
        end

      case inflected do
        :error ->
          nil

        {:ok, display_string} ->
          Articles.update_definiteness(
            %DisplayValue{display_string: display_string, constraints: value_constraints},
            value_constraints,
            Articles.article_prefixes(@locale, ["defArticle"]),
            Articles.article_prefixes(@locale, ["indefArticle"]),
            fn base, _constraints -> definite_article("defArticle", base, true) end,
            fn base, _constraints -> indefinite_article(base, true) end
          )
      end
    else
      _other -> nil
    end
  end

  defp inflect_string(display_string, constraints, value_constraints, guess?) do
    known? = Dictionary.combined_grammemes(@locale, display_string) != nil
    tokens = Tokenizer.word_tokens(@locale, display_string)

    if known? or length(tokens) == 1 do
      word_type = Dictionary.combined_grammemes(@locale, display_string) || 0
      inflect_word(display_string, word_type, constraints, guess?)
    else
      inflect_compound(display_string, tokens, value_constraints, guess?)
    end
  end

  defp inflect_word(word, word_type, constraints, guess?) do
    constraint_values =
      for value <- [Map.get(constraints, "number"), Map.get(constraints, "gender")],
          value not in [nil, ""],
          do: value

    disambiguation = for value <- [Map.get(constraints, "pos")], value not in [nil, ""], do: value
    options = [disambiguation: disambiguation, priorities: @priorities]

    verb = Dictionary.binary_properties(@locale, ["verb"]) || 0

    case Inflector.inflect(@locale, word, word_type, constraint_values, options) do
      {:ok, inflected} ->
        if (word_type &&& verb) == 0 or verb_compatible?(inflected, word_type) do
          {:ok, inflected}
        else
          {:ok, word}
        end

      :error when guess? ->
        {:ok, word}

      :error ->
        :error
    end
  end

  # Never reinflect a verb across the past-participle boundary.
  defp verb_compatible?(inflected, word_type) do
    verb = Dictionary.binary_properties(@locale, ["verb"]) || 0
    important = Dictionary.binary_properties(@locale, ["past", "participle"]) || 0
    inflected_type = Dictionary.combined_grammemes(@locale, inflected) || 0

    (inflected_type &&& verb) == 0 or
      (word_type &&& important) == (inflected_type &&& important)
  end

  defp inflect_compound(display_string, tokens, constraints, guess?) do
    adposition = Dictionary.binary_properties(@locale, ["adposition"]) || 0

    {result, _position, _prep?, _first?} =
      Enum.reduce_while(tokens, {"", 0, false, true}, fn token,
                                                         {output, position, prep?, first?} ->
        separator = binary_part(display_string, position, token.start - position)
        word_type = Dictionary.combined_grammemes(@locale, token.value) || 0

        cond do
          prep? or (first? and String.downcase(token.value) == "l") ->
            {:cont, {output <> separator <> token.value, token.stop, prep?, false}}

          (word_type &&& adposition) != 0 ->
            {:cont, {output <> separator <> token.value, token.stop, true, false}}

          true ->
            case inflect_word(token.value, word_type, constraints, guess?) do
              {:ok, inflected} ->
                {:cont, {output <> separator <> inflected, token.stop, prep?, false}}

              :error ->
                {:halt, {:error, position, prep?, false}}
            end
        end
      end)

    case result do
      :error ->
        :error

      output ->
        tail_start =
          case List.last(tokens) do
            nil -> 0
            token -> token.stop
          end

        {:ok,
         output <> binary_part(display_string, tail_start, byte_size(display_string) - tail_start)}
    end
  end

  defp empty_to_nil(""), do: nil
  defp empty_to_nil(value), do: value
end
