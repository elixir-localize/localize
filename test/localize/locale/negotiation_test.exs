defmodule Localize.Locale.NegotiationTest do
  # Changes the supported locales for the whole node, so it runs alone.
  use ExUnit.Case, async: false

  alias Localize.LanguageTag

  # Negotiation follows ICU's `LocaleMatcher`: a supported locale below
  # CLDR's default script distance is a match, and when none is, the first
  # supported locale is taken, as ICU takes its default locale.
  describe "LanguageTag.best_match/3 with the default distance" do
    test "matches a regional variant and the pairs CLDR marks as close" do
      assert {:ok, :"en-GB", _distance} = LanguageTag.best_match(:"en-AU", [:en, :"en-GB", :fr])
      assert {:ok, :ja, 5} = LanguageTag.best_match("ja-Latn", [:en, :ja])
      assert {:ok, :sr, 5} = LanguageTag.best_match("sr-Latn", [:en, :sr])
    end

    test "takes the first supported locale for another script or language, as no match" do
      assert LanguageTag.best_match("ru-Latn", [:en, :ru]) == {:ok, :en, 80}
      assert LanguageTag.best_match("szl-DE", [:fr, :en, :de]) == {:ok, :fr, 80}
      assert LanguageTag.best_match("zh-Hant", [:fr, :"zh-Hans-CN"]) == {:ok, :fr, 80}
    end
  end

  describe "LanguageTag.best_match/3 with a distance given" do
    test "is strict, with no fallback" do
      assert {:error, %Localize.LocaleMatchError{}} = LanguageTag.best_match("ja", [:en, :fr], 49)
      assert {:error, %Localize.LocaleMatchError{}} = LanguageTag.best_match("ja", [:en, :fr], 80)
    end

    test "accepts what is within it" do
      assert {:ok, :ru, 50} = LanguageTag.best_match("ru-Latn", [:en, :ru], 79)
    end

    test "is an error when it is not a non-negative integer" do
      for distance <- [-1, 1.5, "49", nil] do
        assert {:error, %Localize.InvalidValueError{}} =
                 LanguageTag.best_match("en", [:en], distance),
               inspect(distance)
      end
    end
  end

  describe "Localize.validate_locale/1 with supported locales configured" do
    setup do
      original_supported = Localize.supported_locales()
      on_exit(fn -> Localize.put_supported_locales(original_supported) end)
    end

    test "takes the first supported locale where none matches" do
      :ok = Localize.put_supported_locales([:fr, :en, :ru, :sr])

      # Matching accepted another language here, the territory's own.
      assert {:ok, %LanguageTag{cldr_locale_id: :fr}} = Localize.validate_locale("szl-DE")
      assert {:ok, %LanguageTag{cldr_locale_id: :fr}} = Localize.validate_locale("ja")
    end

    test "takes a supported locale within the distance" do
      :ok = Localize.put_supported_locales([:fr, :en, :ru, :sr])

      assert {:ok, %LanguageTag{cldr_locale_id: :sr}} = Localize.validate_locale("sr-Latn")
      assert {:ok, %LanguageTag{cldr_locale_id: :en}} = Localize.validate_locale("en-AU")

      # CLDR marks Cyrillic Uzbek as close to Russian (34), as ICU matches it.
      assert {:ok, %LanguageTag{cldr_locale_id: :ru}} = Localize.validate_locale("uz-Cyrl")
    end

    test "gives the root for a locale CLDR has no data for, as the root is always supported" do
      :ok = Localize.put_supported_locales([:fr, :en, :ru])

      assert {:ok, %LanguageTag{cldr_locale_id: :und}} = Localize.validate_locale("ru-Latn")
      assert {:ok, %LanguageTag{cldr_locale_id: :und}} = Localize.validate_locale("tlh")
    end
  end
end
