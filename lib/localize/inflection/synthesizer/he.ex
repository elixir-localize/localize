defmodule Localize.Inflection.Synthesizer.He do
  @moduledoc false

  # The per-language synthesizers and conformance harnesses are ported
  # from the upstream C++ linguistic rule tables; their branchiness and
  # nesting mirror the reference implementation they are verified
  # against (see guides/inflection.md).
  # credo:disable-for-this-file Credo.Check.Refactor.CyclomaticComplexity
  # credo:disable-for-this-file Credo.Check.Refactor.Nesting

  # The Hebrew grammar synthesizer, ported from
  # `HeGrammarSynthesizer`. Definiteness is the prefix ה applied by
  # the display function (position depends on phrase shape);
  # pluralization has dictionary, construct-state and heuristic
  # paths including final→medial letter substitution.

  @behaviour Localize.Inflection.Synthesizer

  alias Localize.Inflection.{
    Dictionary,
    DisplayValue,
    GrammemeLookup,
    Inflector,
    Lookup,
    Tokenizer
  }

  import Bitwise

  @locale :he

  @priorities [["noun", "adjective", "verb"], ["singular", "plural"], ["masculine", "feminine"]]

  @final_to_medial %{"ך" => "כ", "ם" => "מ", "ן" => "נ", "ף" => "פ", "ץ" => "צ"}

  @irregular_plurals %{
    "איש" => "אנשים",
    "צל" => "צללים",
    "אישה" => "נשים",
    "שנה" => "שנים",
    "מילה" => "מילים",
    "בת" => "בנות"
  }

  @ot_plurals ~w(חשבון חלון ראיון ארון רעיון חילזון הגיון פתרון מקום אולם אב ארמון דו״ח חשד כוח סוד וילון לקוח רוח קול מטבע עקרון קיר שטר רחוב רגש ספק קרון)

  @inseparable_prefixes ~w(ב ל מ כ)

  @impl true
  def feature_value(feature, display_value, constraints)

  def feature_value("gender", display_value, _constraints) do
    empty_to_nil(
      GrammemeLookup.determine(@locale, display_value.display_string, ["feminine", "masculine"],
        disambiguation: ["noun", "adjective", "determiner", "verb"],
        default: "masculine",
        first_word_determines?: true,
        suffix_function: fn word ->
          if String.ends_with?(word, ["ת", "ה"]), do: "feminine", else: ""
        end
      )
    )
  end

  def feature_value("number", display_value, _constraints) do
    empty_to_nil(
      Lookup.determine(@locale, display_value.display_string, ["singular", "plural", "dual"])
    )
  end

  def feature_value("definiteness", display_value, _constraints) do
    determine_definiteness(display_value.display_string)
  end

  def feature_value("withConditionalHyphen", display_value, _constraints) do
    conditional_hyphen(display_value.display_string)
  end

  def feature_value(_feature, _display_value, _constraints), do: nil

  defp determine_definiteness(word) do
    case Lookup.determine(@locale, word, ["definite", "indefinite", "construct"]) do
      "" ->
        noun = Dictionary.binary_properties(@locale, ["noun", "proper-noun"]) || 0

        case Dictionary.combined_grammemes(@locale, word) do
          nil ->
            if String.starts_with?(word, ["ת", "ה"]), do: "definite"

          properties ->
            if (properties &&& noun) != 0, do: "indefinite"
        end

      value ->
        value
    end
  end

  # A hyphen joins a Hebrew suffix to a foreign word or number.
  defp conditional_hyphen(display_string) do
    case first_alphanumeric(display_string) do
      nil -> "-" <> display_string
      codepoint -> if hebrew?(codepoint), do: display_string, else: "-" <> display_string
    end
  end

  defp first_alphanumeric(<<codepoint::utf8, rest::binary>>) do
    if <<codepoint::utf8>> =~ ~r/[[:alpha:][:digit:]]/u do
      codepoint
    else
      first_alphanumeric(rest)
    end
  end

  defp first_alphanumeric(<<_byte, rest::binary>>), do: first_alphanumeric(rest)
  defp first_alphanumeric(<<>>), do: nil

  defp hebrew?(codepoint) do
    <<codepoint::utf8>> =~ ~r/\p{Hebrew}/u
  end

  # ── Display function ─────────────────────────────────────────

  @impl true
  def display_value(display_data, constraints, _guess?) do
    with %DisplayValue{} = display_value <- List.first(display_data),
         display_string when display_string != "" <- display_value.display_string do
      count = Map.get(constraints, "number", "")
      person = Map.get(constraints, "person", "")
      gender = Map.get(constraints, "gender", "")

      disambiguation =
        for feature <- ["person", "pos"],
            value = Map.get(constraints, feature),
            value not in [nil, ""],
            do: value

      display_string =
        if count != "" or gender != "" do
          inflect_display_string(display_string, count, gender, person, disambiguation)
        else
          display_string
        end

      display_string =
        case Map.get(constraints, "definiteness", "") do
          "" -> display_string
          definiteness -> apply_definiteness(display_string, definiteness)
        end

      %DisplayValue{display_string: display_string, constraints: constraints}
    else
      _other -> nil
    end
  end

  defp inflect_display_string(display_string, count, gender, person, disambiguation) do
    constraint_values = Enum.reject([count, gender, person], &(&1 == ""))

    whole =
      case Dictionary.combined_grammemes(@locale, display_string) do
        nil ->
          :error

        word_grammemes ->
          Inflector.inflect(@locale, display_string, word_grammemes, constraint_values,
            disambiguation: disambiguation,
            priorities: @priorities
          )
      end

    case whole do
      {:ok, inflected} ->
        inflected

      :error ->
        if gender == "" and count in ["dual", "plural"] do
          inflect_compound_to_plural(display_string)
        else
          inflect_word_chain(display_string, constraint_values, disambiguation)
        end
    end
  end

  defp inflect_word_chain(display_string, constraint_values, disambiguation) do
    words = String.split(display_string, " ")

    result =
      Enum.reduce_while(words, [], fn word, acc ->
        grammemes = Dictionary.combined_grammemes(@locale, word)

        inflected =
          Inflector.inflect(@locale, word, grammemes || 0, constraint_values,
            disambiguation: disambiguation,
            priorities: @priorities
          )

        case {inflected, grammemes} do
          {{:ok, value}, _grammemes} -> {:cont, [value | acc]}
          {:error, grammemes} when grammemes != nil -> {:cont, [word | acc]}
          {:error, nil} -> {:halt, :error}
        end
      end)

    case result do
      :error -> display_string
      [] -> display_string
      inflected -> inflected |> Enum.reverse() |> Enum.join(" ")
    end
  end

  # ── Pluralization heuristics ─────────────────────────────────

  @doc false
  def single_word_stem_to_plural(stem) do
    plural =
      case Map.get(@final_to_medial, String.last(stem) || "") do
        nil -> stem
        medial -> String.slice(stem, 0..-2//1) <> medial
      end

    cond do
      Map.has_key?(@irregular_plurals, stem) ->
        Map.fetch!(@irregular_plurals, stem)

      stem in @ot_plurals ->
        plural <> "ות"

      String.ends_with?(plural, "וה") ->
        String.slice(plural, 0..-3//1) <> "ות"

      String.ends_with?(plural, "ה") ->
        String.slice(plural, 0..-2//1) <> "ות"

      String.ends_with?(plural, "אי") ->
        plural <> "ם"

      String.ends_with?(plural, "ית") ->
        String.slice(plural, 0..-3//1) <> "יות"

      String.ends_with?(plural, "ות") ->
        String.slice(plural, 0..-3//1) <> "ויות"

      String.ends_with?(plural, "ת") ->
        String.slice(plural, 0..-2//1) <> "ות"

      plural != "" ->
        plural <> "ים"

      true ->
        plural
    end
  end

  defp pluralize_construct(first_word) do
    word_grammemes = Dictionary.combined_grammemes(@locale, first_word) || 0

    from_inflector =
      case Inflector.inflect(@locale, first_word, word_grammemes, ["plural"],
             optional_constraints: ["construct"],
             priorities: @priorities
           ) do
        {:ok, inflected} -> inflected
        :error -> nil
      end

    from_inflector ||
      first_word
      |> single_word_stem_to_plural()
      |> then(fn plural ->
        if String.ends_with?(plural, "ם") do
          String.slice(plural, 0..-2//1)
        else
          plural
        end
      end)
  end

  defp inflect_compound_to_plural(stem) do
    case String.split(stem, " ") do
      [""] ->
        stem

      [single] ->
        single_word_stem_to_plural(single)

      [first | rest] ->
        noun = Dictionary.binary_properties(@locale, ["noun"]) || 0
        adjective = Dictionary.binary_properties(@locale, ["adjective"]) || 0

        all_nouns? =
          Enum.all?(rest, fn word ->
            grammemes = Dictionary.combined_grammemes(@locale, word) || 0
            (grammemes &&& noun) != 0 and (grammemes &&& adjective) == 0
          end)

        if all_nouns? do
          # Noun-noun compound (smichut): only the first word
          # pluralizes, into construct state.
          Enum.join([pluralize_construct(first) | rest], " ")
        else
          Enum.map_join([first | rest], " ", &single_word_stem_to_plural/1)
        end
    end
  end

  # ── Definiteness prefix ──────────────────────────────────────

  defp apply_definiteness(input, "definite") when input != "" do
    tokens = Tokenizer.word_tokens(@locale, input)

    cond do
      tokens == [] ->
        prefix_he(input)

      length(tokens) == 1 ->
        prefix_he(input)

      preposition_in_tail?(tl(tokens)) ->
        prefix_he(input)

      true ->
        last = List.last(tokens)
        head = binary_part(input, 0, last.start)
        tail = binary_part(input, last.start, byte_size(input) - last.start)
        head <> prefix_he(tail)
    end
  end

  defp apply_definiteness(input, _definiteness), do: input

  defp prefix_he(string) do
    if String.starts_with?(string, "ה"), do: string, else: "ה" <> string
  end

  defp preposition_in_tail?(tokens) do
    Enum.any?(tokens, &preposition?(&1.value))
  end

  defp preposition?(word) do
    adposition = Dictionary.binary_properties(@locale, ["adposition"]) || 0

    case Dictionary.combined_grammemes(@locale, word) do
      nil ->
        with true <- String.length(word) > 1,
             {first, rest} <- String.split_at(word, 1),
             true <- first in @inseparable_prefixes do
          Dictionary.combined_grammemes(@locale, rest) != nil
        else
          _other -> false
        end

      grammemes ->
        (grammemes &&& adposition) != 0
    end
  end

  defp empty_to_nil(""), do: nil
  defp empty_to_nil(value), do: value
end
