defmodule Localize.Inflection.Synthesizer.Ko do
  @moduledoc false

  # The per-language synthesizers and conformance harnesses are ported
  # from the upstream C++ linguistic rule tables; their branchiness and
  # nesting mirror the reference implementation they are verified
  # against (see guides/inflection.md).
  # credo:disable-for-this-file Credo.Check.Refactor.CyclomaticComplexity
  # credo:disable-for-this-file Credo.Check.Refactor.Nesting

  # The Korean grammar synthesizer, ported from
  # `KoGrammarSynthesizer`: pure particle attachment. The display
  # function switches the postpositional particle (은/는, 이/가,
  # 을/를, …) according to whether the final syllable of the noun
  # ends in a vowel, a consonant or rieul (ㄹ); the noun itself is
  # never inflected.

  @behaviour Localize.Inflection.Synthesizer

  alias Localize.Inflection.{Dictionary, DisplayValue, PhraseProperties, Tokenizer}

  @locale :ko

  # {vowel_set, vowel_particle, consonant_particle} per particle
  # key. :vowels treats only vowel-final syllables as vocalic;
  # :vowels_with_rieul also treats rieul-final syllables as vocalic
  # (로/으로, 로부터/으로부터); :empty always selects the consonant
  # particle (the genitive is always 의).
  @particles %{
    "ablative" => {:vowels_with_rieul, "로부터", "으로부터"},
    "accusative" => {:vowels, "를", "을"},
    "comitative" => {:vowels, "와", "과"},
    "exclusive" => {:vowels, "는", "은"},
    "genitive" => {:empty, "", "의"},
    "inclusive" => {:vowels, "가", "이"},
    "instrumental" => {:vowels_with_rieul, "로", "으로"},
    "predicative" => {:vowels, "라", "이라"},
    "vocative" => {:vowels, "야", "아"}
  }

  # Precomposed Hangul syllables run from 가 (0xAC00) in blocks of
  # 28: jongseong index 0 is no final consonant, index 8 is ㄹ.
  @hangul_base 0xAC00
  @hangul_last 0xD7A3
  @jongseong_count 28
  @rieul_jongseong 8

  @jungseong_jamo 0x1161..0x1175
  @choseong_rieul 0x1105
  @jongseong_rieul 0x11AF

  # Non-Latin vowel-final codepoints outside Hangul (the upstream
  # DEFAULT_VOWELS_END minus Latin script): the Cyrillic vowels.
  @cyrillic_vowels ~c"аеиоуыэюя"

  @impl true
  def feature_value(_feature, _display_value, _constraints), do: nil

  @impl true
  def display_value(display_data, constraints, guess?) do
    case List.first(display_data) do
      %DisplayValue{} = display_value ->
        attach_particle(display_value, constraints, guess?)

      _other ->
        nil
    end
  end

  defp attach_particle(display_value, constraints, guess?) do
    display_string = display_value.display_string
    particle_key = particle_key(constraints)

    case Map.get(@particles, particle_key) do
      {_set, _vowel, _consonant} = particle when display_string != "" ->
        case switch_particle(display_string, particle, guess?) do
          {:ok, switched} -> %DisplayValue{display_string: switched, constraints: constraints}
          :error -> nil
        end

      _no_particle ->
        if guess? do
          %DisplayValue{display_string: display_string, constraints: constraints}
        else
          nil
        end
    end
  end

  # The nominative splits by clusivity: 이/가 for the inclusive
  # subject, 은/는 (the default) for the exclusive topic. An empty
  # case falls back to the adjectival constraint (predicative 라/이라).
  defp particle_key(constraints) do
    case Map.get(constraints, "case") || "" do
      "" ->
        Map.get(constraints, "adjectival") || ""

      "nominative" ->
        case Map.get(constraints, "clusivity") || "" do
          "" -> "exclusive"
          clusivity -> clusivity
        end

      value ->
        value
    end
  end

  # Replaces an already-attached particle of the same pair, then
  # appends the phonetically correct one.
  defp switch_particle(string, {_set, vowel_particle, consonant_particle} = particle, guess?) do
    stripped =
      cond do
        String.ends_with?(string, consonant_particle) ->
          binary_part(string, 0, byte_size(string) - byte_size(consonant_particle))

        vowel_particle != "" and String.ends_with?(string, vowel_particle) ->
          binary_part(string, 0, byte_size(string) - byte_size(vowel_particle))

        true ->
          string
      end

    case particle_value(stripped, particle, guess?) do
      "" -> :error
      value -> {:ok, stripped <> value}
    end
  end

  defp particle_value("", _particle, _guess?), do: ""

  defp particle_value(_string, {:empty, _vowel_particle, consonant_particle}, _guess?) do
    consonant_particle
  end

  defp particle_value(string, {set, vowel_particle, consonant_particle}, guess?) do
    relevant = relevant_string(string)
    last = last_matchable(relevant)

    cond do
      not guess? and (relevant == "" or not alphabetic?(last)) ->
        ""

      latin?(last) ->
        # Latin-letter endings (brand names) go through the
        # phonetic vowel test on the lowercased word.
        lowered = String.downcase(relevant)

        if (set == :vowels_with_rieul and ends_with_rieul?(lowered)) or
             ends_with_vowel?(lowered) do
          vowel_particle
        else
          consonant_particle
        end

      vowel_final?(last, set) ->
        vowel_particle

      true ->
        consonant_particle
    end
  end

  defp vowel_final?(nil, _set), do: false

  defp vowel_final?(codepoint, set)
       when codepoint >= @hangul_base and codepoint <= @hangul_last do
    case rem(codepoint - @hangul_base, @jongseong_count) do
      0 -> true
      @rieul_jongseong -> set == :vowels_with_rieul
      _other -> false
    end
  end

  defp vowel_final?(codepoint, set) do
    codepoint in @jungseong_jamo or codepoint in @cyrillic_vowels or
      (set == :vowels_with_rieul and codepoint in [@choseong_rieul, @jongseong_rieul])
  end

  # A dictionary "rieul-end" tag overrides the phonetic letter
  # test: Apple (애플) ends in ㄹ, a consonant for 은/이/을/과.
  defp ends_with_vowel?(word) do
    rieul_mask = Dictionary.binary_properties(@locale, ["rieul-end"])

    if is_integer(rieul_mask) and Dictionary.has_all_properties?(@locale, word, rieul_mask) do
      false
    else
      PhraseProperties.ends_with_vowel?(@locale, word)
    end
  end

  # A word tagged "rieul-end" in the dictionary, or ending with an
  # l/ㄹ character, is treated like a vowel for 로/으로.
  defp ends_with_rieul?(""), do: false

  defp ends_with_rieul?(string) do
    without_punctuation = String.replace(string, ~r/[\p{P}\p{S}]/u, "")
    rieul_mask = Dictionary.binary_properties(@locale, ["rieul-end"])

    (is_integer(rieul_mask) and rieul_mask != 0 and
       Dictionary.has_all_properties?(@locale, without_punctuation, rieul_mask)) or
      last_matchable(string) in [?l, ?L, @choseong_rieul, @jongseong_rieul]
  end

  # Trims a trailing bracketed segment (이름(주) -> 이름), then, when
  # the text does not end in Hangul, walks back to the last token
  # ending in a letter or digit.
  defp relevant_string(string) do
    trimmed =
      case Regex.run(~r/\p{Ps}.*[\p{Ps}\p{Pe}]/us, string, return: :index) do
        [{start, _length} | _rest] -> binary_part(string, 0, start)
        nil -> string
      end

    last = last_matchable(trimmed)

    if trimmed != "" and last != nil and not hangul?(last) do
      trimmed
      |> then(&Tokenizer.word_tokens(:en, &1))
      |> Enum.reverse()
      |> Enum.find_value(trimmed, fn token ->
        if last_matchable(token.value) != nil, do: token.value
      end)
    else
      trimmed
    end
  end

  defp hangul?(codepoint) do
    (codepoint >= @hangul_base and codepoint <= @hangul_last) or
      codepoint in 0x1100..0x11FF or codepoint in 0x3130..0x318F or
      codepoint in 0xA960..0xA97F or codepoint in 0xD7B0..0xD7FF
  end

  defp latin?(nil), do: false

  defp latin?(codepoint) do
    <<codepoint::utf8>> =~ ~r/\p{Latin}/u
  end

  defp alphabetic?(nil), do: false

  defp alphabetic?(codepoint) do
    <<codepoint::utf8>> =~ ~r/[[:alpha:]]/u
  end

  # The last letter or digit codepoint, skipping trailing
  # punctuation and symbols.
  defp last_matchable(string) do
    string
    |> String.reverse()
    |> first_matchable()
  end

  defp first_matchable(<<codepoint::utf8, rest::binary>>) do
    if <<codepoint::utf8>> =~ ~r/[[:alpha:][:digit:]]/u do
      codepoint
    else
      first_matchable(rest)
    end
  end

  defp first_matchable(<<_byte, rest::binary>>), do: first_matchable(rest)
  defp first_matchable(<<>>), do: nil
end
