defmodule Localize.Inflection.GrammemeLookup do
  @moduledoc false

  # Port of the upstream `GrammemeLookupFunction`: a dictionary
  # category lookup with phrase handling, an optional default value
  # and an optional suffix-guess function. Used by French (gender)
  # and other Wave 1+ languages.

  alias Localize.Inflection.{Dictionary, Lookup, Tokenizer}

  @doc """
  Determines the category value of a word or phrase.

  ### Options

  * `:disambiguation` is the part-of-speech priority list passed to
    the dictionary lookup.

  * `:default` is returned when nothing else determines a value
    (defaults to "").

  * `:first_word_determines?` selects the first relevant word
    rather than the last (defaults to false).

  * `:suffix_function` is a `word -> value | ""` guess applied to
    the first token's clean value as a last resort.

  * `:relevant` is the grammeme list a token must carry to be
    considered relevant (defaults to `["noun"]` when
    `:disambiguation` or `:default` is given, mirroring upstream).

  """
  def determine(_locale, "", _tags, _options), do: ""

  def determine(locale, word, tags, options) do
    disambiguation = Keyword.get(options, :disambiguation, [])

    case Lookup.determine(locale, word, tags, disambiguation: disambiguation) do
      "" -> determine_from_tokens(locale, word, tags, options)
      out -> out
    end
  end

  defp determine_from_tokens(locale, word, tags, options) do
    disambiguation = Keyword.get(options, :disambiguation, [])
    relevant_names = Keyword.get(options, :relevant, ["noun"])
    relevant = Dictionary.binary_properties(locale, relevant_names) || 0
    tokens = Tokenizer.word_tokens(locale, word)

    out =
      if Keyword.get(options, :first_word_determines?, false) do
        first_word_determine(locale, tokens, tags, disambiguation, relevant)
      else
        last_word_determine(locale, tokens, tags, disambiguation, relevant)
      end

    out =
      with "" <- out,
           suffix_function when is_function(suffix_function, 1) <-
             Keyword.get(options, :suffix_function) do
        case List.first(tokens) do
          nil -> ""
          token -> suffix_function.(token.clean)
        end
      else
        other when is_binary(other) -> other
        nil -> ""
      end

    if out == "", do: Keyword.get(options, :default, ""), else: out
  end

  defp first_word_determine(locale, tokens, tags, disambiguation, relevant) do
    first_relevant =
      Enum.find(tokens, fn token ->
        relevant == 0 or Dictionary.has_all_properties?(locale, token.clean, relevant)
      end)

    out =
      case first_relevant do
        nil -> ""
        token -> Lookup.determine(locale, token.value, tags, disambiguation: disambiguation)
      end

    case {out, tokens} do
      {"", [first | _rest]} ->
        Lookup.determine(locale, first.value, tags, disambiguation: disambiguation)

      _other ->
        out
    end
  end

  defp last_word_determine(locale, tokens, tags, disambiguation, relevant) do
    out =
      Enum.reduce(tokens, "", fn token, acc ->
        if relevant == 0 or Dictionary.has_all_properties?(locale, token.clean, relevant) do
          case Lookup.determine(locale, token.value, tags, disambiguation: disambiguation) do
            "" -> acc
            value -> value
          end
        else
          acc
        end
      end)

    case {out, List.last(tokens)} do
      {"", last} when not is_nil(last) ->
        Lookup.determine(locale, last.value, tags, disambiguation: disambiguation)

      _other ->
        out
    end
  end
end
