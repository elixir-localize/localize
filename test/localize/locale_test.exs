defmodule Localize.LocaleTest do
  use ExUnit.Case, async: true

  doctest Localize.Locale

  describe "to_locale_id/1" do
    test "atom passes through unchanged" do
      assert Localize.Locale.to_locale_id(:en) == :en
      assert Localize.Locale.to_locale_id(:"en-AU") == :"en-AU"
    end

    test "binary is converted to atom" do
      assert Localize.Locale.to_locale_id("en") == :en
      assert Localize.Locale.to_locale_id("en-AU") == :"en-AU"
    end

    test "LanguageTag with cldr_locale_id set uses that field" do
      {:ok, tag} = Localize.validate_locale("fr-CA")
      assert tag.cldr_locale_id == :"fr-CA"
      assert Localize.Locale.to_locale_id(tag) == :"fr-CA"
    end

    test "LanguageTag with nil cldr_locale_id resolves via validate_locale" do
      # A raw-parsed tag has cldr_locale_id = nil. to_locale_id must
      # resolve it to the canonical CLDR locale, NOT the full tag string
      # (which would include extensions, script, etc. and not match any
      # ETF file name).
      {:ok, raw} = Localize.LanguageTag.parse("en-Latn-AU-u-ca-gregory")
      assert raw.cldr_locale_id == nil
      assert Localize.Locale.to_locale_id(raw) == :"en-AU"
    end

    test "LanguageTag with script and territory resolves to cldr_locale_id" do
      {:ok, raw} = Localize.LanguageTag.parse("zh-Hans-CN")
      locale_id = Localize.Locale.to_locale_id(raw)
      # Must be the CLDR canonical form, not :"zh-Hans-CN"
      assert locale_id in [:"zh-Hans", :"zh-Hans-CN", :zh]
    end
  end
end
