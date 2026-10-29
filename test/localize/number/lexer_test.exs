defmodule Localize.Number.LexerTest do
  use ExUnit.Case, async: true

  alias Localize.Number.{Lexer, Lexicon}

  doctest Lexer

  defp tokens(string, locale \\ :en, number_system \\ :latn, options \\ []) do
    {:ok, language_tag} = Localize.validate_locale(locale)
    {:ok, lexicon} = Lexicon.fetch(language_tag, number_system, options)
    Lexer.tokens(string, lexicon)
  end

  # The kinds alone, for inputs whose values are their sources.
  defp kinds(string, locale \\ :en) do
    Enum.map(tokens(string, locale), fn {kind, value, _source} -> {kind, value} end)
  end

  test "digits, marks and signs of a Latin number" do
    assert kinds("1,234.56") == [
             {:digits, "1"},
             {:mark, ","},
             {:digits, "234"},
             {:mark, "."},
             {:digits, "56"}
           ]

    assert kinds("-5") == [{:minus, "-"}, {:digits, "5"}]
    assert kinds("−5") == [{:minus, "−"}, {:digits, "5"}]
    assert kinds("+5") == [{:plus, "+"}, {:digits, "5"}]
    assert kinds("(5)") == [{:open, "("}, {:digits, "5"}, {:close, ")"}]
    assert kinds("1e5") == [{:digits, "1"}, {:text, "e"}, {:digits, "5"}]

    assert kinds("1.5E-2") == [
             {:digits, "1"},
             {:mark, "."},
             {:digits, "5"},
             {:text, "E"},
             {:minus, "-"},
             {:digits, "2"}
           ]
  end

  test "text runs together, spaces and underscores stand alone" do
    assert kinds("USD 100") == [{:text, "USD"}, {:space, " "}, {:digits, "100"}]
    assert kinds("₿1.5") == [{:text, "₿"}, {:digits, "1"}, {:mark, "."}, {:digits, "5"}]
    assert kinds("1_000") == [{:digits, "1"}, {:underscore, "_"}, {:digits, "000"}]
    assert kinds("1 234") == [{:digits, "1"}, {:space, " "}, {:digits, "234"}]
    assert kinds("1 234") == [{:digits, "1"}, {:space, " "}, {:digits, "234"}]
    assert kinds("") == []
  end

  test "a dash is a minus where the locale's minus family has it, else a dash" do
    # `en` folds the en dash onto the minus; `de-CH` does not.
    assert kinds("5.–", :en) == [{:digits, "5"}, {:mark, "."}, {:minus, "–"}]
    assert kinds("5.–", :"de-CH") == [{:digits, "5"}, {:mark, "."}, {:dash, "–"}]
    assert kinds("5.—", :en) == [{:digits, "5"}, {:mark, "."}, {:dash, "—"}]
  end

  test "bidi controls and other format characters are their own tokens" do
    assert kinds("‎-5‏") == [
             {:bidi, "‎"},
             {:minus, "-"},
             {:digits, "5"},
             {:bidi, "‏"}
           ]

    assert kinds("U­SD") == [{:text, "U"}, {:format, "­"}, {:text, "SD"}]
    assert kinds("؜-٥", :en) == [{:bidi, "؜"}, {:minus, "-"}, {:other_digits, "٥"}]
  end

  test "digits of the lexicon's number system carry their Latin value and their source" do
    assert tokens("١٬٢٣٤٫٥٦", :"ar-EG", :arab) == [
             {:digits, "1", "١"},
             {:mark, "٬", "٬"},
             {:digits, "234", "٢٣٤"},
             {:mark, "٫", "٫"},
             {:digits, "56", "٥٦"}
           ]

    # Latin digits read in every system, and run together with the native ones.
    assert tokens("1٢", :"ar-EG", :arab) == [{:digits, "12", "1٢"}]
  end

  test "digits of another number system are other digits" do
    assert kinds("١٢", :en) == [{:other_digits, "١٢"}]
    assert kinds("５", :en) == [{:other_digits, "５"}]
    assert kinds("1٥", :en) == [{:digits, "1"}, {:other_digits, "٥"}]
    # A superscript is no digit.
    assert kinds("5²", :en) == [{:digits, "5"}, {:text, "²"}]
  end

  test "a separator family's characters are marks in the locale that folds them" do
    assert kinds("1'234", :"de-CH") == [{:digits, "1"}, {:mark, "'"}, {:digits, "234"}]
    assert kinds("1’234", :"de-CH") == [{:digits, "1"}, {:mark, "’"}, {:digits, "234"}]
    assert kinds("1，234", :en) == [{:digits, "1"}, {:mark, "，"}, {:digits, "234"}]
    assert kinds("1。5", :de) == [{:digits, "1"}, {:mark, "。"}, {:digits, "5"}]
  end

  test "punctuation outside every family is still a mark, and symbols are text" do
    assert kinds("5!", :en) == [{:digits, "5"}, {:mark, "!"}]
    assert kinds("5؟", :en) == [{:digits, "5"}, {:mark, "؟"}]
    assert kinds("$5", :en) == [{:text, "$"}, {:digits, "5"}]
    assert kinds("[5]", :en) == [{:text, "["}, {:digits, "5"}, {:text, "]"}]
    # A final quotation mark may close a number, an initial one may not.
    assert kinds("5»", :en) == [{:digits, "5"}, {:mark, "»"}]
    assert kinds("«5", :en) == [{:text, "«"}, {:digits, "5"}]
  end

  test "a tab is its own token" do
    assert kinds("USD\t5", :en) == [{:text, "USD"}, {:tab, "\t"}, {:digits, "5"}]
  end
end
