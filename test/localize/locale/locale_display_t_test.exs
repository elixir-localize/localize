defmodule Localize.Locale.LocaleDisplayTTest do
  use ExUnit.Case, async: true

  alias Localize.Locale.LocaleDisplay
  alias Localize.Locale.LocaleDisplay.T

  describe "display_name/2 -t- field keys" do
    test "renders the source of transformation" do
      assert {:ok, "English (Transform: German, From ASCII)"} =
               LocaleDisplay.display_name("en-t-de-s0-ascii")
    end

    test "renders the destination of transformation" do
      assert {:ok, "English (To Fullwidth, Transform: German)"} =
               LocaleDisplay.display_name("en-t-de-d0-fwidth")
    end

    test "renders the input method key" do
      assert {:ok, "English (Pinyin Input Method, Transform: German)"} =
               LocaleDisplay.display_name("en-t-de-i0-pinyin")
    end

    test "renders the keyboard key" do
      assert {:ok, "English (Dvorak Keyboard, Transform: German)"} =
               LocaleDisplay.display_name("en-t-de-k0-dvorak")
    end

    test "renders the machine translation key" do
      assert {:ok, "English (Transform: German, Unspecified Machine Translation)"} =
               LocaleDisplay.display_name("en-t-de-t0-und")
    end

    test "renders multiple -t- fields together" do
      assert {:ok, "English (Transform: German, UN GEGN Transliteration, From ASCII)"} =
               LocaleDisplay.display_name("en-t-de-m0-ungegn-s0-ascii")
    end

    test "renders multiple x0 private-use values joined with the list separator" do
      assert {:ok, "English (Transform: German, Private-Use Transform: foo, bar)"} =
               LocaleDisplay.display_name("en-t-de-x0-foo-bar")
    end
  end

  describe "display_name/2 -t- language flattening" do
    test "flattens an unknown transform language with its script" do
      assert {:ok, "English (Transform: Unknown language, Latin)"} =
               LocaleDisplay.display_name("en-t-und-Latn")
    end

    test "flattens language, script and territory in standard mode" do
      assert {:ok, "English (Transform: Chinese, Simplified, China)"} =
               LocaleDisplay.display_name("en-t-zh-Hans-CN")
    end

    test "flattens a numeric territory in standard mode" do
      assert {:ok, "English (Transform: Spanish, Latin America)"} =
               LocaleDisplay.display_name("en-t-es-419")
    end

    test "renders multiple variants of the transform language" do
      assert {:ok, "English (Transform: French, Canada, IPA Phonetics, UPA Phonetics)"} =
               LocaleDisplay.display_name("en-t-fr-CA-fonipa-fonupa")
    end

    test "dialect mode consumes a numeric territory in the longest match" do
      assert {:ok, "English (Transform: Latin American Spanish)"} =
               LocaleDisplay.display_name("en-t-es-419", language_display: :dialect)
    end

    test "dialect mode consumes the script in the longest match" do
      assert {:ok, "English (Transform: Simplified Chinese)"} =
               LocaleDisplay.display_name("en-t-zh-Hans", language_display: :dialect)
    end

    test "dialect mode shows subtags not consumed by the longest match" do
      # zh-Hans matches "Simplified Chinese" (script consumed) and the
      # territory remains as a separate subtag.
      assert {:ok, "English (Transform: Simplified Chinese, China)"} =
               LocaleDisplay.display_name("en-t-zh-Hans-CN", language_display: :dialect)
    end
  end

  describe "display_name/2 -t- combined with other extensions and locales" do
    test "renders the -t- extension after -u- extension values" do
      assert {:ok, "English (Buddhist Calendar, Transform: Japanese)"} =
               LocaleDisplay.display_name("en-t-ja-u-ca-buddhist")
    end

    test "renders the transform in the display locale" do
      {:ok, name} = LocaleDisplay.display_name("fr-t-en-m0-ungegn", locale: :fr)
      assert name =~ "anglais"
      assert name =~ "UNGEGN"
    end
  end

  describe "display_name/1 on a parsed (unvalidated) tag with -t-" do
    test "renders a tokenized transform language instead of crashing" do
      # Regression: the raw transform map stores the tlang as a
      # tokenized LanguageTag under the "language" key. Stringifying
      # it returned nil (no canonical_locale_id) and crashed
      # Enum.join with an ArgumentError.
      {:ok, language_tag} = Localize.LanguageTag.parse("en-t-de-m0-ungegn")

      assert {:ok, "English (Transform: German, UN GEGN Transliteration)"} =
               LocaleDisplay.display_name(language_tag)
    end

    test "to_string/1 renders the tlang first and without its map key" do
      {:ok, language_tag} = Localize.LanguageTag.parse("en-t-de-m0-ungegn")
      assert Localize.LanguageTag.to_string(language_tag) == "en-t-de-m0-ungegn"

      {:ok, language_tag} = Localize.LanguageTag.parse("en-t-zh-hans-cn-m0-ungegn")
      assert Localize.LanguageTag.to_string(language_tag) == "en-t-zh-hans-cn-m0-ungegn"
    end
  end

  describe "T.display_name/4 with a plain (unvalidated) transform map" do
    test "renders known fields from a parsed transform map" do
      {:ok, language_tag} = Localize.LanguageTag.parse("en-t-de-m0-ungegn")

      rendered = render(T.display_name(language_tag.transform, :en, display_names(), []))
      assert rendered =~ "Transform:"
      assert rendered =~ "UN GEGN Transliteration"
    end

    test "falls back to the key name and raw value for unknown values" do
      assert "Transform Rules: zzzz" =
               render(T.display_name(%{"m0" => "zzzz"}, :en, display_names(), []))
    end

    test "returns an empty list for an empty transform map" do
      assert [] == T.display_name(%{}, :en, display_names(), [])
    end
  end

  defp render(iodata), do: :erlang.iolist_to_binary(iodata)

  defp display_names(locale_id \\ :en) do
    {:ok, locale_display_names} = Localize.Locale.get(locale_id, [:locale_display_names])
    {:ok, languages} = Localize.Locale.get(locale_id, [:languages])
    {:ok, territories} = Localize.Locale.get(locale_id, [:territories])
    {:ok, bracket_replacements} = Localize.Locale.get(locale_id, [:nested_bracket_replacement])

    locale_display_names
    |> Map.put(:language, languages)
    |> Map.put(:territory, territories)
    |> Map.put(:nested_bracket_replacement, bracket_replacements)
  end
end
