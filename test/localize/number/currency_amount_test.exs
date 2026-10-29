defmodule Localize.Number.CurrencyAmountTest do
  use ExUnit.Case, async: true

  alias Localize.Number.Parser

  defp amount(string, options \\ []) do
    options = Keyword.put_new(options, :locale, :en)

    case Parser.parse_currency_amount(string, options) do
      {:ok, {currency, decimal}} -> {currency, Decimal.to_string(decimal, :normal)}
      {:error, exception} -> exception
    end
  end

  # Every amount ex_money's own parser reads in its test suite, which
  # `Money.parse/2` moves onto this function in ex_money 6.3.0. These are a
  # compatibility contract: change one only with ex_money in step.
  describe "ex_money's parse cases" do
    test "a currency code before the amount" do
      assert {:USD, "100"} = amount("USD 100")
      assert {:USD, "100"} = amount("USD100")
      assert {:USD, "100"} = amount("USD 100 ")
      assert {:USD, "100"} = amount("USD100 ")
      assert {:USD, "100.00"} = amount("USD 100.00")
      assert {:USD, "1"} = amount("USD 1")
      assert {:USD, "9"} = amount("USD9")
    end

    test "a currency code after the amount" do
      assert {:USD, "100"} = amount("100 USD")
      assert {:USD, "100"} = amount("100USD")
      assert {:USD, "100"} = amount("100 USD ")
      assert {:USD, "100.00"} = amount("100.00USD")
    end

    test "a currency name" do
      assert {:AUD, "12346.45"} = amount("australian dollar 12346.45")
      assert {:AUD, "12346.45"} = amount("12346.45 australian dollars")
      assert {:AUD, "12346.45"} = amount("12346.45 Australian Dollars")
      assert {:AUD, "12346"} = amount("12 346 dollar australien", locale: :fr)
      assert {:FRF, "100"} = amount("100 French francs")
    end

    test "the locale's separators and symbols" do
      assert {:USD, "100.00"} = amount("100,00USD", locale: :de)
      assert {:EUR, "99.99"} = amount("99.99€")
      assert {:EUR, "1127.54"} = amount("1.127,54 €", locale: :de)
      assert {:EUR, "1127.54"} = amount("1 127,54 €", locale: :fr)
      assert {:EUR, "1127.54"} = amount("1 127,54 €", locale: :fr)
      assert {:DKK, "4200.00"} = amount("4.200,00 kr.", locale: :da)
      assert {:MAD, "1234.56"} = amount("‏1.234,56 د.م.‏", locale: :"ar-MA")

      assert {:USD, "30000.00"} =
               amount("US$30 000,00", locale: :"en-ZA", separators: :standard)
    end

    test "a sign before, between or after" do
      assert {:EUR, "-127.54"} = amount("-127,54 €", locale: :fr)
      assert {:EUR, "-127.54"} = amount("-127,54€", locale: :fr)
      assert {:EUR, "-127.54"} = amount("€ 127,54-", locale: :nl)
      assert {:EUR, "-127.54"} = amount("€127,54-", locale: :nl)
      assert {:CHF, "-127.54"} = amount("CHF -127.54", locale: :"de-CH")
      assert {:CHF, "-127.54"} = amount("-127.54 CHF", locale: :"de-CH")
      assert {:DKK, "-127.54"} = amount("kr-127,54", locale: :da)
      assert {:DKK, "-127.54"} = amount("kr -127,54", locale: :da)
    end

    # ex_money read "($-127.54)" as 127.54 dollars, where others read it as
    # -127.54: it is refused.
    test "accounting parentheses negate the amount inside them" do
      assert {:USD, "-127.54"} = amount("($127.54)")
      assert %Localize.InvalidAmountError{amount: "(-127.54)"} = amount("($-127.54)")
    end

    test "currency filters and fuzzy matching" do
      assert %Localize.UnknownCurrencyError{currency: "French francs"} =
               amount("100 French francs", only: [:current])

      assert {:EUR, "100"} = amount("100 eurosports", fuzzy: 0.8)

      assert %Localize.UnknownCurrencyError{currency: "eurosports"} =
               amount("100 eurosports", fuzzy: 0.9)
    end

    test "a default currency" do
      assert {:USD, "100"} = amount("100", default_currency: :USD)
      assert {:USD, "100"} = amount("100", default_currency: "USD")
      assert {:AUD, "100"} = amount("100", default_currency: "australian dollars")
      assert {:EUR, "100"} = amount("EUR 100", default_currency: :USD)
    end

    test "a caller's own currencies" do
      token = fn text ->
        if String.downcase(text) in ["btc", "bitcoin"] do
          {:ok, "BTC"}
        else
          :error
        end
      end

      assert {"BTC", "100"} = amount("100 BTC", caller_currency: token)
      assert {"BTC", "100"} = amount("100 Bitcoin", caller_currency: token)
      assert {"BTC", "100"} = amount("BTC 100", caller_currency: token)
      assert {"BTC", "100"} = amount("Bitcoin 100", caller_currency: token)

      assert %Localize.UnknownCurrencyError{currency: "Dogecoin"} =
               amount("100 Dogecoin", caller_currency: token)
    end

    test "text that names a CLDR currency and a different one of the caller's is refused" do
      caller = fn text ->
        case text do
          "₮" -> {:ok, "USDT"}
          "S" -> {:ok, "SOME"}
          "K" -> {:ok, "KCOIN"}
          "MNT" -> {:ok, :MNT}
          _other -> :error
        end
      end

      # "₮" is the tugrik's symbol in `mn`, and only its narrow symbol in `en`.
      # In a locale whose own currency the text names, that currency takes it.
      assert {:MNT, "5"} = amount("₮5", locale: :mn)
      assert {:MNT, "5"} = amount("₮5", locale: :mn, caller_currency: caller)
      assert {:SOS, "5"} = amount("S5", locale: :so, caller_currency: caller)
      assert {:MMK, "5"} = amount("K5", locale: :my, caller_currency: caller)

      # Elsewhere "₮" names both, and neither is read: in `en` it is only the
      # tugrik's narrow symbol, but it still names the tugrik, so the
      # caller's Tether does not take it.
      assert %Localize.ParseError{detail: en_detail} = amount("₮5", caller_currency: caller)
      assert en_detail =~ "two currencies"
      assert {:MNT, "5"} = amount("MNT 5", caller_currency: caller)
      assert {:USD, "5"} = amount("5 USD", caller_currency: caller)
    end

    # A caller's currency has no separators in CLDR, so its amount is read
    # with the locale's and the root locale's, the form ex_money writes a
    # token amount in, and refused where the two differ.
    test "a caller's currency is read with the locale's separators and the root's" do
      token = fn text ->
        if text in ["BTC", "₿"] do
          {:ok, "BTC"}
        else
          :error
        end
      end

      for {string, locale, value} <- [
            {"₿1.234", :en, "1.234"},
            {"₿1.234", :fr, "1.234"},
            {"₿1234.56", :de, "1234.56"},
            {"₿0.00012345", :de, "0.00012345"},
            {"1,5 BTC", :de, "1.5"},
            {"1,234.56 BTC", :de, "1234.56"},
            {"₿.5", :de, "0.5"}
          ] do
        assert {"BTC", ^value} = amount(string, locale: locale, caller_currency: token),
               "#{locale} #{inspect(string)}"
      end

      for string <- ["₿1.234", "1,234 BTC"] do
        assert %Localize.InvalidAmountError{cause: %Localize.ParseError{detail: detail}} =
                 amount(string, locale: :de, caller_currency: token)

        assert detail =~ "ambiguous"
      end
    end

    # A digital token's identifier has digits in it, so it is read as a
    # word: first or last, and separated from the number by a space.
    test "a caller's currency text with digits in it" do
      token = fn text ->
        if text in ["Q9PB7XDNF", "4H95J0R2X", "USD1"] do
          {:ok, text}
        else
          :error
        end
      end

      for {string, locale, currency, value} <- [
            {"Q9PB7XDNF 5", :en, "Q9PB7XDNF", "5"},
            {"5 Q9PB7XDNF", :en, "Q9PB7XDNF", "5"},
            {"4H95J0R2X 1,234.5", :en, "4H95J0R2X", "1234.5"},
            {"4H95J0R2X 1,5", :de, "4H95J0R2X", "1.5"},
            {"5 Q9PB7XDNF", :fr, "Q9PB7XDNF", "5"},
            {"Q9PB7XDNF 5", :en, "Q9PB7XDNF", "5"},
            {"(Q9PB7XDNF 5)", :en, "Q9PB7XDNF", "-5"},
            {"-Q9PB7XDNF 5", :en, "Q9PB7XDNF", "-5"},
            {"Q9PB7XDNF -5", :en, "Q9PB7XDNF", "-5"},
            {"USD1 234", :en, "USD1", "234"}
          ] do
        assert {^currency, ^value} = amount(string, locale: locale, caller_currency: token),
               "#{locale} #{inspect(string)}"
      end

      # Without a space the identifier's digits run on into the number's.
      for string <- ["Q9PB7XDNF5", "5Q9PB7XDNF", "Q9PB7XDNF 5 4H95J0R2X"] do
        assert %Localize.ParseError{reason: :unexpected_input} =
                 amount(string, caller_currency: token)
      end

      assert %Localize.InvalidAmountError{currency: "Q9PB7XDNF", amount: ""} =
               amount("Q9PB7XDNF", caller_currency: token)

      # `fr` "USD1 234" is also 1 234 US dollars, so it is neither.
      assert {:USD, "1234"} = amount("USD1 234", locale: :fr)

      assert %Localize.ParseError{detail: detail} =
               amount("USD1 234", locale: :fr, caller_currency: token)

      assert detail =~ "two currencies"

      # Two names of one currency make two amounts of it.
      terra = fn text ->
        if text in ["LUNA", "LUNA2"] do
          {:ok, "NGXHD2ZFQ"}
        else
          :error
        end
      end

      assert %Localize.ParseError{detail: "it is two amounts of \"NGXHD2ZFQ\""} =
               amount("LUNA2 234", locale: :fr, caller_currency: terra)

      assert {"NGXHD2ZFQ", "234"} = amount("LUNA2 234", caller_currency: terra)

      # Only a caller reads such a word.
      assert %Localize.ParseError{reason: :unexpected_input} = amount("Q9PB7XDNF 5")
    end
  end

  describe "what Localize formats" do
    test "a currency's own separators" do
      assert {:CHF, "1234.56"} = amount("1’234.56 CHF", locale: :"fr-CH")
      assert {:CHF, "1234.56"} = amount("1'234.56 CHF", locale: :"fr-CH")
      assert {:EUR, "1234.56"} = amount("€ 1.234,56", locale: :"de-AT")
    end

    test "signs and bidi controls" do
      assert {:CHF, "-1234.56"} = amount("-CHF 1,234.56")
      assert {:USD, "-127.54"} = amount("-$127.54")
      assert {:SEK, "-1234.56"} = amount("−1 234,56 kr", locale: :sv)
      assert {:EGP, "-1234.56"} = amount("(؜1,234.56 ج.م.‏)", locale: :ar)

      assert {:EGP, "-1234.56"} =
               amount("؜-‏١٬٢٣٤٫٥٦ ج.م.‏", locale: :"ar-EG")
    end

    test "round trips" do
      for locale <- [:en, :de, :fr, :"de-CH", :"fr-CH", :sv, :da, :nl, :ar, :"ar-EG", :hi],
          amount <- ["1234.56", "-1234.56"],
          format <- [:currency, :accounting] do
        {:ok, currency} = Localize.Currency.currency_from_locale(locale)
        decimal = Decimal.new(amount)

        {:ok, string} =
          Localize.Number.to_string(decimal, locale: locale, currency: currency, format: format)

        assert {:ok, {^currency, parsed}} = Parser.parse_currency_amount(string, locale: locale)
        assert Decimal.equal?(parsed, decimal), "#{locale} #{format} #{inspect(string)}"
      end
    end

    test "a decimal mark that opens or closes the number" do
      assert {:USD, "0.5"} = amount(".5 USD")
      assert {:USD, "0.5"} = amount("USD .5")
      assert {:USD, "-0.5"} = amount(".5- USD")
      assert {:USD, "-0.5"} = amount("($.5)")
      assert {:USD, "5"} = amount("5. USD")
      assert {:USD, "5"} = amount("5.USD")
      assert {:USD, "5"} = amount("USD 5.")
      assert {:EUR, "0.5"} = amount("€ ,5", locale: :de)
    end

    # CLDR writes a narrow symbol where the context makes the currency clear,
    # so an amount reads a letter abbreviation only for the locale's own
    # currency: in Swiss text "15 Rp." is 15 Rappen, though `de-CH` gives the
    # rupiah the narrow "Rp".
    test "a narrow letter abbreviation is read only for the locale's own currency" do
      for {string, locale} <- [
            {"15 Rp.", :"de-CH"},
            {"Rp 15", :"de-CH"},
            {"K5", :en},
            {"Kč 100", :en}
          ] do
        assert %Localize.UnknownCurrencyError{} = amount(string, locale: locale),
               "#{locale} #{inspect(string)}"
      end

      assert {:IDR, "15000"} = amount("Rp 15.000", locale: :id)
      assert {:CZK, "100"} = amount("100 Kč", locale: :cs)
      assert {:CHF, "5"} = amount("Fr. 5.-", locale: :"de-CH")
      assert {:GBP, "5"} = amount("£5", locale: :en)
      assert {:EUR, "5"} = amount("€5", locale: :en)
      assert [:IDR] = Parser.resolve_currency("Rp", locale: :"de-CH")
    end

    # A currency sign means a currency and nothing else, so it is read outside
    # the currency's own locales when it names that currency alone, in the
    # locale and in CLDR's root data: `en-AU` writes the euro "EUR" and its
    # narrow symbol "€", which Localize formats with `currency_symbol: :narrow`.
    test "a currency sign naming one currency is read in any locale" do
      assert {:EUR, "1.00"} = amount("€1.00", locale: :"en-AU")
      assert {:EUR, "1.00"} = amount("€1.00", locale: :"es-MX")
      assert {:INR, "100"} = amount("₹100", locale: :"en-AU")
      assert {:MNT, "5"} = amount("₮5", locale: :en)
      assert {:EUR, "15.40"} = amount("€ 15.40", locale: :"de-CH")
      assert {:EUR, "15.40"} = amount("15.40 €", locale: :"de-CH")
    end

    # `bg` writes the South Korean won "KRW" and the yuan "CNY", so its data
    # leaves "₩" to the North Korean won and "¥" to the yen; root gives each
    # sign to two currencies, so neither is read. `en-AU` gives "₱" to the
    # Philippine and the Cuban peso and "£" to the pound and five others.
    test "a currency sign that several currencies share is refused" do
      for {string, locale} <- [
            {"₩100", :bg},
            {"¥100", :bg},
            {"¥100", :"en-AU"},
            {"₱100", :"en-AU"},
            {"£5", :"en-AU"},
            {"¤5", :"de-CH"}
          ] do
        assert %Localize.UnknownCurrencyError{} = amount(string, locale: locale),
               "#{locale} #{inspect(string)}"
      end
    end

    test "a currency sign is read only among the currencies a filter leaves" do
      assert %Localize.UnknownCurrencyError{} = amount("€1.00", locale: :"de-CH", only: [:CHF])
      assert %Localize.UnknownCurrencyError{} = amount("€1.00", locale: :"en-AU", only: [:AUD])
      assert %Localize.UnknownCurrencyError{} = amount("€1.00", locale: :"de-CH", except: [:EUR])
      assert {:EUR, "1.00"} = amount("€1.00", locale: :"de-CH", only: [:EUR])
    end

    # TR35's loose matching normalizes to NFKC. Currency text is matched so,
    # the text and the locale's strings alike; the number is not, where NFKC
    # would make the footnote of "$5²" a digit.
    test "currency text is matched after NFKC normalization, the number is not" do
      assert {:JPY, "1.00"} = amount("¥1.00", locale: :ja)
      assert {:JPY, "1.00"} = amount("￥1.00", locale: :ja)
      assert {:USD, "1.00"} = amount("＄1.00", locale: :en)
      assert {:KRW, "5"} = amount("￦5", locale: :"zh-Hant")
      assert {:AED, "5"} = amount("5 ﺩ.ﺇ", locale: :ar)
      assert {:JPY, "1"} = amount("¥1", locale: :ja, only: [:JPY])

      assert %Localize.ParseError{} = amount("$5²")

      # "①" and "½" are not decimal digits, so the text has no number and
      # is read whole as currency text.
      for string <- ["$①", "$½"] do
        assert %Localize.UnknownCurrencyError{} = amount(string), inspect(string)
      end
    end

    # An amount in the wrong currency is wrong money, so a symbol that names
    # several of the locale's currencies is refused rather than taken as the
    # nearest locale's: `resolve_currency/2` reads "$" in `fr` as the
    # Canadian dollar, as in `fr-CA`.
    test "a symbol several of the locale's currencies share is refused" do
      for {string, locale} <- [
            {"$2.00", :fr},
            {"$2,00", :"pt-PT"},
            {"$2.00", :es},
            {"$2.00", :"en-GB"}
          ] do
        assert %Localize.UnknownCurrencyError{currency: "$"} = amount(string, locale: locale),
               "#{locale} #{inspect(string)}"
      end

      assert {:USD, "2.00"} = amount("2,00 $US", locale: :fr)
      assert {:CAD, "2.00"} = amount("2,00 $CA", locale: :fr)
      assert {:CAD, "2.00"} = amount("$2.00", locale: :"fr-CA")
      assert {:USD, "2.00"} = amount("$2.00", locale: :en)
      assert [:CAD] = Parser.resolve_currency("$", locale: :fr)
    end

    # Swiss "Fr. –.15" and Dutch "€ -,50" write a dash for the zero before the
    # decimal mark, where a minus would stand, so the amount could be either.
    test "a minus before a decimal mark with no digit ahead of it is refused" do
      for {string, locale} <- [
            {"Fr. –.15", :"fr-CH"},
            {"Fr. -.15", :"fr-CH"},
            {"Fr. -.15", :"de-CH"},
            {"Fr. -.15", :"it-CH"},
            {"€ -,50", :nl},
            {"-$.50", :en},
            {"$-.50", :en},
            {"-.50 USD", :en},
            {"USD −.50", :en}
          ] do
        assert %Localize.InvalidAmountError{} = amount(string, locale: locale),
               "#{locale} #{inspect(string)}"
      end
    end

    test "a grouping separator that opens or closes the number is refused" do
      assert %Localize.InvalidAmountError{amount: ".5"} = amount("€ .5", locale: :de)
      assert %Localize.InvalidAmountError{amount: "5."} = amount("5. €", locale: :de)
      assert %Localize.InvalidAmountError{amount: ",5"} = amount(",5 USD")
    end

    # A mark between the currency and the digits is the currency's when CLDR
    # writes the currency with it, the number's when it is the decimal mark,
    # and refused otherwise. Before this "$.50" read as fifty dollars.
    test "a mark CLDR writes with the currency stays with it" do
      assert {:CHF, "5"} = amount("Fr.5", locale: :"de-CH")
      assert {:DKK, "5"} = amount("kr.5", locale: :da)
    end

    test "a decimal mark touching the currency belongs to the number" do
      assert {:USD, "0.50"} = amount("$.50")
      assert {:USD, "0.50"} = amount("USD.50")
      assert {:USD, "-0.50"} = amount("($.50)")
      assert {:EUR, "0.5"} = amount("€,5", locale: :de)
      assert {:BRL, "0.5"} = amount("R$,5", locale: :"pt-BR")
    end

    test "any other mark touching the currency is ambiguous and refused" do
      for {string, locale} <- [{"kr.5", :nb}, {"€.5", :de}, {"R$.5", :"pt-BR"}] do
        assert %Localize.ParseError{reason: :unexpected_input} = amount(string, locale: locale),
               "#{locale} #{inspect(string)}"
      end
    end

    test "a zero fraction written as a dash" do
      for locale <- [:"de-CH", :"fr-CH", :"it-CH"],
          {string, expected} <- [
            {"CHF 5.-", "5"},
            {"CHF 5.–", "5"},
            {"5.– CHF", "5"},
            {"Fr. 5.-", "5"},
            {"Fr. 5.--", "5"},
            {"CHF 1'234.–", "1234"},
            {"CHF -5.-", "-5"},
            {"(CHF 5.-)", "-5"}
          ] do
        assert {:CHF, ^expected} = amount(string, locale: locale), "#{locale} #{inspect(string)}"
      end

      assert {:CHF, "5"} = amount("Fr. 5.—", locale: :"de-CH")
      assert {:EUR, "5"} = amount("€ 5,-", locale: :nl)
      assert {:EUR, "-5"} = amount("-€ 5,-", locale: :nl)
      assert {:EUR, "-127.54"} = amount("€ 127,54-", locale: :nl)
    end

    # An amount that could be two amounts is refused, never guessed.
    test "a group the locale does not write is refused" do
      assert %Localize.InvalidAmountError{amount: "1.23"} = amount("1.23 EUR", locale: :de)
      assert %Localize.InvalidAmountError{amount: "1,23"} = amount("1,23 USD")
      assert {:INR, "1234567"} = amount("1,234,567 INR", locale: :"en-IN")
      assert {:INR, "1234567"} = amount("₹12,34,567", locale: :"en-IN")
    end

    test "de-AT and fr-CH amounts read with either set of separators" do
      assert {:EUR, "1234.56"} = amount("€ 1.234,56", locale: :"de-AT")
      assert {:EUR, "1234.56"} = amount("1\u00A0234,56 EUR", locale: :"de-AT")
      assert {:CHF, "1234.56"} = amount("1'234,56 CHF", locale: :"fr-CH")
      assert {:CHF, "1234.56"} = amount("1'234.56 CHF", locale: :"fr-CH")
      assert {:CHF, "100.00"} = amount("100,00 CHF", locale: :"fr-CH")
      assert {:CHF, "0.5"} = amount("CHF,5", locale: :"fr-CH")
    end

    # Both of `de-AT`'s sets mark the fraction with a comma, and the euro's
    # groups with a period, so a period is never its decimal point.
    test "a period is de-AT's currency group, never its decimal point" do
      assert {:EUR, "1234"} = amount("1.234 EUR", locale: :"de-AT")

      for string <- ["100.00 EUR", "1.23 EUR", "1.2345 EUR"] do
        assert %Localize.InvalidAmountError{} = amount(string, locale: :"de-AT"), string
      end
    end

    test "a period that is neither of the locale's separators" do
      assert {:EUR, "100.00"} = amount("100.00 €", locale: :fr)
      assert {:EUR, "1.5"} = amount("€ 1.5", locale: :fr)
      assert {:SEK, "-0.50"} = amount("-0.50 kr", locale: :sv)

      for {string, locale} <- [
            {"1.234 €", :fr},
            {"1.234 kr", :sv},
            {"1.234 zł", :pl},
            {"€ 1.000.000", :fr}
          ] do
        assert %Localize.InvalidAmountError{} = amount(string, locale: locale),
               "#{locale} #{inspect(string)}"
      end
    end

    # `resolve_currency/2` breaks a tie by the order of the names; an amount
    # in a currency picked that way would be a guess.
    test "a fuzzy match is refused where two currencies are equally close" do
      for {string, locale} <- [{"100 dollars", :fr}, {"kr 100", :en}, {"100 USDD", :en}] do
        assert %Localize.UnknownCurrencyError{} = amount(string, locale: locale, fuzzy: 0.8),
               "#{locale} #{inspect(string)}"
      end

      assert {:EUR, "100"} = amount("100 eurosports", fuzzy: 0.8)
      assert {:EUR, "100"} = amount("100 eruo", fuzzy: 0.8)
      assert {:CHF, "100"} = amount("100 Swiss francs", fuzzy: 0.8)
      assert [:RHD] = Parser.resolve_currency("dollars", locale: :fr, fuzzy: 0.8)
    end

    test "a sentence's closing period after the currency" do
      assert {:USD, "100"} = amount("100 USD.")
    end

    # German "1,599 €" is a fuel price, but a shop writing English separators
    # means 1599: three fraction digits are a thousands group as often as not
    # in a currency with fewer.
    test "three fraction digits after a single mark in a currency of fewer are refused" do
      for {string, locale} <- [
            {"73,460 €", :de},
            {"-1,599 €", :de},
            {"(1,599 €)", :de},
            {"$59.568", :en},
            {"USD (7.926)", :"en-GB"},
            {"880,000 ₫", :vi},
            {"3,990 Ft", :hu},
            {"R8,499", :"en-ZA"},
            {"￥1.000", :ja},
            {"1,234 €", :fr}
          ] do
        assert %Localize.InvalidAmountError{cause: %Localize.ParseError{}} =
                 amount(string, locale: locale),
               "#{locale} #{inspect(string)}"
      end

      assert {:EUR, "0.123"} = amount("0,123 €", locale: :de)
      assert {:EUR, "1234.567"} = amount("1.234,567 €", locale: :de)
      assert {:EUR, "1599"} = amount("1.599 €", locale: :de)
      assert {:EUR, "73.46"} = amount("73,46 €", locale: :de)
      assert {:USD, "12345.678"} = amount("$12,345.678", locale: :en)
      assert {:USD, "1599"} = amount("$1,599", locale: :en)
      assert {:KWD, "1.599"} = amount("KWD 1.599", locale: :en)
      assert {:CLF, "1.599"} = amount("CLF 1.599", locale: :en)
    end

    # Symbols are reused: Russian shops write the ruble "Р", which folds to
    # "р." of the ruble of 1991–1998.
    test "a historic currency is read by its code or name, not its symbol" do
      for {string, locale} <- [
            {"6 300 Р", :ru},
            {"336 р.", :ru},
            {"230 лв.", :bg},
            {"100 DM", :de},
            {"100 kn", :hr}
          ] do
        assert %Localize.UnknownCurrencyError{} = amount(string, locale: locale),
               "#{locale} #{inspect(string)}"
      end

      assert {:RUR, "100"} = amount("100 RUR", locale: :ru)
      assert {:BGN, "230"} = amount("230 BGN", locale: :bg)
      assert {:DEM, "100"} = amount("100 DEM", locale: :de)
      assert {:DEM, "100"} = amount("100 Deutsche Mark", locale: :de)
      assert {:RUB, "100"} = amount("100 ₽", locale: :ru)
    end
  end

  describe "errors" do
    test "no currency and no default" do
      assert %Localize.ParseError{reason: :missing_currency, input: "100"} = amount("100")
    end

    test "a currency whose number cannot be read" do
      assert %Localize.InvalidAmountError{
               currency: :USD,
               amount: "30\u00A0000,00",
               cause: %Localize.InvalidValueError{}
             } = amount("US$30\u00A0000,00", locale: :"en-ZA", separators: :us)

      assert Exception.message(
               Localize.InvalidAmountError.exception(currency: :USD, amount: "1,2,3")
             ) ==
               ~s(The amount "1,2,3" of currency :USD is not a number.)
    end

    test "text that is not one currency amount" do
      for string <- ["USD 100 with trailing text", "USD 100 EUR", "5 USD 6"] do
        assert %Localize.ParseError{reason: :unexpected_input} = amount(string),
               inspect(string)
      end
    end

    # A form's empty field is a missing amount, as ex_money has always
    # reported it, not text that is not money.
    test "text with no number" do
      for string <- ["", "   ", "\u00A0", "\u200E"] do
        assert %Localize.ParseError{reason: :missing_currency} = amount(string), inspect(string)
      end

      assert %Localize.InvalidAmountError{currency: :EUR, amount: ""} =
               amount("", default_currency: :EUR)

      assert %Localize.InvalidAmountError{currency: :USD, amount: ""} = amount("USD")
      assert %Localize.InvalidAmountError{currency: :USD, amount: ""} = amount(" $ ")

      for string <- ["-", "(USD)", "()", "USD-", "+"] do
        assert %Localize.ParseError{reason: :unexpected_input} = amount(string), inspect(string)
      end
    end

    # The number, signs and parentheses included, is read by `parse/2`.
    test "a currency whose signs or parentheses are malformed" do
      for string <- ["--5 USD", "-+5 USD", "(5 USD", "5 USD)", ")5 USD(", "((5 USD))"] do
        assert %Localize.InvalidAmountError{currency: :USD} = amount(string), inspect(string)
      end
    end

    test "invalid arguments and options" do
      assert {:error, _} = Parser.parse_currency_amount(nil)
      assert {:error, _} = Parser.parse_currency_amount(:"")
      assert {:error, _} = Parser.parse_currency_amount(100)
      assert {:error, _} = Parser.parse_currency_amount("USD 100", :not_a_list)
      assert {:error, _} = Parser.parse_currency_amount("USD 100", locale: "xx-invalid-!!")
      assert {:error, _} = Parser.parse_currency_amount("100 eurosports", fuzzy: 2.0)
      assert {:error, _} = Parser.parse_currency_amount("100", default_currency: 12)
      assert {:error, _} = Parser.parse_currency_amount("100 BTC", caller_currency: :nope)

      assert {:error, %Localize.InvalidValueError{value: :nope}} =
               Parser.parse_currency_amount("Q9PB7XDNF 5", caller_currency: :nope)
    end

    test "an over-long string" do
      string = "USD " <> String.duplicate("1", Parser.max_number_bytes())

      assert {:error, %Localize.ParseError{reason: :input_too_large}} =
               Parser.parse_currency_amount(string)
    end
  end
end
