defmodule Localize.Inflection.Synthesizer.En do
  @moduledoc false

  # The English grammar synthesizer, ported from
  # `EnGrammarSynthesizer` and its lookup and display functions.

  @behaviour Localize.Inflection.Synthesizer

  alias Localize.Inflection.{
    Articles,
    Data,
    Dictionary,
    DisplayValue,
    Inflector,
    Lookup,
    PhraseProperties,
    SpeakableString,
    Tokenizer
  }

  import Bitwise

  @locale :en
  @speak "speak"

  @number_tags ["singular", "plural"]
  @count_disambiguation ["noun", "verb"]
  @priorities [
    ["noun", "adjective", "verb"],
    ["third", "first", "second"],
    ["singular", "plural"]
  ]

  @possessive_determiners %{
    "he" => "his",
    "him" => "his",
    "i" => "my",
    "it" => "its",
    "me" => "my",
    "she" => "her",
    "them" => "their",
    "they" => "their",
    "us" => "our",
    "we" => "our",
    "you" => "your"
  }

  @impl true
  def feature_value(feature, display_value, constraints)

  def feature_value("number", display_value, _constraints) do
    empty_to_nil(determine_count(display_value.display_string))
  end

  def feature_value("case", display_value, _constraints) do
    display_string = String.downcase(display_value.display_string)

    if String.length(display_string) >= 3 do
      normalized = String.replace(display_string, ~r/[’ʼ]/u, "'")

      genitive? =
        (String.ends_with?(normalized, "'s") or String.ends_with?(normalized, "s'") or
           normalized == "its") and not MapSet.member?(contractions(), normalized)

      if genitive?, do: "genitive"
    end
  end

  def feature_value("definiteness", display_value, _constraints) do
    Articles.detect_definiteness(
      @locale,
      display_value,
      Articles.article_prefixes(@locale, ["defArticle"]),
      Articles.article_prefixes(@locale, ["indefArticle"])
    )
  end

  def feature_value(feature, display_value, _constraints)
      when feature in ["defArticle", "indefArticle"] do
    indefinite_article(display_value, false)
  end

  def feature_value(_feature, _display_value, _constraints), do: nil

  # The a/an lookup, shared by the feature function (article only)
  # and the display function (article prepended).
  defp indefinite_article(display_value, include?) do
    display_string = display_value.display_string

    if display_string == "" do
      Articles.create_preposition(display_value, "", include?)
    else
      count = determine_count(display_string)

      if count == "plural" do
        Articles.create_preposition(display_value, "", include?)
      else
        stripped = strip_possessive(display_string)

        article =
          if PhraseProperties.starts_with_vowel?(@locale, stripped) or
               starts_with_vowel_digits?(stripped) do
            "an"
          else
            "a"
          end

        Articles.create_preposition(display_value, article, include?)
      end
    end
  end

  defp strip_possessive(display_string) do
    if String.length(display_string) > 3 and
         (String.ends_with?(display_string, "’s") or String.ends_with?(display_string, "'s")) do
      String.slice(display_string, 0..-3//1)
    else
      display_string
    end
  end

  # Numbers pronounced with a leading vowel: 8, 11, 18 and their
  # thousand-groups (800, 11000, …), mirroring upstream.
  defp starts_with_vowel_digits?(display_string) do
    case Integer.parse(String.replace(display_string, ",", "")) do
      {number, _rest} when number >= 0 ->
        first_digit = display_string |> String.first() |> String.to_integer()

        cond do
          first_digit == 8 -> true
          first_digit == 1 -> reduce_number(number) in [11, 18]
          true -> false
        end

      _other ->
        false
    end
  rescue
    ArgumentError -> false
  end

  defp reduce_number(number) when number >= 1000, do: reduce_number(div(number, 1000))
  defp reduce_number(number) when number >= 100, do: div(number, 100)
  defp reduce_number(number), do: number

  # Port of EnGrammarSynthesizer_CountLookupFunction.determine/1.
  defp determine_count(phrase) do
    result =
      Lookup.determine(@locale, phrase, @number_tags, disambiguation: @count_disambiguation)

    if result != "" or phrase == "" do
      result
    else
      tokens = Tokenizer.word_tokens(@locale, phrase)
      count_before_preposition(tokens) || count_of_last_word(tokens)
    end
  end

  # Handles "to the red light on the front porch" where "light" is
  # the noun to check.
  defp count_before_preposition(tokens) do
    preposition = Dictionary.binary_properties(@locale, ["adposition"]) || 0

    tokens
    |> Enum.reduce_while(nil, fn token, last_word ->
      if last_word != nil and Dictionary.has_all_properties?(@locale, token.clean, preposition) do
        {:halt, determine_word_count(last_word.value)}
      else
        {:cont, token}
      end
    end)
    |> case do
      result when is_binary(result) and result != "" -> result
      _other -> nil
    end
  end

  defp count_of_last_word(tokens) do
    case List.last(tokens) do
      nil -> ""
      last -> determine_word_count(last.value)
    end
  end

  defp determine_word_count(word) do
    Lookup.determine(@locale, word, @number_tags, disambiguation: @count_disambiguation)
  end

  @impl true
  def display_value(display_data, constraints, guess?) do
    with %DisplayValue{} = display_value <- List.first(display_data),
         display_string when display_string != "" <- display_value.display_string do
      count = Map.get(constraints, "number")
      requesting_plural? = count == "plural"

      inflected =
        if count in ["singular", "plural"] do
          inflect_phrase(display_string, constraints, guess?)
        else
          {:ok, :uninflected}
        end

      case inflected do
        :error ->
          nil

        {:ok, result} ->
          {display_string, value_constraints} =
            case result do
              :uninflected ->
                # Preserve the speak value only when not morphologically changing.
                case Map.get(display_value.constraints, @speak) do
                  nil -> {display_string, constraints}
                  speak -> {display_string, Map.put(constraints, @speak, speak)}
                end

              inflected_string ->
                {inflected_string, constraints}
            end

          {display_string, value_constraints} =
            if Map.get(constraints, "case") == "genitive" do
              inflect_possessive(display_string, value_constraints, requesting_plural?)
            else
              {display_string, value_constraints}
            end

          add_definiteness(
            %DisplayValue{display_string: display_string, constraints: value_constraints},
            constraints
          )
      end
    else
      _other -> nil
    end
  end

  defp add_definiteness(display_value, constraints) do
    Articles.add_definiteness(
      display_value,
      constraints,
      Articles.article_prefixes(@locale, ["defArticle"]),
      Articles.article_prefixes(@locale, ["indefArticle"]),
      fn base, _constraints -> static_definite_article(base) end,
      fn base, _constraints -> indefinite_article(base, true) end
    )
  end

  # Port of StaticArticleLookupFunction with the article "the".
  defp static_definite_article(display_value) do
    case Map.get(display_value.constraints, "defArticle") do
      nil ->
        display_string = display_value.display_string

        if display_string != "" and
             not String.starts_with?(String.downcase(display_string), "the ") do
          Articles.create_preposition(display_value, "the", true)
        else
          Articles.create_preposition(display_value, "", true)
        end

      article ->
        Articles.create_preposition(display_value, article, true)
    end
  end

  # Port of EnGrammarSynthesizer_EnDisplayFunction.inflectPhrase/3.
  # Returns {:ok, string} or :error.
  defp inflect_phrase(phrase, constraints, guess?) do
    constraint_values =
      for value <- [Map.get(constraints, "number")], value not in [nil, ""], do: value

    disambiguation = for value <- [Map.get(constraints, "pos")], value not in [nil, ""], do: value
    options = [disambiguation: disambiguation, priorities: @priorities]

    case Dictionary.combined_grammemes(@locale, phrase) do
      properties when is_integer(properties) ->
        case Inflector.inflect(@locale, phrase, properties, constraint_values, options) do
          {:ok, inflected} -> {:ok, inflected}
          :error when guess? -> {:ok, phrase}
          :error -> :error
        end

      nil ->
        inflect_significant_token(phrase, constraint_values, options, guess?)
    end
  end

  defp inflect_significant_token(phrase, constraint_values, options, guess?) do
    case find_significant_token(phrase) do
      {token, properties} when properties != 0 or guess? ->
        with {:ok, inflected_word} <-
               inflect_token(token, properties, constraint_values, options, guess?) do
          {prefix, suffix} = split_around(phrase, token)
          {:ok, prefix <> inflected_word <> suffix}
        end

      _nil_or_unknown ->
        if guess?, do: {:ok, phrase}, else: :error
    end
  end

  # The last word before the first preposition, or the last word.
  defp find_significant_token(phrase) do
    preposition = Dictionary.binary_properties(@locale, ["adposition"]) || 0

    @locale
    |> Tokenizer.word_tokens(phrase)
    |> Enum.reduce_while(nil, fn token, best ->
      properties = Dictionary.combined_grammemes(@locale, token.value) || 0

      if best != nil and (properties &&& preposition) == preposition and preposition != 0 do
        {:halt, best}
      else
        {:cont, {token, properties}}
      end
    end)
  end

  defp inflect_token(token, properties, constraint_values, options, guess?) do
    case Inflector.inflect(@locale, token.value, properties, constraint_values, options) do
      {:ok, inflected} ->
        {:ok, inflected}

      :error when guess? ->
        if "plural" in constraint_values do
          {:ok, guess_plural(token.value)}
        else
          {:ok, guess_singular(token.value)}
        end

      :error ->
        :error
    end
  end

  defp split_around(phrase, token) do
    prefix = binary_part(phrase, 0, token.start)
    suffix = binary_part(phrase, token.stop, byte_size(phrase) - token.stop)
    {prefix, suffix}
  end

  @vowels ~w(a e i o u A E I O U)

  defp guess_plural(word) do
    cond do
      String.ends_with?(word, ["s", "ch", "sh", "x", "z"]) ->
        word <> "es"

      String.length(word) > 2 and String.ends_with?(word, "y") and
          String.slice(word, -2..-2//1) not in @vowels ->
        String.slice(word, 0..-2//1) <> "ies"

      true ->
        word <> "s"
    end
  end

  defp guess_singular(word) do
    cond do
      String.ends_with?(word, ["ses", "ches", "shes", "xes", "zes"]) ->
        String.slice(word, 0..-3//1)

      String.ends_with?(word, "ies") ->
        String.slice(word, 0..-4//1) <> "y"

      String.ends_with?(word, "s") ->
        String.slice(word, 0..-2//1)

      true ->
        word
    end
  end

  # Port of EnGrammarSynthesizer_EnDisplayFunction.inflectPossessive/3.
  defp inflect_possessive(display_string, value_constraints, requesting_plural?) do
    case Map.get(@possessive_determiners, String.downcase(display_string)) do
      determiner when is_binary(determiner) ->
        {determiner, value_constraints}

      nil when display_string == "" ->
        {display_string, value_constraints}

      nil ->
        suffix = possessive_suffix(display_string, requesting_plural?)

        value_constraints =
          case Map.get(value_constraints, @speak) do
            nil -> value_constraints
            speak -> Map.put(value_constraints, @speak, speak <> suffix)
          end

        {display_string <> suffix, value_constraints}
    end
  end

  defp possessive_suffix(display_string, requesting_plural?) do
    if String.length(display_string) > 2 do
      last_two = String.slice(display_string, -2..-1//1)

      cond do
        String.contains?(last_two, ["'", "’", "ʼ"]) and
            String.contains?(String.downcase(last_two), "s") ->
          ""

        String.ends_with?(last_two, "s") ->
          if requesting_plural? or plural_noun?(display_string) do
            "’"
          else
            "’s"
          end

        true ->
          "’s"
      end
    else
      "’s"
    end
  end

  # True when the last word reads as a plural common noun (cats’,
  # Niagara Falls’) as opposed to a name or singular that merely
  # ends in s (Jones’s). Proper nouns keep ’s even when a plural
  # reading exists.
  defp plural_noun?(display_string) do
    with last_word when not is_nil(last_word) <- Tokenizer.last_word(@locale, display_string),
         noun when is_integer(noun) <- Dictionary.binary_properties(@locale, ["noun"]),
         plural when is_integer(plural) <- Dictionary.binary_properties(@locale, ["plural"]),
         singular when is_integer(singular) <- Dictionary.binary_properties(@locale, ["singular"]),
         proper when is_integer(proper) <- Dictionary.binary_properties(@locale, ["proper-noun"]) do
      combined = Dictionary.combined_grammemes(@locale, last_word.value) || 0

      plural_reading? =
        @locale
        |> Dictionary.grammeme_sets(last_word.value)
        |> Enum.any?(fn reading ->
          (reading &&& noun) == noun and (reading &&& plural) == plural and
            (reading &&& singular) == 0
        end)

      plural_reading? and (combined &&& proper) == 0
    else
      _other -> false
    end
  end

  defp contractions do
    Data.metadata!(@locale).contractions
    |> Enum.filter(&String.ends_with?(String.downcase(&1), "'s"))
    |> Enum.map(&String.downcase/1)
    |> MapSet.new()
  end

  defp empty_to_nil(""), do: nil
  defp empty_to_nil(value), do: value

  @doc false
  def speakable(value), do: SpeakableString.print(value)
end
