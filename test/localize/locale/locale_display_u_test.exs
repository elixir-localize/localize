defmodule Localize.Locale.LocaleDisplayUTest do
  use ExUnit.Case, async: true

  alias Localize.Locale.LocaleDisplay
  alias Localize.Locale.LocaleDisplay.U

  describe "display_name/2 -u- collation option keys" do
    test "renders numeric collation disabled" do
      assert {:ok, "English (Sort Digits Individually)"} =
               LocaleDisplay.display_name("en-u-kn-false")
    end

    test "renders lowercase-first and normal case ordering" do
      assert {:ok, "English (Sort Lowercase First)"} =
               LocaleDisplay.display_name("en-u-kf-lower")

      assert {:ok, "English (Sort Normal Case Order)"} =
               LocaleDisplay.display_name("en-u-kf-false")
    end

    test "renders backwards accent sorting" do
      assert {:ok, "English (Sort Accents Reversed)"} =
               LocaleDisplay.display_name("en-u-kb-true")
    end

    test "renders case level sorting" do
      assert {:ok, "English (Sort Case Sensitive)"} =
               LocaleDisplay.display_name("en-u-kc-true")
    end

    test "renders normalization for both kh and kk keys" do
      assert {:ok, "English (Sort Unicode Normalized)"} =
               LocaleDisplay.display_name("en-u-kh-true")

      assert {:ok, "English (Sort Unicode Normalized)"} =
               LocaleDisplay.display_name("en-u-kk-true")
    end

    test "renders alternate handling" do
      assert {:ok, "English (Sort Symbols)"} =
               LocaleDisplay.display_name("en-u-ka-noignore")
    end

    test "renders multi-script reordering joined with the list separator" do
      assert {:ok, "English (Script/Block Reordering: Latin, Cyrillic, Greek)"} =
               LocaleDisplay.display_name("en-u-kr-latn-cyrl-grek")
    end
  end

  # Step 3 of CLDR's non-location format algorithm uses the zone's exemplar
  # city. The zone data keys that `:exemplar_city`, but the lookup matched
  # `%{city: _}`, so it never fired and every zone fell through to a city name
  # derived from the IANA id instead — 48 zones in `en` and 190 in `ja`.
  describe "display_name/2 -u-tz- exemplar cities" do
    test "uses CLDR's exemplar city rather than one derived from the IANA id" do
      # CLDR renamed this city; the IANA id still says Godthab.
      assert {:ok, "English (Time Zone: Nuuk Time)"} =
               LocaleDisplay.display_name("en-u-tz-glgoh")

      assert {:ok, "Deutsch (Zeitzone: Nuuk [Ortszeit])"} =
               LocaleDisplay.display_name("de-u-tz-glgoh", locale: :de)
    end

    test "keeps the accents that deriving from the id would drop" do
      assert {:ok, "Deutsch (Zeitzone: Azoren [Ortszeit])"} =
               LocaleDisplay.display_name("de-u-tz-ptpdl", locale: :de)
    end

    test "descends into a three-part zone id, whose leaf CLDR keys by string" do
      # "America/Indiana/Knox" — splitting into two parts looked for a city
      # named "Indiana/Knox", so the qualifier CLDR adds was lost.
      assert {:ok, "English (Time Zone: Knox, Indiana Time)"} =
               LocaleDisplay.display_name("en-u-tz-usknx")

      assert {:ok, "Deutsch (Zeitzone: R\u00edo Gallegos [Ortszeit])"} =
               LocaleDisplay.display_name("de-u-tz-arrgl", locale: :de)
    end

    test "an unknown zone still falls back to a name derived from the id" do
      # A zone CLDR has no exemplar city for, and an unknown one, must both
      # degrade rather than raise — and must not grow the atom table.
      assert {:ok, "English (Time Zone: UTC Time)"} =
               LocaleDisplay.display_name("en-u-tz-utc")
    end
  end

  describe "display_name/2 -u- key ordering and composition" do
    test "multiple keys are displayed sorted by BCP47 key, not input order" do
      # Input order is ca, nu, hc but display order is ca, hc, nu.
      assert {:ok, "English (Buddhist Calendar, 12 Hour System [1–12], Thai Digits)"} =
               LocaleDisplay.display_name("en-u-ca-buddhist-nu-thai-hc-h12")
    end

    test "nested parentheses in type names are replaced with brackets" do
      assert {:ok, "English (Gregorian Calendar [ISO 8601 Weeks])"} =
               LocaleDisplay.display_name("en-u-ca-iso8601")

      assert {:ok, "English (Hijri Calendar [Umm al-Qura])"} =
               LocaleDisplay.display_name("en-u-ca-islamic-umalqura")
    end

    test "deprecated calendar aliases canonicalize to the preferred form" do
      assert {:ok, "English (Hijri Calendar [tabular, civil epoch])"} =
               LocaleDisplay.display_name("en-u-ca-islamicc")
    end
  end

  describe "display_name/2 -u- special value handling" do
    test "renders a multi-zone territory timezone using the exemplar city" do
      assert {:ok, "English (Time Zone: New York Time)"} =
               LocaleDisplay.display_name("en-u-tz-usnyc")
    end

    test "renders the UTC timezone with its derived name" do
      assert {:ok, "English (Time Zone: UTC Time)"} =
               LocaleDisplay.display_name("en-u-tz-utc")
    end

    test "falls back to the raw code when a subdivision has no display name" do
      # The en locale_display_names subdivision table covers only a
      # handful of codes (gbeng, gbsct, gbwls); usca is not among them
      # so the raw value is shown after the key name.
      assert {:ok, "English (Region Subdivision: usca)"} =
               LocaleDisplay.display_name("en-u-sd-usca")
    end

    test "renders currencies with their symbols" do
      assert {:ok, "English (Currency: $)"} =
               LocaleDisplay.display_name("en-u-cu-usd")

      assert {:ok, "English (Currency: ¤)"} =
               LocaleDisplay.display_name("en-u-cu-xxx")
    end

    test "renders the region override with the territory name" do
      assert {:ok, "English (Region For Supplemental Data: France)"} =
               LocaleDisplay.display_name("en-u-rg-frzzzz")
    end

    test "renders measurement system and unit override keys" do
      assert {:ok, "English (US Measurement System)"} =
               LocaleDisplay.display_name("en-u-ms-ussystem")

      assert {:ok, "English (Celsius)"} =
               LocaleDisplay.display_name("en-u-mu-celsius")
    end

    test "renders sentence break suppression" do
      assert {:ok, "English (Suppress Sentence Breaks After Standard Abbreviations)"} =
               LocaleDisplay.display_name("en-u-ss-standard")
    end

    test "renders text presentation, loose line breaks and phrase line wrap" do
      assert {:ok,
              "English (Text Presentation For Emoji, Loose Line Break Style, " <>
                "Prevent Line Breaks In Phrases)"} =
               LocaleDisplay.display_name("en-u-em-text-lb-loose-lw-phrase")
    end

    test "renders multiple dictionary break exclusion scripts translated and joined" do
      # Regression: list-valued dx concatenated the untranslated
      # script codes ("LaooThai") instead of translating each script
      # and joining with the list separator like -u-kr does.
      assert {:ok, "English (Dictionary Break Exclusions: Lao, Thai)"} =
               LocaleDisplay.display_name("en-u-dx-thai-laoo")
    end
  end

  describe "display_name/1 on a parsed (unvalidated) tag with -u-" do
    test "joins multi-part -u- values with hyphens in the canonical id" do
      # Regression: list values were flattened without hyphens,
      # producing "en-u-ca-islamiccivil-nu-thai" and an
      # UnknownLocaleError.
      {:ok, language_tag} = Localize.LanguageTag.parse("en-u-ca-islamic-civil-nu-thai")

      assert Localize.LanguageTag.to_string(language_tag) == "en-u-ca-islamic-civil-nu-thai"

      assert {:ok, "English (Hijri Calendar [tabular, civil epoch], Thai Digits)"} =
               LocaleDisplay.display_name(language_tag)
    end
  end

  describe "U.display_name/4 with a plain (unvalidated) extension map" do
    test "joins multi-part values with hyphens and canonicalizes them" do
      assert "Hijri Calendar [tabular, civil epoch]" =
               render(U.display_name(%{"ca" => ["islamic", "civil"]}, :en, display_names(), []))
    end

    test "canonicalizes deprecated aliases from a map value" do
      assert "Hijri Calendar [tabular, civil epoch]" =
               render(U.display_name(%{"ca" => "islamicc"}, :en, display_names(), []))
    end

    test "falls back to the key name and raw value for unknown values" do
      assert "Calendar: zzzz" =
               render(U.display_name(%{"ca" => "zzzz"}, :en, display_names(), []))
    end

    test "orders map keys by BCP47 key" do
      assert "Buddhist Calendar, Thai Digits" =
               render(
                 U.display_name(%{"nu" => "thai", "ca" => "buddhist"}, :en, display_names(), [])
               )
    end

    test "returns an empty list for an empty extension map" do
      assert [] == U.display_name(%{}, :en, display_names(), [])
    end
  end

  describe "display_name/2 -u- field rendering" do
    test "renders the rg region override with a territory name" do
      assert LocaleDisplay.display_name("en-u-rg-uszzzz", locale: :en) ==
               {:ok, "English (Region For Supplemental Data: United States)"}
    end

    test "renders the cu currency with its symbol" do
      assert LocaleDisplay.display_name("en-u-cu-usd", locale: :en) ==
               {:ok, "English (Currency: $)"}
    end

    test "renders the tz timezone with its city-based name" do
      assert LocaleDisplay.display_name("en-u-tz-ausyd", locale: :en) ==
               {:ok, "English (Time Zone: Sydney Time)"}

      assert LocaleDisplay.display_name("en-u-tz-usnyc", locale: :en) ==
               {:ok, "English (Time Zone: New York Time)"}
    end

    test "renders the sd subdivision with the raw code when unnamed" do
      assert LocaleDisplay.display_name("en-u-sd-usca", locale: :en) ==
               {:ok, "English (Region Subdivision: usca)"}
    end

    test "renders the fw first-day-of-week value" do
      assert LocaleDisplay.display_name("en-u-fw-mon", locale: :en) ==
               {:ok, "English (First day of week: Monday)"}
    end

    test "renders the hc hour-cycle value" do
      assert LocaleDisplay.display_name("en-u-hc-h23", locale: :en) ==
               {:ok, "English (24 Hour System [0–23])"}
    end

    test "renders the ms measurement system value" do
      assert LocaleDisplay.display_name("en-u-ms-metric", locale: :en) ==
               {:ok, "English (Metric System)"}
    end

    test "renders the cf currency format value" do
      assert LocaleDisplay.display_name("en-u-cf-account", locale: :en) ==
               {:ok, "English (Accounting Currency Format)"}
    end

    test "renders the em emoji presentation value" do
      assert LocaleDisplay.display_name("en-u-em-emoji", locale: :en) ==
               {:ok, "English (Emoji Presentation For Emoji)"}
    end

    test "renders the va posix variant value" do
      assert LocaleDisplay.display_name("en-u-va-posix", locale: :en) ==
               {:ok, "English (POSIX Compliant Locale)"}
    end

    test "renders the dx dictionary-break value with the raw script code" do
      assert LocaleDisplay.display_name("en-u-dx-thai", locale: :en) ==
               {:ok, "English (Dictionary Break Exclusions: thai)"}
    end
  end

  defp render(iodata), do: :erlang.iolist_to_binary(iodata)

  defp display_names(locale_id \\ :en) do
    {:ok, locale_display_names} = Localize.Locale.get(locale_id, [:locale_display_names])
    {:ok, territories} = Localize.Locale.get(locale_id, [:territories])
    {:ok, bracket_replacements} = Localize.Locale.get(locale_id, [:nested_bracket_replacement])

    locale_display_names
    |> Map.put(:territory, territories)
    |> Map.put(:nested_bracket_replacement, bracket_replacements)
  end
end
