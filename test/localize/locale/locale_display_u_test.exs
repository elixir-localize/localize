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
