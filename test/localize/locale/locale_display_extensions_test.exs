defmodule Localize.Locale.LocaleDisplayExtensionsTest do
  use ExUnit.Case, async: true

  alias Localize.Locale.LocaleDisplay

  describe "display_name/2 for -u- keyword values" do
    test "renders calendar and numbering system names" do
      assert {:ok, "English (United States, Buddhist Calendar, Thai Digits)"} =
               LocaleDisplay.display_name("en-US-u-ca-buddhist-nu-thai")
    end

    test "renders the hour cycle" do
      {:ok, name} = LocaleDisplay.display_name("en-u-hc-h23")
      assert name =~ "24 Hour System"
    end

    test "renders the first day of week" do
      assert {:ok, "English (First day of week: Monday)"} =
               LocaleDisplay.display_name("en-u-fw-mon")
    end

    test "renders measurement systems" do
      assert {:ok, "English (Imperial Measurement System)"} =
               LocaleDisplay.display_name("en-u-ms-uksystem")

      assert {:ok, "English (Metric System)"} =
               LocaleDisplay.display_name("en-u-ms-metric")
    end

    test "renders collation types and options" do
      assert {:ok, "English (Phonebook Sort Order)"} =
               LocaleDisplay.display_name("en-u-co-phonebk")

      assert {:ok, "English (Sort Digits Numerically)"} =
               LocaleDisplay.display_name("en-u-kn-true")

      assert {:ok, "English (Sort Accents)"} =
               LocaleDisplay.display_name("en-u-ks-level2")

      assert {:ok, "English (Sort Uppercase First)"} =
               LocaleDisplay.display_name("en-u-kf-upper")
    end

    test "renders script reordering with translated script and reorder names" do
      assert {:ok, "English (Script/Block Reordering: Latin, Digits)"} =
               LocaleDisplay.display_name("en-u-kr-latn-digit")
    end

    test "renders a timezone using the exemplar city" do
      {:ok, name} = LocaleDisplay.display_name("en-u-tz-ausyd")
      assert name =~ "Sydney Time"
    end

    test "renders a single-zone territory timezone using the country name" do
      {:ok, name} = LocaleDisplay.display_name("en-u-tz-gblon")
      assert name =~ "United Kingdom Time"
    end

    test "renders a region override territory name" do
      {:ok, name} = LocaleDisplay.display_name("en-u-rg-uszzzz")
      assert name =~ "United States"
    end

    test "renders a region override subdivision name" do
      {:ok, name} = LocaleDisplay.display_name("en-u-rg-gbeng")
      assert name =~ "England"
    end

    test "renders dictionary break exclusions with the script name" do
      {:ok, name} = LocaleDisplay.display_name("en-u-dx-thai")
      assert name =~ "Dictionary Break Exclusions"
    end

    test "renders emoji presentation, line break and variant keys" do
      assert {:ok, "English (Emoji Presentation For Emoji)"} =
               LocaleDisplay.display_name("en-u-em-emoji")

      assert {:ok, "English (Strict Line Break Style)"} =
               LocaleDisplay.display_name("en-u-lb-strict")

      assert {:ok, "English (POSIX Compliant Locale)"} =
               LocaleDisplay.display_name("en-u-va-posix")
    end

    test "renders a currency with its symbol" do
      {:ok, name} = LocaleDisplay.display_name("en-u-cu-aud")
      assert name =~ "Currency"
      assert name =~ "A$"
    end

    test "renders keyword names in the display locale" do
      {:ok, name} = LocaleDisplay.display_name("fr-u-ca-buddhist", locale: :fr)
      assert name == "français (calendrier bouddhiste)"
    end
  end

  describe "display_name/2 for -t- extensions" do
    test "renders a plain transform source language" do
      assert {:ok, "German (Transform: English)"} = LocaleDisplay.display_name("de-t-en")
    end

    test "renders the transform mechanism keyword" do
      assert {:ok, "Japanese (Transform: Italian, UN GEGN Transliteration)"} =
               LocaleDisplay.display_name("ja-t-it-m0-ungegn")
    end

    test "renders a hybrid transform with the h0 key name" do
      assert {:ok, "English (Hybrid: German)"} =
               LocaleDisplay.display_name("en-t-de-h0-hybrid")
    end

    test "renders transform language subtags flattened in standard mode" do
      assert {:ok, "English (Transform: French, Canada)"} =
               LocaleDisplay.display_name("en-t-fr-CA")
    end

    test "uses the longest language match in dialect mode" do
      assert {:ok, "English (Transform: Canadian French)"} =
               LocaleDisplay.display_name("en-t-fr-CA", language_display: :dialect)
    end

    test "renders script, territory and variants of the transform language" do
      assert {:ok, "English (Transform: French, Latin, Canada, IPA Phonetics)"} =
               LocaleDisplay.display_name("en-t-fr-Latn-CA-fonipa")
    end

    test "renders private use transform values" do
      assert {:ok, "English (Transform: German, Private-Use Transform: medical)"} =
               LocaleDisplay.display_name("en-t-de-x0-medical")
    end
  end

  describe "display_name/2 for generic extensions and private use" do
    test "renders a generic singleton extension as key-value pairs" do
      assert {:ok, "English (a: bcde-fghi)"} = LocaleDisplay.display_name("en-a-bcde-fghi")
    end

    test "renders private use subtags under the x key" do
      assert {:ok, "English (x: priv-use)"} = LocaleDisplay.display_name("en-x-priv-use")
    end
  end
end
