defmodule Localize.Inflection.Synthesizer.Ml do
  @moduledoc false

  # The Malayalam grammar synthesizer, ported from
  # `MlGrammarSynthesizer`: dictionary lookups with suffix
  # heuristics for number/gender/case features, and a display
  # function that inflects the last significant token of a
  # Malayalam-script phrase, with noun/verb suffix fallback tables.

  @behaviour Localize.Inflection.Synthesizer

  alias Localize.Inflection.{Dictionary, DisplayValue, Inflector, Lookup, Tokenizer}

  @locale :ml

  @priorities [
    ["noun", "verb", "pronoun"],
    ["nominative", "accusative", "dative", "genitive", "locative", "instrumental", "sociative"],
    ["singular", "plural"],
    ["masculine", "feminine", "neuter"],
    ["formal", "informal"],
    ["inclusive", "exclusive"],
    ["first", "second", "third"],
    ["past", "present", "future"],
    ["indicative", "imperative", "subjunctive"]
  ]

  @plural_suffixes ["കൾ", "ങ്ങൾ", "മാർ", "വർ", "കളുടെ", "ങ്ങൾക്ക്"]

  @masculine_suffixes ["ൻ", "ർ"]
  @feminine_suffixes ["ി", "ാളി"]
  @neuter_suffixes ["ത്", "ം", "യം"]

  # First matching suffix (in this order) determines the case
  # feature of a display string.
  @suffix_to_case [
    {"ന്റെ", "genitive"},
    {"യുടെ", "genitive"},
    {"ഉടെ", "genitive"},
    {"ആയുടെ", "genitive"},
    {"ഉടേതു്", "genitive"},
    {"ഉടേതു", "genitive"},
    {"ഉടെത്", "genitive"},
    {"നെ", "accusative"},
    {"ക്ക്", "dative"},
    {"യ്ക്ക്", "dative"},
    {"യിൽ", "locative"},
    {"ഇൽ", "locative"},
    {"ആൽ", "instrumental"},
    {"വഴി", "instrumental"},
    {"ഓടെ", "sociative"}
  ]

  # {number, case} -> suffix. There are no accusative entries, so
  # the accusative fallback appends nothing.
  @noun_suffixes %{
    {"singular", "nominative"} => "",
    {"singular", "dative"} => "ക്ക്",
    {"singular", "genitive"} => "യുടെ",
    {"plural", "nominative"} => "കൾ",
    {"plural", "dative"} => "കൾക്ക്",
    {"plural", "genitive"} => "കളുടെ"
  }

  # {person, number, tense} -> suffix, all indicative mood. The
  # future suffix carries a leading space as upstream.
  @verb_suffixes %{
                   {"first", "singular", "past"} => "ച്ചു",
                   {"second", "singular", "past"} => "ച്ചു",
                   {"third", "singular", "past"} => "ച്ചു",
                   {"first", "plural", "past"} => "ഞ്ഞു",
                   {"second", "plural", "past"} => "ന്നു",
                   {"third", "plural", "past"} => "ന്നു"
                 }
                 |> Map.merge(
                   for person <- ["first", "second", "third"],
                       number <- ["singular", "plural"],
                       into: %{} do
                     {{person, number, "present"}, "ിക്കുന്നു"}
                   end
                 )
                 |> Map.merge(
                   for person <- ["first", "second", "third"],
                       number <- ["singular", "plural"],
                       into: %{} do
                     {{person, number, "future"}, " ചെയ്യും"}
                   end
                 )

  @persons ["first", "second", "third"]
  @numbers ["singular", "plural"]
  @tenses ["past", "present", "future"]
  @moods ["indicative", "imperative", "subjunctive"]
  @cases ["nominative", "accusative", "dative", "genitive", "instrumental", "locative"]

  @impl true
  def feature_value(feature, display_value, constraints)

  def feature_value("number", display_value, _constraints) do
    determine_number(display_value.display_string)
  end

  def feature_value("gender", display_value, _constraints) do
    determine_gender(display_value.display_string)
  end

  def feature_value("case", display_value, _constraints) do
    Enum.find_value(@suffix_to_case, fn {suffix, case_name} ->
      if String.ends_with?(display_value.display_string, suffix), do: case_name
    end)
  end

  def feature_value(_feature, _display_value, _constraints), do: nil

  @impl true
  def display_value(display_data, constraints, guess?) do
    with %DisplayValue{} = display_value <- List.first(display_data),
         display_string when display_string != "" <- display_value.display_string do
      if map_size(constraints) == 0 or
           not Regex.match?(~r/\p{Malayalam}/u, display_string) or
           Regex.match?(~r/[\p{Latin}\p{Nd}\p{P}]/u, display_string) do
        %DisplayValue{display_string: display_string, constraints: constraints}
      else
        constraint_values = build_constraint_values(constraints)
        inflected = inflect_phrase(display_string, constraint_values, guess?)

        # An unchanged result means no display value, even with
        # guessing enabled.
        if inflected != "" and inflected != display_string do
          %DisplayValue{display_string: inflected, constraints: constraints}
        else
          nil
        end
      end
    else
      _other -> nil
    end
  end

  defp build_constraint_values(constraints) do
    for feature <- ["case", "number", "gender", "pos"],
        value = Map.get(constraints, feature),
        value not in [nil, ""],
        do: value
  end

  # The last significant token is inflected; other tokens pass
  # through. Significant tokens are re-spaced with a single added
  # space on top of the original separators, as upstream.
  defp inflect_phrase(phrase, constraint_values, guess?) do
    case Tokenizer.word_tokens(@locale, phrase) do
      [] ->
        phrase

      tokens ->
        last_token = List.last(tokens)
        pos_value = Enum.find(constraint_values, "", &(&1 in ["noun", "pronoun", "verb"]))

        {result, position} =
          Enum.reduce(tokens, {"", 0}, fn token, {result, position} ->
            separator = binary_part(phrase, position, token.start - position)
            result = result <> separator
            result = if result != "", do: result <> " ", else: result

            value =
              if token == last_token do
                inflect_last_token(phrase, token.value, constraint_values, guess?, pos_value)
              else
                token.value
              end

            {result <> value, token.stop}
          end)

        result <> binary_part(phrase, position, byte_size(phrase) - position)
    end
  end

  defp inflect_last_token(phrase, value, constraint_values, guess?, pos_value) do
    grammemes = Dictionary.combined_grammemes(@locale, value) || 0

    inflected =
      case Inflector.inflect(@locale, value, grammemes, constraint_values,
             priorities: @priorities
           ) do
        {:ok, out} ->
          {:ok, out}

        :error when guess? and pos_value in ["noun", "pronoun"] ->
          guess_noun_inflection(phrase, constraint_values)

        :error when guess? and pos_value == "verb" ->
          {:ok, value <> verb_suffix(constraint_values)}

        :error ->
          :error
      end

    case inflected do
      {:ok, out} -> out
      :error -> value <> accusative_suffix(value, constraint_values)
    end
  end

  # The last-resort rule appends the accusative noun suffix — an
  # empty string today, as the suffix table has no accusative rows.
  defp accusative_suffix(value, constraint_values) do
    number = Enum.find(constraint_values, &(&1 in @numbers))
    case_value = Enum.find(constraint_values, &(&1 in @cases))

    if case_value == "accusative" and not String.ends_with?(value, "കൾ") do
      Map.get(@noun_suffixes, {number, "accusative"}, "")
    else
      ""
    end
  end

  defp verb_suffix(constraint_values) do
    slots =
      Enum.reduce(constraint_values, %{}, fn value, slots ->
        cond do
          value in @persons -> Map.put_new(slots, :person, value)
          value in @numbers -> Map.put_new(slots, :number, value)
          value in @tenses -> Map.put_new(slots, :tense, value)
          value in @moods -> Map.put_new(slots, :mood, value)
          true -> slots
        end
      end)

    # The packed verb key only matches when every slot is filled
    # and the mood is indicative.
    if Map.get(slots, :mood) == "indicative" do
      Map.get(@verb_suffixes, {slots[:person], slots[:number], slots[:tense]}, "")
    else
      ""
    end
  end

  # Re-inflects the whole phrase, inflecting the last significant
  # Malayalam-script token; token values concatenate verbatim.
  defp guess_noun_inflection(phrase, constraint_values) do
    case Tokenizer.word_tokens(@locale, phrase) do
      [] ->
        :error

      tokens ->
        target =
          tokens
          |> Enum.filter(&Regex.match?(~r/\p{Malayalam}/u, &1.value))
          |> List.last()

        if target == nil do
          {:ok, phrase}
        else
          grammemes = Dictionary.combined_grammemes(@locale, target.value) || 0

          {result, position} =
            Enum.reduce(tokens, {"", 0}, fn token, {result, position} ->
              separator = binary_part(phrase, position, token.start - position)

              value =
                if token == target do
                  case Inflector.inflect(@locale, token.value, grammemes, constraint_values,
                         priorities: @priorities
                       ) do
                    {:ok, out} -> out
                    :error -> token.value <> accusative_suffix(token.value, constraint_values)
                  end
                else
                  token.value
                end

              {result <> separator <> value, token.stop}
            end)

          {:ok, result <> binary_part(phrase, position, byte_size(phrase) - position)}
        end
    end
  end

  defp determine_number(""), do: nil

  defp determine_number(word) do
    tags = ["singular", "plural"]
    disambiguation = ["noun", "verb"]

    with "" <- Lookup.determine(@locale, word, tags, disambiguation: disambiguation),
         tokens = Tokenizer.word_tokens(@locale, word),
         "" <- determine_from_noun_tokens(tokens, tags, disambiguation) do
      last_value = (List.last(tokens) || %{value: ""}).value

      if String.ends_with?(last_value, @plural_suffixes) do
        "plural"
      else
        "singular"
      end
    else
      value -> value
    end
  end

  defp determine_gender(""), do: nil

  defp determine_gender(word) do
    tags = ["masculine", "feminine", "neuter"]
    disambiguation = ["noun", "pronoun"]

    with "" <- Lookup.determine(@locale, word, tags, disambiguation: disambiguation),
         tokens = Tokenizer.word_tokens(@locale, word),
         "" <- determine_from_noun_tokens(tokens, tags, disambiguation),
         "" <- determine_from_any_token(tokens, tags, disambiguation),
         "" <- guess_gender_by_suffix(tokens) do
      "masculine"
    else
      value -> value
    end
  end

  defp determine_from_noun_tokens(tokens, tags, disambiguation) do
    noun_mask = Dictionary.binary_properties(@locale, ["noun"])

    Enum.find_value(tokens, "", fn token ->
      if Dictionary.has_all_properties?(@locale, token.clean, noun_mask) do
        case Lookup.determine(@locale, token.value, tags, disambiguation: disambiguation) do
          "" -> nil
          value -> value
        end
      end
    end)
  end

  defp determine_from_any_token(tokens, tags, disambiguation) do
    Enum.find_value(tokens, "", fn token ->
      case Lookup.determine(@locale, token.value, tags, disambiguation: disambiguation) do
        "" -> nil
        value -> value
      end
    end)
  end

  defp guess_gender_by_suffix(tokens) do
    case List.first(tokens) do
      nil ->
        ""

      token ->
        cond do
          String.ends_with?(token.clean, @masculine_suffixes) -> "masculine"
          String.ends_with?(token.clean, @feminine_suffixes) -> "feminine"
          String.ends_with?(token.clean, @neuter_suffixes) -> "neuter"
          true -> ""
        end
    end
  end
end
