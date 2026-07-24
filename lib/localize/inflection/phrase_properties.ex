defmodule Localize.Inflection.PhraseProperties do
  @moduledoc false

  # Phonetic phrase properties used for article selection, ported
  # from the upstream `PhraseProperties`.
  #
  # A word's sound may be recorded in the dictionary with the
  # `vowel-start` / `consonant-start` grammemes; otherwise the first
  # letter or digit is tested against the default vowel set
  # (NFKD-decomposed so accented vowels match).

  alias Localize.Inflection.Dictionary

  import Bitwise

  @default_vowels ~c"aeiouıæœøаеиоуыэюя" ++ Enum.to_list(0x1161..0x1175)

  @doc """
  Returns true when the phrase phonetically starts with a vowel for
  article-selection purposes.

  """
  def starts_with_vowel?(locale, phrase) do
    case dictionary_sound(locale, phrase, "vowel-start", "consonant-start") do
      :vowel ->
        true

      :consonant ->
        false

      :unknown ->
        # French: a known word starting with a capital H (often a
        # proper noun) does not elide — "le Havre", not "l’Havre".
        if french?(locale) and String.starts_with?(phrase, "H") and
             Dictionary.combined_grammemes(locale, phrase) != nil do
          false
        else
          first_letter_vowel?(phrase, vowels(locale))
        end
    end
  end

  defp french?(locale), do: match?("fr" <> _rest, Atom.to_string(locale))

  @doc """
  Returns true when the codepoint is in the default vowel set.

  """
  def default_vowel?(codepoint) when is_integer(codepoint) do
    codepoint in @default_vowels or
      (codepoint >= ?A and codepoint <= ?Z and (codepoint + 32) in @default_vowels)
  end

  @doc """
  Returns true when the phrase phonetically ends with a vowel.

  """
  def ends_with_vowel?(locale, phrase) do
    stripped = String.replace(phrase, ~r/(?!&)[\p{P}\p{S}]/u, "")

    # Turkish uses the plain vowel set; other languages also count
    # a final y as vocalic.
    vowels =
      case Atom.to_string(locale) do
        "tr" <> _rest -> @default_vowels
        _other -> [?y | @default_vowels]
      end

    case dictionary_sound(locale, stripped, "vowel-end", "consonant-end") do
      :vowel -> true
      :consonant -> false
      :unknown -> last_letter_vowel?(stripped, vowels)
    end
  end

  defp last_letter_vowel?(phrase, vowels) do
    case last_matchable(phrase) do
      nil ->
        false

      codepoint ->
        decomposed =
          <<codepoint::utf8>>
          |> :unicode.characters_to_nfkd_binary()
          |> String.downcase()

        case decomposed do
          <<first::utf8, _rest::binary>> -> first in vowels
          _other -> false
        end
    end
  end

  defp last_matchable(phrase) do
    phrase
    |> String.reverse()
    |> first_matchable_string()
  end

  defp first_matchable_string(<<codepoint::utf8, rest::binary>>) do
    if <<codepoint::utf8>> =~ ~r/[[:alpha:][:digit:]]/u do
      codepoint
    else
      first_matchable_string(rest)
    end
  end

  defp first_matchable_string(<<_byte, rest::binary>>), do: first_matchable_string(rest)
  defp first_matchable_string(<<>>), do: nil

  defp dictionary_sound(locale, phrase, vowel_tag, consonant_tag) do
    with mask when is_integer(mask) <- Dictionary.combined_grammemes(locale, phrase),
         vowel when is_integer(vowel) <- Dictionary.binary_properties(locale, [vowel_tag]),
         consonant when is_integer(consonant) <-
           Dictionary.binary_properties(locale, [consonant_tag]) do
      cond do
        (mask &&& vowel) != 0 and (mask &&& consonant) == 0 -> :vowel
        (mask &&& vowel) == 0 and (mask &&& consonant) != 0 -> :consonant
        true -> :unknown
      end
    else
      _other -> :unknown
    end
  end

  defp vowels(locale) do
    case Atom.to_string(locale) do
      "fr" <> _rest -> [?h | @default_vowels]
      _other -> @default_vowels
    end
  end

  defp first_letter_vowel?(phrase, vowels) do
    case first_matchable(phrase) do
      nil ->
        false

      codepoint ->
        decomposed =
          <<codepoint::utf8>>
          |> :unicode.characters_to_nfkd_binary()
          |> String.downcase()

        case decomposed do
          <<first::utf8, _rest::binary>> -> first in vowels
          _other -> false
        end
    end
  end

  # The first letter or decimal digit in the phrase, skipping
  # punctuation and whitespace.
  defp first_matchable(<<codepoint::utf8, rest::binary>>) do
    char = <<codepoint::utf8>>

    if char =~ ~r/[[:alpha:][:digit:]]/u do
      codepoint
    else
      first_matchable(rest)
    end
  end

  defp first_matchable(<<_byte, rest::binary>>), do: first_matchable(rest)
  defp first_matchable(<<>>), do: nil
end
