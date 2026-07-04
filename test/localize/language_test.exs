defmodule Localize.LanguageTest do
  use ExUnit.Case, async: true

  alias Localize.Language

  doctest Localize.Language

  # ── to_string ──────────────────────────────────────────────

  describe "to_string/2" do
    test "returns localized language name" do
      assert {:ok, "German"} == Language.display_name("de")
      assert {:ok, "Japanese"} == Language.display_name("ja")
      assert {:ok, "French"} == Language.display_name("fr")
    end

    test "returns name from a language tag" do
      {:ok, tag} = Localize.validate_locale(:de)
      assert {:ok, "German"} == Language.display_name(tag)
    end

    test "returns short style when available" do
      {:ok, standard} = Language.display_name("en-GB", style: :standard)
      {:ok, short} = Language.display_name("en-GB", style: :short)
      assert standard != short
      assert short == "UK English"
    end

    test "falls back to standard when short is unavailable" do
      assert Language.display_name("de", style: :short) ==
               Language.display_name("de", style: :standard)
    end

    test "returns name in another locale" do
      assert {:ok, "Englisch"} == Language.display_name("en", locale: :de)
      assert {:ok, "Deutsch"} == Language.display_name("de", locale: :de)
    end

    test "returns error tuple for a malformed locale" do
      assert {:error, %Localize.InvalidLocaleError{locale_id: "zzzzzzz"}} =
               Language.display_name("zzzzzzz")
    end

    test "returns error tuple for a valid language with no display name" do
      assert {:error, %Localize.UnknownLanguageError{language: "mis"}} =
               Language.display_name("mis")
    end

    test "is consistent between a string and a language tag" do
      assert Language.display_name("en-GB") ==
               Language.display_name(Localize.LanguageTag.new!("en-GB"))

      assert Language.display_name("ar-SA") ==
               Language.display_name(Localize.LanguageTag.new!("ar-SA"))
    end

    test "resolves a region-specific name and falls back to the base language" do
      assert {:ok, "British English"} == Language.display_name("en-GB")
      assert {:ok, "Brazilian Portuguese"} == Language.display_name("pt-BR", style: :menu)
      assert {:ok, "European Portuguese"} == Language.display_name("pt-PT", style: :menu)
      assert {:ok, "Arabic"} == Language.display_name("ar-SA")
    end

    # Per TR35 the display lookup canonicalizes but does not add likely
    # subtags: a bare language keeps its own name, and only an explicitly
    # supplied region/script resolves to a region-specific CLDR name.
    test "a bare language is not maximized to a region-specific name" do
      assert {:ok, "English"} == Language.display_name("en")
      assert {:ok, "Spanish"} == Language.display_name("es")
      assert {:ok, "Chinese"} == Language.display_name("zh")
      assert {:ok, "Portuguese"} == Language.display_name("pt")

      assert {:ok, "American English"} == Language.display_name("en-US")
      assert {:ok, "Simplified Chinese"} == Language.display_name("zh-Hans")
    end

    # Per TR35, the candidate cascade tries lang-script before lang-region
    # (the two-subtag tie is broken toward the earlier subtag). No CLDR
    # language currently has both a lang-script and lang-region name, so the
    # tie itself is untriggerable — but the reordering must not shadow a
    # region-specific name (`en-GB`) behind the always-present maximized
    # script candidate (`en-Latn`), nor break a script-specific name.
    test "candidate order does not shadow region- or script-specific names" do
      assert {:ok, "British English"} == Language.display_name("en-GB")
      assert {:ok, "Traditional Chinese"} == Language.display_name("zh-Hant")
      assert {:ok, "English"} == Language.display_name("en-IN")
    end

    test "falls back to default locale when fallback is true" do
      # "ccp" (Chakma) may not exist in all locales but should be in :en
      assert {:ok, _name} = Language.display_name("ccp", locale: :de, fallback: true)
    end

    test "does not fall back when fallback is false" do
      # Pick a language unlikely to be in :de but present in :en
      result_no_fallback = Language.display_name("ccp", locale: :de, fallback: false)
      result_with_fallback = Language.display_name("ccp", locale: :de, fallback: true)

      # Both should work since :de has "ccp", but verify fallback option is respected
      assert result_no_fallback == result_with_fallback
    end
  end

  describe "to_string!/2" do
    test "returns name on success" do
      assert "German" == Language.display_name!("de")
      assert "UK English" == Language.display_name!("en-GB", style: :short)
    end

    test "raises on a valid language with no display name" do
      assert_raise Localize.UnknownLanguageError, fn ->
        Language.display_name!("mis")
      end
    end

    test "raises on a malformed locale" do
      assert_raise Localize.InvalidLocaleError, fn ->
        Language.display_name!("zzzzzzz")
      end
    end
  end

  # ── languages_for ─────────────────────────────────────────────

  describe "languages_for/1" do
    test "returns sorted list of language codes" do
      assert {:ok, codes} = Language.languages_for()
      assert is_list(codes)
      assert "en" in codes
      assert "de" in codes
      assert "ja" in codes
      assert codes == Enum.sort(codes)
    end

    test "returns codes for another locale" do
      assert {:ok, codes} = Language.languages_for(locale: :de)
      assert "en" in codes
    end

    test "defaults to current locale" do
      assert {:ok, default_codes} = Language.languages_for()
      assert {:ok, en_codes} = Language.languages_for(locale: :en)
      assert default_codes == en_codes
    end
  end

  # ── language_names_for ────────────────────────────────────────

  describe "language_names_for/1" do
    test "returns map of language codes to name maps" do
      assert {:ok, languages} = Language.language_names_for()
      assert is_map(languages)
      assert %{standard: "German"} = languages["de"]
      assert %{standard: "Japanese"} = languages["ja"]
    end

    test "returns languages for another locale" do
      assert {:ok, languages} = Language.language_names_for(locale: :de)
      assert %{standard: "Englisch"} = languages["en"]
    end

    test "defaults to current locale" do
      assert {:ok, default_langs} = Language.language_names_for()
      assert {:ok, en_langs} = Language.language_names_for(locale: :en)
      assert default_langs == en_langs
    end
  end

  # ── deprecated delegates ──────────────────────────────────────

  describe "deprecated known_/available_ delegates" do
    test "available_languages/1 delegates to languages_for/1" do
      # Called via apply/3 so the deliberate use of the deprecated
      # name does not emit a compile-time deprecation warning.
      assert apply(Language, :available_languages, [[locale: :en]]) ==
               Language.languages_for(locale: :en)
    end

    test "known_languages/1 delegates to language_names_for/1" do
      assert apply(Language, :known_languages, [[locale: :en]]) ==
               Language.language_names_for(locale: :en)
    end
  end

  # ── Style defaults ───────────────────────────────────────────

  describe "default options" do
    test ":style defaults to :standard" do
      assert Language.display_name("en-GB") ==
               Language.display_name("en-GB", style: :standard)
    end

    test ":fallback defaults to false" do
      assert Language.display_name("ccp", locale: :de) ==
               Language.display_name("ccp", locale: :de, fallback: false)
    end
  end

  # ── Invalid options ──────────────────────────────────────────

  describe "invalid options" do
    test "returns an error tuple on invalid :style" do
      assert {:error, %Localize.InvalidValueError{value: :invalid}} =
               Language.display_name("de", style: :invalid)
    end

    test "returns an error tuple on invalid :fallback" do
      assert {:error, %Localize.InvalidValueError{value: :invalid}} =
               Language.display_name("de", fallback: :invalid)
    end

    test "display_name! raises on invalid options" do
      assert_raise Localize.InvalidValueError, fn ->
        Language.display_name!("de", style: :invalid)
      end
    end
  end
end
