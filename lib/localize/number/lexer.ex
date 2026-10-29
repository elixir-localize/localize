defmodule Localize.Number.Lexer do
  @moduledoc """
  Reads a string into the tokens the number and currency amount
  grammars parse.

  The lexer makes one pass over the string and classifies each
  character with the `t:Localize.Number.Lexicon.t/0` it is given:
  digits of the lexicon's number system and Latin digits read as
  digits, the characters of the minus and plus families as signs,
  the separator families as marks, and so on. It drops nothing and
  decides nothing: a format character, an underscore and a space are
  each a token of their own, and whether a mark is a decimal separator
  depends on the reading, which is the grammar's business. Every
  token keeps the text it was read from, so an error can quote the
  input as it was written.

  Consecutive digits, consecutive digits of another number system
  and consecutive text characters each merge into one token; every
  other token is one character.

  """

  alias Localize.Number.Lexicon

  @typedoc """
  The kinds of token.

  * `:digits` — a run of digits, with their Latin value.

  * `:other_digits` — a run of digits of a number system the lexicon
    does not read.

  * `:mark` — a punctuation mark, a final quotation mark, or a
    character that is a separator in some reading.

  * `:space` — a space character (`[:Zs:]`).

  * `:minus` and `:plus` — a sign.

  * `:dash` — a dash that may stand for a zero fraction and is not a
    minus.

  * `:open` and `:close` — a parenthesis.

  * `:underscore` — Elixir's digit separator.

  * `:tab` — a tab, which may decorate a currency amount but is no
    space inside a number.

  * `:bidi` — a Unicode bidi control character.

  * `:format` — any other format character (`[:Cf:]`).

  * `:text` — a run of anything else.

  """
  @type kind ::
          :digits
          | :other_digits
          | :mark
          | :space
          | :minus
          | :plus
          | :dash
          | :open
          | :close
          | :underscore
          | :tab
          | :bidi
          | :format
          | :text

  @typedoc """
  A token: its kind, its value and the text it was read from. The
  value differs from the text only for `:digits`, whose value is the
  digits as Latin digits.
  """
  @type token :: {kind(), String.t(), String.t()}

  # Unicode's Bidi_Control characters: ALM, LRM, RLM, the embeddings and
  # overrides, and the isolates. CLDR writes them into the signs and
  # currency formats of the right-to-left locales.
  @bidi_controls [0x061C, 0x200E, 0x200F, 0x202A, 0x202B, 0x202C, 0x202D, 0x202E] ++
                   [0x2066, 0x2067, 0x2068, 0x2069]

  # The space separators, `[:Zs:]`.
  @spaces [0x0020, 0x00A0, 0x1680] ++
            Enum.to_list(0x2000..0x200A) ++ [0x202F, 0x205F, 0x3000]

  # ASCII's punctuation marks (`Po`): the rest of ASCII's punctuation is a
  # sign, a parenthesis, a bracket or a symbol, none of them a mark.
  @ascii_marks ~c[!"#%&'*,./:;?@\\]

  # A character the lexicon does not know and ASCII does not settle is
  # classed by Unicode's categories: a format character, a digit of some
  # other number system, or a punctuation mark (`Po` or a final quotation
  # mark, which may close a number; an initial one may not). One regular
  # expression, so the lookup is one call.
  @categories ~r/\A(?:(\p{Cf})|(\p{Nd})|([\p{Po}\p{Pf}]))\z/u

  @doc """
  Returns the tokens of a string.

  ### Arguments

  * `string` is the string to read.

  * `lexicon` is the `t:Localize.Number.Lexicon.t/0` to read it with.

  ### Returns

  * A list of `t:token/0` in the order read.

  ### Examples

      iex> {:ok, en} = Localize.validate_locale(:en)
      iex> {:ok, lexicon} = Localize.Number.Lexicon.fetch(en, :latn, [])
      iex> Localize.Number.Lexer.tokens("USD -1,234.5", lexicon)
      [
        {:text, "USD", "USD"},
        {:space, " ", " "},
        {:minus, "-", "-"},
        {:digits, "1", "1"},
        {:mark, ",", ","},
        {:digits, "234", "234"},
        {:mark, ".", "."},
        {:digits, "5", "5"}
      ]

      iex> {:ok, ar_eg} = Localize.validate_locale(:"ar-EG")
      iex> {:ok, lexicon} = Localize.Number.Lexicon.fetch(ar_eg, :arab, [])
      iex> Localize.Number.Lexer.tokens("١٢٫٥", lexicon)
      [{:digits, "12", "١٢"}, {:mark, "٫", "٫"}, {:digits, "5", "٥"}]

  """
  @spec tokens(String.t(), Lexicon.t()) :: [token()]
  def tokens(string, %Lexicon{} = lexicon) when is_binary(string) do
    string
    |> lex(lexicon, [])
    |> Enum.reverse()
  end

  defp lex(<<>>, _lexicon, tokens) do
    tokens
  end

  defp lex(<<codepoint::utf8, rest::binary>>, lexicon, tokens) do
    character = <<codepoint::utf8>>
    {kind, value} = classify(codepoint, character, lexicon)
    lex(rest, lexicon, push(tokens, kind, value, character))
  end

  # The lexicon's own sets first, since they settle the characters that
  # matter most and cost a lookup each. A space is read before the marks,
  # because a locale that groups with a space has that space in its group
  # set.
  defp classify(codepoint, character, lexicon) do
    cond do
      codepoint in @bidi_controls -> {:bidi, character}
      digit = Map.get(lexicon.digits, character) -> {:digits, <<?0 + digit>>}
      MapSet.member?(lexicon.minus, character) -> {:minus, character}
      MapSet.member?(lexicon.plus, character) -> {:plus, character}
      MapSet.member?(lexicon.dashes, character) -> {:dash, character}
      codepoint in @spaces -> {:space, character}
      MapSet.member?(lexicon.marks, character) -> {:mark, character}
      true -> {fixed_kind(codepoint, character), character}
    end
  end

  # What the lexicon does not settle: the parentheses and the underscore,
  # then ASCII, and Unicode's categories only for what is left.
  defp fixed_kind(codepoint, character) do
    cond do
      codepoint == ?( -> :open
      codepoint == ?) -> :close
      codepoint == ?_ -> :underscore
      codepoint == ?\t -> :tab
      codepoint < 128 -> ascii_kind(codepoint)
      true -> category_kind(character)
    end
  end

  defp ascii_kind(codepoint) when codepoint in @ascii_marks do
    :mark
  end

  defp ascii_kind(_codepoint) do
    :text
  end

  defp category_kind(character) do
    case Regex.run(@categories, character) do
      [_character, format] when format != "" -> :format
      [_character, "", digit] when digit != "" -> :other_digits
      [_character, "", "", _mark] -> :mark
      _not_classed -> :text
    end
  end

  # Digits, other digits and text run together into one token each.
  defp push([{kind, value, source} | tokens], kind, more_value, more_source)
       when kind in [:digits, :other_digits, :text] do
    [{kind, value <> more_value, source <> more_source} | tokens]
  end

  defp push(tokens, kind, value, source) do
    [{kind, value, source} | tokens]
  end
end
