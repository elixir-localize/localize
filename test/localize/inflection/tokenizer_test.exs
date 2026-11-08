defmodule Localize.Inflection.TokenizerTest do
  use ExUnit.Case, async: true

  alias Localize.Inflection.Tokenizer

  # Phrases in languages that have a synthesizer, whose tokens must not
  # depend on whether `unicode_string` is installed.
  @phrases [
    {:en, "light on the patio"},
    {:en, "rock n'roll don't"},
    {:en, "the U.S. dollar"},
    {:fr, "l'école d'action"},
    {:it, "dell'arte"},
    {:de, "der Domain-Eigentümer"},
    {:nl, "auto’s van de buurman"},
    {:hi, "दरवाज़ा में"},
    {:he, "ילד קטן"},
    {:ar, "رسالتان"},
    {:ko, "집은 크다"},
    {:tr, "İstanbul'da"},
    {:ml, "വീട് മനോഹരം"},
    {:pl, "nowy."}
  ]

  test "unicode_string is the backend here, where the library is installed" do
    assert Tokenizer.backend() == :unicode_string
  end

  test "both backends find the same words in a language that has a synthesizer" do
    for {locale, phrase} <- @phrases do
      assert Tokenizer.word_tokens(locale, phrase, :unicode_string) ==
               Tokenizer.word_tokens(locale, phrase, :regex),
             "#{locale} #{inspect(phrase)}"
    end
  end

  test "apostrophes and hyphens end a word, Dutch keeps its apostrophe, a period stays between alphanumerics" do
    assert values(:fr, "l'école d'action") == ["l", "école", "d", "action"]
    assert values(:en, "rock n'roll don't") == ["rock", "n", "roll", "don", "t"]
    assert values(:de, "der Domain-Eigentümer") == ["der", "Domain", "Eigentümer"]
    assert values(:nl, "auto’s van de buurman") == ["auto’s", "van", "de", "buurman"]
    assert values(:en, "the U.S. dollar") == ["the", "U.S", "dollar"]
    assert values(:pl, "nowy.") == ["nowy"]
  end

  test "a token's offsets address its value in the phrase, and clean is its lowercase" do
    for {locale, phrase} <- @phrases ++ [{:th, "บ้านสวยมาก"}],
        backend <- [:unicode_string, :regex],
        token <- Tokenizer.word_tokens(locale, phrase, backend) do
      assert binary_part(phrase, token.start, token.stop - token.start) == token.value
      assert token.clean == String.downcase(token.value, downcase_mode(locale))
      assert token.word?
    end
  end

  test "a Thai phrase breaks into dictionary words with unicode_string, and is one run without" do
    assert values(:th, "บ้านสวยมาก") == ["บ้าน", "สวย", "มาก"]
    assert values(:th, "บ้านสวยมาก", :regex) == ["บ้านสวยมาก"]
  end

  # The Chinese and Japanese dictionary loads in under a second and takes
  # about 100 MB, which the suite can afford.
  test "a Chinese or Japanese phrase breaks into dictionary words with unicode_string" do
    assert values(:ja, "東京の美しい家") == ["東京", "の", "美しい", "家"]
    assert values(:zh, "我爱北京天安门") == ["我", "爱", "北京", "天安门"]
    assert values(:ja, "東京の美しい家", :regex) == ["東京の美しい家"]
  end

  test "a locale unicode_string has no rules for segments by the root rules" do
    assert values(:ml, "വീട് മനോഹരം") == ["വീട്", "മനോഹരം"]
    assert values(:kn, "ಮನೆ ಸುಂದರ") == ["ಮನೆ", "ಸುಂದರ"]
  end

  test "an empty phrase and one of punctuation have no tokens" do
    assert Tokenizer.word_tokens(:en, "") == []
    assert Tokenizer.word_tokens(:en, " - ") == []
    assert Tokenizer.last_word(:en, "") == nil
    assert Tokenizer.first_word(:en, "...") == nil
  end

  defp values(locale, phrase, backend \\ Tokenizer.backend()) do
    locale
    |> Tokenizer.word_tokens(phrase, backend)
    |> Enum.map(& &1.value)
  end

  defp downcase_mode(:tr) do
    :turkic
  end

  defp downcase_mode(_locale) do
    :default
  end
end
