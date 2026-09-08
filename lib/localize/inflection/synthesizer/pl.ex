defmodule Localize.Inflection.Synthesizer.Pl do
  @moduledoc false

  # The per-language synthesizers and conformance harnesses are ported
  # from the upstream C++ linguistic rule tables; their branchiness and
  # nesting mirror the reference implementation they are verified
  # against (see guides/inflection.md).
  # credo:disable-for-this-file Credo.Check.Refactor.CyclomaticComplexity
  # credo:disable-for-this-file Credo.Check.Refactor.Nesting

  # The Polish grammar synthesizer, ported from
  # `PlGrammarSynthesizer`. Plural agreement splits into virile
  # (human) and non-virile forms; the display function inflects the
  # head noun and the modifiers before it, and can prepend a
  # vocalised preposition via the withPreposition feature.

  @behaviour Localize.Inflection.Synthesizer

  alias Localize.Inflection.{
    Data,
    Dictionary,
    DisplayValue,
    Inflector,
    Lookup,
    PhraseProperties,
    Tokenizer
  }

  import Bitwise

  @locale :pl

  @genders ["masculine", "feminine", "neuter"]
  @numbers ["singular", "plural"]
  @cases ~w(nominative genitive dative accusative instrumental locative vocative)
  @animacies ["animate", "inanimate", "human"]

  @priorities [
    ["numeral", "noun", "pronoun", "adjective", "verb"],
    @cases,
    ["singular", "plural"],
    @genders,
    ["human", "nonhuman", "animate", "inanimate"]
  ]

  @max_suffix_length 7
  @min_stem_length 2

  # {preposition, prefix_letters, prefixes, words} — words are
  # prefix-matched.
  @prepositions %{
    "bez" => {[], [], ["mnie"]},
    "nad" => {[], [], ["mną", "mnie", "wszystko"]},
    "od" => {[], [], ["mnie"]},
    "pod" => {[], [], ["mną", "mnie"]},
    "przed" => {[], [], ["mną", "mnie", "wszystkim"]},
    "przez" => {[], [], ["mnie"]},
    "w" => {["f", "w"], [], ["mnie"]},
    "z" => {["z", "ź", "ś", "s"], ["ws", "wz"], ["mną", "dwoje"]}
  }

  @lookups %{
    "gender" => @genders,
    "number" => @numbers,
    "case" => @cases,
    "animacy" => @animacies
  }

  @impl true
  def feature_value(feature, display_value, _constraints) when is_map_key(@lookups, feature) do
    case Lookup.determine(@locale, display_value.display_string, Map.fetch!(@lookups, feature)) do
      "" -> nil
      value -> value
    end
  end

  def feature_value(_feature, _display_value, _constraints), do: nil

  # ── Preposition vocalisation ─────────────────────────────────

  @doc false
  def preposition(preposition, word) do
    case Map.get(@prepositions, preposition) do
      nil ->
        preposition

      {prefix_letters, prefixes, words} ->
        lowercased = String.downcase(word)

        vocalise? =
          String.length(lowercased) > 1 and
            (two_consonant?(lowercased, prefix_letters) or
               String.starts_with?(lowercased, prefixes) or
               String.starts_with?(lowercased, words))

        if vocalise?, do: preposition <> "e", else: preposition
    end
  end

  defp two_consonant?(_word, []), do: false

  defp two_consonant?(word, prefix_letters) do
    {first, rest} = String.next_codepoint(word)

    with true <- first in prefix_letters,
         {second, _rest} when not is_nil(second) <- String.next_codepoint(rest),
         <<c2::utf8>> <- second do
      not PhraseProperties.default_vowel?(c2)
    else
      _other -> false
    end
  end

  # ── Word inflection with prefix stripping and exemplar guess ─

  defp inflect_word(word, word_type, constraint_values, disambiguation, guess?) do
    from_dictionary =
      if word_type != 0 do
        options = [disambiguation: disambiguation, priorities: @priorities, fallback: false]

        case Inflector.inflect(@locale, word, word_type, constraint_values, options) do
          {:ok, inflected} -> inflected
          :error -> nil
        end
      end

    from_dictionary ||
      strip_prefix_inflection(word, constraint_values, disambiguation) ||
      exemplar_guess(word, word_type, constraint_values, disambiguation, guess?)
  end

  defp strip_prefix_inflection(word, constraint_values, disambiguation) do
    lowercased = String.downcase(word)

    Enum.find_value(["nie", "naj"], fn prefix ->
      with true <- String.starts_with?(lowercased, prefix),
           rest = binary_part(word, byte_size(prefix), byte_size(word) - byte_size(prefix)),
           grammemes when is_integer(grammemes) <- Dictionary.combined_grammemes(@locale, rest),
           {:ok, inflected} <-
             Inflector.inflect(@locale, rest, grammemes, constraint_values,
               disambiguation: disambiguation,
               priorities: @priorities,
               fallback: false
             ) do
        binary_part(word, 0, byte_size(prefix)) <> inflected
      else
        _other -> nil
      end
    end)
  end

  defp exemplar_guess(word, word_type, constraint_values, disambiguation, guess?) do
    length = String.length(word)

    if guess? and word_type == 0 and length > @min_stem_length do
      exemplars = Data.metadata!(@locale).suffix_exemplars

      Enum.find_value(
        min(@max_suffix_length, length - @min_stem_length)..1//-1,
        fn suffix_length ->
          suffix = String.slice(word, length - suffix_length, suffix_length)

          with [exemplar | _rest] <- Map.get(exemplars, suffix, []),
               grammemes when is_integer(grammemes) <-
                 Dictionary.combined_grammemes(@locale, exemplar),
               {:ok, inflected} <-
                 Inflector.inflect(@locale, exemplar, grammemes, constraint_values,
                   disambiguation: disambiguation,
                   priorities: @priorities,
                   fallback: false
                 ) do
            splice(word, exemplar, inflected)
          else
            _other -> nil
          end
        end
      )
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

  # ── Display function ─────────────────────────────────────────

  @impl true
  def display_value(display_data, constraints, guess?) do
    with %DisplayValue{} = display_value <- List.first(display_data),
         display_string when display_string != "" <- display_value.display_string do
      value_constraints = Map.merge(display_value.constraints, constraints)

      display_string =
        if map_size(constraints) > 0 do
          inflected =
            case Dictionary.combined_grammemes(@locale, display_string) do
              nil ->
                inflect_token_chain(display_string, constraints, guess?)

              word_grammemes ->
                inflect_known(display_string, word_grammemes, constraints, guess?)
            end

          inflected || display_string
        else
          display_string
        end

      display_string = prepend_preposition(display_string, constraints)
      %DisplayValue{display_string: display_string, constraints: value_constraints}
    else
      _other -> nil
    end
  end

  defp inflect_known(display_string, word_grammemes, constraints, guess?) do
    number = Map.get(constraints, "number", "")
    gender = Map.get(constraints, "gender", "")
    case_ = Map.get(constraints, "case", "")
    animacy = Map.get(constraints, "animacy", "")

    agreement = Dictionary.binary_properties(@locale, ["adjective", "pronoun"]) || 0

    # Non-virile plural agreement words share one form; gender is
    # dropped.
    {gender, animacy} =
      if number == "plural" and (word_grammemes &&& agreement) != 0 and
           animacy in ["animate", "inanimate"] and
           case_ in ["nominative", "accusative", "vocative"] do
        {"", "nonhuman"}
      else
        {gender, animacy}
      end

    constraint_values = Enum.reject([number, gender, case_, animacy], &(&1 == ""))
    disambiguation = for value <- [Map.get(constraints, "pos")], value not in [nil, ""], do: value
    inflect_word(display_string, word_grammemes, constraint_values, disambiguation, guess?)
  end

  defp inflect_token_chain(display_string, constraints, guess?) do
    tokens = Tokenizer.word_tokens(@locale, display_string)

    with head_token when not is_nil(head_token) <- List.last(tokens) do
      head = head_token.value
      head_grammemes = Dictionary.combined_grammemes(@locale, head) || 0

      constraint_values =
        for feature <- ["number", "gender", "case"],
            value = Map.get(constraints, feature),
            value not in [nil, ""],
            do: value

      disambiguation =
        for value <- [Map.get(constraints, "pos")], value not in [nil, ""], do: value

      inflected_head =
        inflect_word(head, head_grammemes, constraint_values, disambiguation, guess?)

      if inflected_head == nil and head_grammemes == 0 do
        nil
      else
        inflected_head = inflected_head || head
        agreement = agreement_constraints(head, constraints)

        inflect_modifiers(display_string, tokens, head_token, inflected_head, agreement, guess?)
      end
    end
  end

  defp agreement_constraints(head, constraints) do
    number =
      case Map.get(constraints, "number", "") do
        "" -> Lookup.determine(@locale, head, @numbers)
        value -> value
      end

    case_ =
      case Map.get(constraints, "case", "") do
        "" -> Lookup.determine(@locale, head, @cases)
        value -> value
      end

    gender =
      case Map.get(constraints, "gender", "") do
        "" when number == "singular" -> Lookup.determine(@locale, head, @genders)
        value -> value
      end

    animacy =
      case Map.get(constraints, "animacy", "") do
        "" when gender == "masculine" or number == "plural" ->
          Lookup.determine(@locale, head, @animacies)

        value ->
          value
      end

    # Plural agreement is virile vs non-virile.
    animacy =
      if number == "plural" do
        if animacy == "human", do: "human", else: "nonhuman"
      else
        animacy
      end

    %{number: number, gender: gender, case: case_, animacy: animacy}
  end

  defp inflect_modifiers(display_string, tokens, head_token, inflected_head, agreement, guess?) do
    constraint_values =
      Enum.reject(
        [agreement.number, agreement.gender, agreement.case, agreement.animacy],
        &(&1 == "")
      )

    without_animacy =
      Enum.reject([agreement.number, agreement.gender, agreement.case], &(&1 == ""))

    adposition = Dictionary.binary_properties(@locale, ["adposition"]) || 0
    pronoun = Dictionary.binary_properties(@locale, ["pronoun"]) || 0

    result =
      Enum.reduce_while(Enum.with_index(tokens), {"", 0, true}, fn {token, index},
                                                                   {output, position, before?} ->
        separator = binary_part(display_string, position, token.start - position)

        cond do
          token.start == head_token.start ->
            {:cont, {output <> separator <> inflected_head, token.stop, false}}

          not before? ->
            {:cont, {output <> separator <> token.value, token.stop, before?}}

          true ->
            word_grammemes = Dictionary.combined_grammemes(@locale, token.value) || 0

            inflected =
              if (word_grammemes &&& adposition) != 0 do
                next = Enum.at(tokens, index + 1)
                if next, do: preposition(token.clean, next.clean), else: token.value
              else
                inflect_modifier(
                  token.value,
                  word_grammemes,
                  constraint_values,
                  without_animacy,
                  agreement,
                  pronoun,
                  guess?
                )
              end

            case inflected do
              nil -> {:halt, :error}
              value -> {:cont, {output <> separator <> value, token.stop, before?}}
            end
        end
      end)

    case result do
      :error ->
        nil

      {output, position, _before?} ->
        output <> binary_part(display_string, position, byte_size(display_string) - position)
    end
  end

  defp inflect_modifier(
         word,
         word_grammemes,
         constraint_values,
         without_animacy,
         agreement,
         pronoun,
         guess?
       ) do
    inflect_word(word, word_grammemes, constraint_values, ["adjective"], guess?) ||
      if(agreement.animacy != "",
        do: inflect_word(word, word_grammemes, without_animacy, ["adjective"], guess?)
      ) ||
      if((word_grammemes &&& pronoun) != 0, do: word) ||
      known_uninflectable(word, word_grammemes) ||
      if(agreement.animacy == "human",
        do:
          inflect_word(
            word,
            word_grammemes,
            without_animacy ++ ["animate"],
            ["adjective"],
            guess?
          )
      )
  end

  defp known_uninflectable(word, word_grammemes) do
    if word_grammemes != 0 and Dictionary.patterns_for_word(@locale, word) == [] do
      word
    end
  end

  defp prepend_preposition(display_string, constraints) do
    case Map.get(constraints, "withPreposition") do
      value when value in [nil, ""] ->
        display_string

      preposition ->
        case Tokenizer.first_word(@locale, display_string) do
          nil ->
            display_string

          first ->
            if first.clean == preposition do
              display_string
            else
              preposition(preposition, first.clean) <> " " <> display_string
            end
        end
    end
  end
end
