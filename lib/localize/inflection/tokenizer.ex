defmodule Localize.Inflection.Tokenizer do
  @moduledoc false

  # A minimal word tokenizer sufficient for the space-and-punctuation
  # separated languages (English, Spanish and similar). Each token is
  # `%{value:, clean:, start:, stop:, word?:}` where `start`/`stop`
  # are byte offsets into the original string, `clean` is the
  # lowercased value, and `word?` is true when the token contains a
  # letter or digit.
  #
  # The upstream tokenizer delegates to the ICU break iterator;
  # languages needing dictionary-based segmentation or compound
  # splitting get their own tokenizer when those languages are
  # ported.

  @doc """
  Tokenizes a phrase into word and separator tokens, returning word
  tokens only.

  """
  def word_tokens(locale, phrase) do
    # Apostrophes and hyphens are token boundaries, as in the
    # upstream break iterator — "d'action" is "d" + "action" and
    # "Domain-Eigentümer" is "Domain" + "Eigentümer". Dutch keeps
    # apostrophes inside words (auto’s is a dictionary key).
    # Periods stay inside a token only between alphanumerics
    # ("U.S." is one token, "nowy." is "nowy" + "."), as in UAX29.
    # Combining marks (Indic vowel signs, viramas) continue a word.
    pattern =
      if locale == :nl do
        ~r/[[:alpha:][:digit:]][[:alpha:][:digit:]\p{M}]*(?:['’\.][[:alpha:][:digit:]][[:alpha:][:digit:]\p{M}]*)*/u
      else
        ~r/[[:alpha:][:digit:]][[:alpha:][:digit:]\p{M}]*(?:\.[[:alpha:][:digit:]][[:alpha:][:digit:]\p{M}]*)*/u
      end

    pattern
    |> Regex.scan(phrase, return: :index)
    |> Enum.map(fn [{start, length}] ->
      value = binary_part(phrase, start, length)

      %{
        value: value,
        clean: String.downcase(value, downcase_mode(locale)),
        start: start,
        stop: start + length,
        word?: true
      }
    end)
  end

  @doc """
  Returns the last word token of a phrase, or nil.

  """
  def last_word(locale, phrase) do
    locale |> word_tokens(phrase) |> List.last()
  end

  @doc """
  Returns the first word token of a phrase, or nil.

  """
  def first_word(locale, phrase) do
    locale |> word_tokens(phrase) |> List.first()
  end

  defp downcase_mode(locale) do
    case Atom.to_string(locale) do
      "tr" <> _rest -> :turkic
      "az" <> _rest -> :turkic
      _other -> :default
    end
  end
end
