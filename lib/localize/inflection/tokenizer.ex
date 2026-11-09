defmodule Localize.Inflection.Tokenizer do
  @moduledoc false

  # The word tokenizer behind the inflection synthesizers. Each token is
  # `%{value:, clean:, start:, stop:, word?:}` where `start`/`stop` are
  # byte offsets into the original string, `clean` is the lowercased
  # value, and `word?` is true when the token contains a letter or
  # digit.
  #
  # Words are found in two passes. Where the consumer has `unicode_string`
  # the phrase is first segmented by UAX #29 (`Unicode.String.split/2`
  # with `break: :word`, in the locale), which is where a Chinese,
  # Japanese or Thai phrase breaks into dictionary words; without it the
  # phrase is one segment. Each segment is then scanned for words by a
  # pattern that draws the boundaries upstream's break iterator draws
  # and the synthesizers rely on: apostrophes and hyphens end a word, so
  # "d'action" is "d" + "action" and "Domain-Eigentümer" is "Domain" +
  # "Eigentümer", except that Dutch keeps its apostrophes ("auto’s" is a
  # dictionary key); a period stays inside a word only between
  # alphanumerics ("U.S." is one word, "nowy." is "nowy" + "."), as in
  # UAX #29; and combining marks (Indic vowel signs, viramas) continue
  # a word. UAX #29 keeps "d'action" whole, so the second pass is what
  # makes the two installations agree on every language that has a
  # synthesizer.
  #
  # Localize declares no dependency on `unicode_string`, which depends
  # optionally on Localize, so the dependency points one way; the module
  # is looked for at runtime (`Code.ensure_loaded?/1`, a loaded-module
  # check once it is loaded), and the compiler is told not to expect it,
  # so Localize compiles and runs without it. The application environment
  # key `:inflection_word_break` chooses `:unicode_string` or `:regex`
  # outright; the default, `:auto`, takes `unicode_string` when it is
  # there.

  @compile {:no_warn_undefined, Unicode.String}

  @word_pattern ~r/[[:alpha:][:digit:]][[:alpha:][:digit:]\p{M}]*(?:\.[[:alpha:][:digit:]][[:alpha:][:digit:]\p{M}]*)*/u

  @dutch_word_pattern ~r/[[:alpha:][:digit:]][[:alpha:][:digit:]\p{M}]*(?:['’\.][[:alpha:][:digit:]][[:alpha:][:digit:]\p{M}]*)*/u

  @doc """
  Tokenizes a phrase into word and separator tokens, returning word
  tokens only.

  """
  def word_tokens(locale, phrase) do
    word_tokens(locale, phrase, backend())
  end

  @doc """
  Tokenizes a phrase with the given backend, `:unicode_string` or
  `:regex`; `:unicode_string` scans the phrase as one segment when the
  library is not installed.

  """
  def word_tokens(locale, phrase, backend) do
    {tokens, _offset} =
      locale
      |> segments(phrase, backend)
      |> Enum.flat_map_reduce(0, fn segment, offset ->
        {scan(locale, segment, offset), offset + byte_size(segment)}
      end)

    tokens
  end

  @doc """
  The backend `word_tokens/2` segments with: the one the application
  environment key `:inflection_word_break` names, `:unicode_string` or
  `:regex`, or by default `:unicode_string` when `Unicode.String` is
  loaded and `:regex` otherwise. Any other value of the key is read as
  the default.

  """
  def backend do
    case Application.get_env(:localize, :inflection_word_break, :auto) do
      :unicode_string -> :unicode_string
      :regex -> :regex
      _auto -> detected_backend()
    end
  end

  defp detected_backend do
    if Code.ensure_loaded?(Unicode.String) do
      :unicode_string
    else
      :regex
    end
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

  # The segments of the phrase in order, whitespace and punctuation
  # included, so that they concatenate to the phrase and carry its byte
  # offsets. A locale `unicode_string` has no rules for segments by the
  # root rules. Without the module the phrase is one segment.
  defp segments(locale, phrase, :unicode_string) do
    if Code.ensure_loaded?(Unicode.String) do
      unicode_string_segments(locale, phrase)
    else
      [phrase]
    end
  end

  defp segments(_locale, phrase, :regex) do
    [phrase]
  end

  defp unicode_string_segments(locale, phrase) do
    case Unicode.String.split(phrase, break: :word, locale: locale) do
      segments when is_list(segments) -> segments
      _error -> [phrase]
    end
  end

  defp scan(locale, segment, offset) do
    locale
    |> word_pattern()
    |> Regex.scan(segment, return: :index)
    |> Enum.map(fn [{start, length}] ->
      value = binary_part(segment, start, length)

      %{
        value: value,
        clean: String.downcase(value, downcase_mode(locale)),
        start: offset + start,
        stop: offset + start + length,
        word?: true
      }
    end)
  end

  defp word_pattern(:nl) do
    @dutch_word_pattern
  end

  defp word_pattern(_locale) do
    @word_pattern
  end

  defp downcase_mode(locale) do
    case Atom.to_string(locale) do
      "tr" <> _rest -> :turkic
      "az" <> _rest -> :turkic
      _other -> :default
    end
  end
end
