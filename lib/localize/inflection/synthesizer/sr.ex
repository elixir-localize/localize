defmodule Localize.Inflection.Synthesizer.Sr do
  @moduledoc false

  # The Serbian grammar synthesizer, ported from
  # `SrGrammarSynthesizer`. Dictionary inflection for known words
  # (nominative is requested by omitting the case constraint), and
  # a rule-based guess for unknown -а declension nouns (Cyrillic).

  @behaviour Localize.Inflection.Synthesizer

  alias Localize.Inflection.{Dictionary, DisplayValue, Inflector, Lookup}

  @locale :sr

  @genders ["masculine", "feminine", "neuter"]
  @numbers ["singular", "plural"]
  @animacies ["animate", "inanimate"]

  @priorities [["noun", "adjective"], ["singular", "plural"], @genders]

  @case_index %{
    "nominative" => 0,
    "genitive" => 1,
    "dative" => 2,
    "accusative" => 3,
    "vocative" => 4,
    "instrumental" => 5,
    "locative" => 6
  }

  @suffix_singular ~w(а е и у а ом и)
  @suffix_plural ~w(е а ама е е ама ама)

  @cyrillic_vowels ~w(а е и о у)

  @lookups %{
    "gender" => @genders,
    "number" => @numbers,
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

  @impl true
  def display_value(display_data, constraints, guess?) do
    with %DisplayValue{} = display_value <- List.first(display_data),
         display_string when display_string != "" <- display_value.display_string do
      display_string =
        cond do
          Dictionary.combined_grammemes(@locale, display_string) != nil ->
            inflect_from_dictionary(constraints, display_string)

          guess? ->
            inflect_with_rule(constraints, display_string)

          true ->
            display_string
        end

      %DisplayValue{display_string: display_string, constraints: constraints}
    else
      _other -> nil
    end
  end

  defp inflect_from_dictionary(constraints, lemma) do
    count = Map.get(constraints, "number", "")
    case_ = Map.get(constraints, "case", "")
    gender = Map.get(constraints, "gender", "")

    # Nominative is unmarked in the patterns; it is requested by
    # omitting the case constraint.
    constraint_values =
      if(count != "", do: [count], else: []) ++
        if(case_ != "" and case_ != "nominative", do: [case_], else: []) ++
        if(gender != "", do: [gender], else: [])

    word_grammemes = Dictionary.combined_grammemes(@locale, lemma) || 0

    case Inflector.inflect(@locale, lemma, word_grammemes, constraint_values,
           priorities: @priorities
         ) do
      {:ok, inflected} -> inflected
      :error -> lemma
    end
  end

  defp inflect_with_rule(constraints, lemma) do
    case_ = Map.get(constraints, "case", "")
    count = Map.get(constraints, "number", "") |> then(&if(&1 == "", do: "singular", else: &1))

    cond do
      case_ == "" ->
        lemma

      count == "singular" and case_ == "nominative" ->
        lemma

      String.ends_with?(lemma, "а") ->
        rule_a(lemma, count, case_)

      true ->
        # The о/е, neuter-е and consonant declension rules are
        # unimplemented upstream (TODO stubs returning the lemma).
        lemma
    end
  end

  defp rule_a(lemma, count, case_) do
    case Map.get(@case_index, case_) do
      nil ->
        lemma

      index ->
        base = String.slice(lemma, 0..-2//1)
        suffixes = if count == "singular", do: @suffix_singular, else: @suffix_plural
        inflected = base <> Enum.at(suffixes, index)

        inflected
        |> vocative_special(lemma, count, case_)
        |> genitive_plural_special(lemma, count, case_)
    end
  end

  defp vocative_special(inflected, lemma, "singular", "vocative") do
    syllables = count_syllables(lemma)

    cond do
      String.ends_with?(lemma, "ица") and syllables > 2 ->
        String.slice(inflected, 0..-2//1) <> "е"

      proper_noun?(lemma) and syllables == 2 ->
        String.slice(inflected, 0..-2//1) <> "о"

      true ->
        inflected
    end
  end

  defp vocative_special(inflected, _lemma, _count, _case), do: inflected

  defp genitive_plural_special(inflected, lemma, "plural", "genitive") do
    inflected =
      if String.ends_with?(lemma, ["тња", "дња", "пта", "лба", "рва"]) do
        String.slice(inflected, 0..-2//1) <> "и"
      else
        inflected
      end

    Enum.reduce(
      [{"јка", "јака"}, {"мља", "маља"}, {"вца", "ваца"}, {"тка", "така"}, {"пка", "пака"}],
      inflected,
      fn {suffix, replacement}, acc ->
        if String.ends_with?(acc, suffix) do
          String.slice(acc, 0, String.length(acc) - String.length(suffix)) <> replacement
        else
          acc
        end
      end
    )
  end

  defp genitive_plural_special(inflected, _lemma, _count, _case), do: inflected

  defp count_syllables(lemma) do
    graphemes = String.graphemes(lemma)
    length = length(graphemes)

    vowels = Enum.count(graphemes, &(&1 in @cyrillic_vowels))

    syllabic_r =
      graphemes
      |> Enum.with_index()
      |> Enum.count(fn {char, index} ->
        char in ["р", "Р"] and
          ((index == 0 and index + 1 < length and consonant?(Enum.at(graphemes, 1))) or
             (index != 0 and index + 1 < length and consonant?(Enum.at(graphemes, index - 1)) and
                consonant?(Enum.at(graphemes, index + 1))))
      end)

    vowels + syllabic_r
  end

  defp consonant?(char) when is_binary(char) do
    String.match?(char, ~r/\p{Cyrillic}/u) and char not in @cyrillic_vowels
  end

  defp consonant?(_char), do: false

  # Cyrillic capitals Ђ..Ш signal a proper noun.
  defp proper_noun?(lemma) do
    case String.next_codepoint(lemma) do
      {<<c::utf8>>, _rest} -> c >= 0x0402 and c <= 0x0428
      _other -> false
    end
  end
end
