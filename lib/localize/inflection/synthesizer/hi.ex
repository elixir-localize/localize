defmodule Localize.Inflection.Synthesizer.Hi do
  @moduledoc false

  # The per-language synthesizers and conformance harnesses are ported
  # from the upstream C++ linguistic rule tables; their branchiness and
  # nesting mirror the reference implementation they are verified
  # against (see guides/inflection.md).
  # credo:disable-for-this-file Credo.Check.Refactor.CyclomaticComplexity
  # credo:disable-for-this-file Credo.Check.Refactor.Nesting

  # The Hindi grammar synthesizer, ported from
  # `HiGrammarSynthesizer`: number/gender dictionary lookups and a
  # phrase display function that forces words before an adposition
  # into the oblique case (दरवाज़ा में -> दरवाजे में) and reverts
  # plural-feminine words to singular before a plural verb.

  @behaviour Localize.Inflection.Synthesizer

  alias Localize.Inflection.{Dictionary, DisplayValue, GrammemeLookup, Inflector, Tokenizer}

  import Bitwise

  @locale :hi

  @genders ["masculine", "feminine"]
  @priorities [
    ["noun", "adposition", "adjective", "verb"],
    ["participle"],
    ["third", "second", "first"],
    ["direct", "oblique"],
    ["singular", "plural"],
    @genders
  ]

  # Postpositions never inflect except the genitive का/के/की, which
  # agrees with the possessed noun.
  @inflectable_adpositions ["का", "के", "की"]

  @masculine_suffixes ["ा", "े"]
  @feminine_suffixes ["ी", "े"]

  @impl true
  def feature_value(feature, display_value, constraints)

  def feature_value("number", display_value, _constraints) do
    case GrammemeLookup.determine(@locale, display_value.display_string, ["singular", "plural"],
           disambiguation: ["noun", "verb"]
         ) do
      "" -> nil
      value -> value
    end
  end

  def feature_value("gender", display_value, _constraints) do
    case GrammemeLookup.determine(@locale, display_value.display_string, @genders,
           disambiguation: ["noun", "adposition", "adjective", "verb"],
           default: "masculine",
           first_word_determines?: true,
           suffix_function: &guess_gender_by_suffix/1
         ) do
      "" -> nil
      value -> value
    end
  end

  def feature_value(_feature, _display_value, _constraints), do: nil

  # The masculine list is scanned first, so a े-final word is
  # always reported masculine even though े is in both lists.
  defp guess_gender_by_suffix(word) do
    cond do
      String.ends_with?(word, @masculine_suffixes) -> "masculine"
      String.ends_with?(word, @feminine_suffixes) -> "feminine"
      true -> ""
    end
  end

  @impl true
  def display_value(display_data, constraints, guess?) do
    with %DisplayValue{} = display_value <- List.first(display_data),
         display_string when display_string != "" <- display_value.display_string do
      value_constraints = Map.merge(display_value.constraints, constraints)

      result =
        if map_size(constraints) == 0 do
          {:ok, display_string}
        else
          inflect_string(display_string, constraints, guess?)
        end

      case result do
        {:ok, inflected} ->
          %DisplayValue{display_string: inflected, constraints: value_constraints}

        :error ->
          if guess? do
            %DisplayValue{display_string: display_string, constraints: value_constraints}
          else
            nil
          end
      end
    else
      _other -> nil
    end
  end

  defp inflect_string(display_string, constraints, guess?) do
    case Dictionary.combined_grammemes(@locale, display_string) do
      nil ->
        inflect_phrase(display_string, constraints, guess?)

      grammemes ->
        inflect_word(display_string, grammemes, constraints, guess?, false)
    end
  end

  defp inflect_phrase(display_string, constraints, guess?) do
    tokens = Tokenizer.word_tokens(@locale, display_string)

    case inflect_significant_words(Enum.map(tokens, & &1.value), constraints, guess?) do
      {:ok, inflected_words} ->
        {:ok, reassemble(display_string, tokens, inflected_words)}

      :error ->
        :error
    end
  end

  defp inflect_significant_words([], _constraints, _guess?), do: {:ok, []}

  defp inflect_significant_words(words, constraints, guess?) do
    adposition_mask = Dictionary.binary_properties(@locale, ["adposition"])
    adposition_index = Enum.find_index(words, &has_all?(&1, adposition_mask))

    inflected =
      words
      |> Enum.with_index()
      |> Enum.reduce_while([], fn {word, index}, acc ->
        processing_adposition? = index == adposition_index
        make_oblique? = adposition_index != nil and index < adposition_index

        if processing_adposition? and word not in @inflectable_adpositions do
          {:cont, [word | acc]}
        else
          grammemes = Dictionary.combined_grammemes(@locale, word) || 0

          case inflect_word(word, grammemes, constraints, guess?, make_oblique?) do
            {:ok, value} -> {:cont, [value | acc]}
            :error when guess? -> {:cont, [word | acc]}
            :error -> {:halt, :error}
          end
        end
      end)

    case inflected do
      :error -> :error
      list when length(words) == 1 -> {:ok, Enum.reverse(list)}
      list -> plural_verb_agreement(Enum.reverse(list), guess?)
    end
  end

  # The plural of चाहती is चाहतीं, but before the plural verb हैं it
  # reverts to the singular form: चाहती हैं.
  defp plural_verb_agreement(inflected, guess?) do
    plural_verb_mask = Dictionary.binary_properties(@locale, ["plural", "verb"])

    if has_all?(List.last(inflected), plural_verb_mask) do
      plural_feminine_mask = Dictionary.binary_properties(@locale, ["plural", "feminine"])
      {leading, [last]} = Enum.split(inflected, -1)

      leading
      |> Enum.reduce_while([], fn word, acc ->
        grammemes = Dictionary.combined_grammemes(@locale, word) || 0

        if (grammemes &&& plural_feminine_mask) != plural_feminine_mask do
          {:cont, [word | acc]}
        else
          case Inflector.inflect(@locale, word, grammemes, ["singular"], priorities: @priorities) do
            {:ok, singular} -> {:cont, [singular | acc]}
            :error when guess? -> {:cont, [guess_singular(word) | acc]}
            :error -> {:halt, :error}
          end
        end
      end)
      |> case do
        :error -> :error
        reversed -> {:ok, Enum.reverse(reversed) ++ [last]}
      end
    else
      {:ok, inflected}
    end
  end

  defp has_all?(word, mask) do
    grammemes = Dictionary.combined_grammemes(@locale, word) || 0
    (grammemes &&& mask) == mask
  end

  # When a word goes oblique because it precedes an adposition, the
  # gender constraint is intentionally not applied, and "oblique" is
  # injected only when the caller supplied no explicit case.
  defp inflect_word(word, grammemes, constraints, guess?, make_oblique?) do
    gender_mask = Dictionary.binary_properties(@locale, @genders)
    number = Map.get(constraints, "number")
    gender = Map.get(constraints, "gender")
    case_constraint = Map.get(constraints, "case")

    constraint_values =
      Enum.reject(
        [
          number,
          if((grammemes &&& gender_mask) != 0 and not make_oblique?, do: gender),
          case_constraint,
          if(case_constraint in [nil, ""] and make_oblique?, do: "oblique")
        ],
        &(&1 in [nil, ""])
      )

    disambiguation = for value <- [Map.get(constraints, "pos")], value not in [nil, ""], do: value

    case Inflector.inflect(@locale, word, grammemes, constraint_values,
           disambiguation: disambiguation,
           priorities: @priorities
         ) do
      {:ok, inflected} ->
        {:ok, inflected}

      :error when guess? ->
        {:ok, guess_inflection(word, gender, number)}

      :error ->
        :error
    end
  end

  defp guess_inflection(word, gender, number) do
    word =
      case gender do
        "feminine" -> guess_feminine(word)
        "masculine" -> guess_masculine(word)
        _other -> word
      end

    case number do
      "plural" -> guess_plural(word)
      "singular" -> guess_singular(word)
      _other -> word
    end
  end

  defp guess_singular(word) do
    cond do
      # बटुए -> बटुआ
      String.ends_with?(word, "ए") -> drop_last(word) <> "आ"
      # लड़के -> लड़का
      String.ends_with?(word, "े") -> drop_last(word) <> "ा"
      # Removes only the anusvara: किताबें -> किताबे (as upstream).
      String.ends_with?(word, "ें") -> drop_last(word)
      true -> word
    end
  end

  defp guess_plural(word) do
    cond do
      # लड़की -> लड़कियाँ, नीति -> नीतियाँ
      String.ends_with?(word, "ी") or String.ends_with?(word, "ि") ->
        drop_last(word) <> "ियाँ"

      # वस्तु -> वस्तुएँ
      String.ends_with?(word, "ू") or String.ends_with?(word, "ु") ->
        drop_last(word) <> "ुएँ"

      # चिड़िया -> चिड़ियाँ (must precede the ा rule)
      String.ends_with?(word, "या") ->
        drop_last(word) <> "ाँ"

      # बटुआ -> बटुए
      String.ends_with?(word, "आ") ->
        drop_last(word) <> "ए"

      # लड़का -> लड़के
      String.ends_with?(word, "ा") ->
        drop_last(word) <> "े"

      true ->
        word
    end
  end

  # लड़की -> लड़का
  defp guess_masculine(word) do
    if String.ends_with?(word, "ी"), do: drop_last(word) <> "ा", else: word
  end

  # लड़का -> लड़की
  defp guess_feminine(word) do
    if String.ends_with?(word, "ा"), do: drop_last(word) <> "ी", else: word
  end

  # Drops the final codepoint (all relevant Devanagari characters
  # are single UTF-16 code units upstream).
  defp drop_last(word) do
    {_last, rest} = word |> String.to_charlist() |> List.pop_at(-1)
    List.to_string(rest)
  end

  defp reassemble(display_string, tokens, inflected_words) do
    {output, position} =
      tokens
      |> Enum.zip(inflected_words)
      |> Enum.reduce({"", 0}, fn {token, inflected}, {output, position} ->
        separator = binary_part(display_string, position, token.start - position)
        {output <> separator <> inflected, token.stop}
      end)

    output <> binary_part(display_string, position, byte_size(display_string) - position)
  end
end
