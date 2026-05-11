defmodule Localize.LocaleTest do
  use ExUnit.Case, async: true

  doctest Localize.Locale

  describe "cldr_locale_id_from/1" do
    test "atom is validated and returned as ok-tuple" do
      assert Localize.Locale.cldr_locale_id_from(:en) == {:ok, :en}
      assert Localize.Locale.cldr_locale_id_from(:"en-AU") == {:ok, :"en-AU"}
    end

    test "binary is validated and returned as ok-tuple" do
      assert Localize.Locale.cldr_locale_id_from("en") == {:ok, :en}
      assert Localize.Locale.cldr_locale_id_from("en-AU") == {:ok, :"en-AU"}
    end

    test "LanguageTag with cldr_locale_id set uses that field" do
      {:ok, tag} = Localize.validate_locale("fr-CA")
      assert tag.cldr_locale_id == :"fr-CA"
      assert Localize.Locale.cldr_locale_id_from(tag) == {:ok, :"fr-CA"}
    end

    test "LanguageTag with nil cldr_locale_id resolves via validate_locale" do
      # A raw-parsed tag has cldr_locale_id = nil. cldr_locale_id_from must
      # resolve it to the canonical CLDR locale, NOT the full tag string
      # (which would include extensions, script, etc. and not match any
      # ETF file name).
      {:ok, raw} = Localize.LanguageTag.parse("en-Latn-AU-u-ca-gregory")
      assert raw.cldr_locale_id == nil
      assert Localize.Locale.cldr_locale_id_from(raw) == {:ok, :"en-AU"}
    end

    test "LanguageTag with script and territory resolves to cldr_locale_id" do
      {:ok, raw} = Localize.LanguageTag.parse("zh-Hans-CN")
      assert {:ok, locale_id} = Localize.Locale.cldr_locale_id_from(raw)
      # Must be the CLDR canonical form, not :"zh-Hans-CN"
      assert locale_id in [:"zh-Hans", :"zh-Hans-CN", :zh]
    end

    test "bare und tag with nil cldr_locale_id resolves to :und" do
      # Regression: `Localize.Locale.parent/1` returns `und` for bare
      # languages (e.g. `ja`, `de`). The returned tag has
      # `cldr_locale_id: nil`, so `cldr_locale_id_from/1` used to route through
      # `validate_locale/1` and likely-subtag resolution. Maximizing
      # `und` produces a concrete locale (`:en`, `:aa`, or in some
      # environments the originally-requested locale depending on the
      # likely-subtag table), which fed back into the provider's
      # parent-chain walker and produced infinite recursion. A bare und
      # tag must map directly to `:und` without likely-subtag
      # resolution — independent of any `-u-` extensions.
      {:ok, parent_tag} = Localize.Locale.parent("ja")
      assert Localize.Locale.cldr_locale_id_from(parent_tag) == {:ok, :und}

      {:ok, parent_tag} = Localize.Locale.parent("de")
      assert Localize.Locale.cldr_locale_id_from(parent_tag) == {:ok, :und}
    end

    test "unparseable locale string returns error" do
      # A string that fails BCP-47 grammar (digit-only subtag in
      # language position) cannot be validated.
      assert {:error, _} = Localize.Locale.cldr_locale_id_from("123-456")
    end

    test "garbage input returns InvalidLocaleError" do
      assert {:error, %Localize.InvalidLocaleError{}} =
               Localize.Locale.cldr_locale_id_from([1, 2, 3])

      assert {:error, %Localize.InvalidLocaleError{}} =
               Localize.Locale.cldr_locale_id_from(%{a: 1})
    end
  end

  describe "locale loading resolves non-canonical locale IDs" do
    test "pt-BR resolves to :pt for loading" do
      # pt-BR is a valid BCP 47 tag but not a canonical CLDR locale;
      # CLDR maps it to :pt. The provider must resolve before
      # attempting cache lookup or download so it doesn't produce
      # 404s for pt-BR.etf.
      assert {:ok, _data} = Localize.Locale.Provider.PersistentTerm.load(:"pt-BR")
    end

    test "en-US resolves to :en for loading" do
      assert {:ok, _data} = Localize.Locale.Provider.PersistentTerm.load(:"en-US")
    end
  end
end
