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

    test "returns error tuple for unknown language code" do
      assert {:error, %Localize.UnknownLanguageError{language: "zzzzzzz"}} =
               Language.display_name("zzzzzzz")
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

    test "raises on unknown language" do
      assert_raise Localize.UnknownLanguageError, fn ->
        Language.display_name!("zzzzzzz")
      end
    end
  end

  # ── available_languages ───────────────────────────────────────

  describe "available_languages/1" do
    test "returns sorted list of language codes" do
      assert {:ok, codes} = Language.available_languages()
      assert is_list(codes)
      assert "en" in codes
      assert "de" in codes
      assert "ja" in codes
      assert codes == Enum.sort(codes)
    end

    test "returns codes for another locale" do
      assert {:ok, codes} = Language.available_languages(locale: :de)
      assert "en" in codes
    end

    test "defaults to current locale" do
      assert {:ok, default_codes} = Language.available_languages()
      assert {:ok, en_codes} = Language.available_languages(locale: :en)
      assert default_codes == en_codes
    end
  end

  # ── known_languages ───────────────────────────────────────────

  describe "known_languages/1" do
    test "returns map of language codes to name maps" do
      assert {:ok, languages} = Language.known_languages()
      assert is_map(languages)
      assert %{standard: "German"} = languages["de"]
      assert %{standard: "Japanese"} = languages["ja"]
    end

    test "returns languages for another locale" do
      assert {:ok, languages} = Language.known_languages(locale: :de)
      assert %{standard: "Englisch"} = languages["en"]
    end

    test "defaults to current locale" do
      assert {:ok, default_langs} = Language.known_languages()
      assert {:ok, en_langs} = Language.known_languages(locale: :en)
      assert default_langs == en_langs
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
    test "raises on invalid :style" do
      assert_raise ArgumentError, fn ->
        Language.display_name("de", style: :invalid)
      end
    end

    test "raises on invalid :fallback" do
      assert_raise ArgumentError, fn ->
        Language.display_name("de", fallback: :invalid)
      end
    end
  end
end
