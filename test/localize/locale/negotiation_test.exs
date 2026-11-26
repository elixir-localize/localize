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

    # The tests run with the default locale `en`.
    test "takes the default locale where none matches" do
      :ok = Localize.put_supported_locales([:fr, :en, :ru, :sr])

      # Matching accepted another language here, the territory's own.
      assert {:ok, %LanguageTag{cldr_locale_id: :en}} = Localize.validate_locale("szl-DE")
      assert {:ok, %LanguageTag{cldr_locale_id: :en}} = Localize.validate_locale("ja")
    end

    test "takes the first supported locale where the default locale is not supported" do
      :ok = Localize.put_supported_locales([:fr, :de])

      assert {:ok, %LanguageTag{cldr_locale_id: :fr}} = Localize.validate_locale("ja")
    end

    test "follows a change of default locale, although validations are cached" do
      original_default = Localize.default_locale()
      on_exit(fn -> Localize.put_default_locale(original_default) end)
      :ok = Localize.put_supported_locales([:fr, :en, :ru])

      assert {:ok, %LanguageTag{cldr_locale_id: :en}} = Localize.validate_locale("ja")
      {:ok, _ru} = Localize.put_default_locale(:ru)
      assert {:ok, %LanguageTag{cldr_locale_id: :ru}} = Localize.validate_locale("ja")
    end

    test "negotiates nothing when every CLDR locale is supported" do
      :ok = Localize.put_supported_locales(Localize.SupplementalData.all_locale_ids())

      assert {:ok, %LanguageTag{cldr_locale_id: :und}} = Localize.validate_locale("tlh")
      assert {:ok, %LanguageTag{cldr_locale_id: :pt}} = Localize.validate_locale("pt-BE")
    end

    test "takes a supported locale within the distance" do
      :ok = Localize.put_supported_locales([:fr, :en, :ru, :sr])

      assert {:ok, %LanguageTag{cldr_locale_id: :sr}} = Localize.validate_locale("sr-Latn")
      assert {:ok, %LanguageTag{cldr_locale_id: :en}} = Localize.validate_locale("en-AU")

      # CLDR marks Cyrillic Uzbek as close to Russian (34), as ICU matches it.
      assert {:ok, %LanguageTag{cldr_locale_id: :ru}} = Localize.validate_locale("uz-Cyrl")
    end

    test "takes the default locale for a locale CLDR has no data for, and the root only when asked for" do
      :ok = Localize.put_supported_locales([:fr, :en, :ru])

      assert {:ok, %LanguageTag{cldr_locale_id: :en}} = Localize.validate_locale("ru-Latn")
      assert {:ok, %LanguageTag{cldr_locale_id: :en}} = Localize.validate_locale("tlh")
      assert {:ok, %LanguageTag{cldr_locale_id: :und}} = Localize.validate_locale("und")

      # Extensions choose preferences, not the locale.
      assert {:ok, %LanguageTag{cldr_locale_id: :und}} = Localize.validate_locale("und-u-nu-latn")

      assert {:ok, %LanguageTag{cldr_locale_id: :und}} =
               Localize.validate_locale("UND-u-ca-gregory")
    end

    # The request is negotiated, not the locale it inherits from: `pt-BE`
    # inherits from `pt`, but CLDR rates it nearer `pt-PT`.
    test "negotiates the request, not the locale it inherits from" do
      :ok = Localize.put_supported_locales([:en, :"en-GB", :pt, :"pt-PT"])

      assert {:ok, %LanguageTag{cldr_locale_id: :"pt-PT"}} = Localize.validate_locale("pt-BE")
      assert {:ok, %LanguageTag{cldr_locale_id: :"en-GB"}} = Localize.validate_locale("en-SY")
      assert {:ok, %LanguageTag{cldr_locale_id: :pt}} = Localize.validate_locale("pt-BR")
    end
  end

  describe "LanguageTag.best_match/3 among locales as near" do
    test "takes CLDR's paradigm locales when given as atoms" do
      assert {:ok, :"pt-PT", 4} = LanguageTag.best_match("pt-BE", [:pt, :"pt-PT"])
      assert {:ok, :"en-GB", 3} = LanguageTag.best_match("en-SY", [:en, :"en-GB"])
    end

    # A macro-region stands for each kind of region it holds, at the largest
    # of their distances, so `en-001` is as far from `en-GB` as from `en`,
    # and ICU takes the more likely, whatever the order.
    test "takes the more likely locale for a macro-region, whatever the order" do
      for supported <- [[:en, :"en-GB"], [:"en-GB", :en]] do
        assert {:ok, :en, 5} = LanguageTag.best_match("en-001", supported)
        assert {:ok, :en, 5} = LanguageTag.best_match("en-419", supported)
      end

      assert {:ok, :pt, 5} = LanguageTag.best_match("pt-001", [:"pt-PT", :pt])
      assert {:ok, :"en-GB", 3} = LanguageTag.best_match("en-150", [:en, :"en-GB"])
    end
  end
end
