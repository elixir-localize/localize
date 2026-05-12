defmodule Localize.LanguageTagTest do
  use ExUnit.Case, async: true

  doctest Localize.LanguageTag

  alias Localize.LanguageTag

  describe "parse/1 basic language tags" do
    test "parses simple language code" do
      assert {:ok, tag} = LanguageTag.parse("en")
      assert tag.language == :en
      assert tag.script == nil
      assert tag.territory == nil
      assert tag.language_variants == []
      assert tag.requested_locale_id == "en"
    end

    test "parses language with territory" do
      assert {:ok, tag} = LanguageTag.parse("en-US")
      assert tag.language == :en
      assert tag.territory == :US
      assert tag.script == nil
    end

    test "parses language with script" do
      assert {:ok, tag} = LanguageTag.parse("zh-Hans")
      assert tag.language == :zh
      assert tag.script == :Hans
    end

    test "parses language with script and territory" do
      assert {:ok, tag} = LanguageTag.parse("zh-Hans-CN")
      assert tag.language == :zh
      assert tag.script == :Hans
      assert tag.territory == :CN
    end

    test "parses three-letter language code" do
      assert {:ok, tag} = LanguageTag.parse("yue")
      assert tag.language == :yue
    end

    test "parses language with variant" do
      assert {:ok, tag} = LanguageTag.parse("sr-Cyrl-RS-fonipa")
      assert tag.language == :sr
      assert tag.script == :Cyrl
      assert tag.territory == :RS
      assert tag.language_variants == ["fonipa"]
    end

    test "case is normalised on parse" do
      assert {:ok, tag} = LanguageTag.parse("EN-us")
      assert tag.language == :en
      assert tag.territory == :US
    end

    test "parses UN M.49 numeric region code" do
      assert {:ok, tag} = LanguageTag.parse("es-419")
      assert tag.language == :es
      assert tag.territory == :"419"
    end
  end

  describe "parse/1 unicode locale extension (-u-)" do
    test "parses calendar extension" do
      assert {:ok, tag} = LanguageTag.parse("en-US-u-ca-gregory")
      assert tag.locale == %{"ca" => "gregory"}
    end

    test "parses multiple locale keywords" do
      assert {:ok, tag} = LanguageTag.parse("en-US-u-ca-gregory-nu-arab")
      assert tag.locale["ca"] == "gregory"
      assert tag.locale["nu"] == "arab"
    end

    test "parses collation extension" do
      assert {:ok, tag} = LanguageTag.parse("de-u-co-phonebk")
      assert tag.locale["co"] == "phonebk"
    end
  end

  describe "parse/1 transform extension (-t-)" do
    test "parses transform with language" do
      assert {:ok, tag} = LanguageTag.parse("de-DE-t-en-US")
      # Inner transform language tag is tokenized (not fully parsed)
      assert tag.transform["language"].language == "en"
    end

    test "parses transform with keywords" do
      assert {:ok, tag} = LanguageTag.parse("de-DE-t-en-US-h0-hybrid")
      assert tag.transform["h0"] == "hybrid"
      assert tag.transform["language"].language == "en"
    end
  end

  describe "parse/1 private use" do
    test "parses private use tag" do
      assert {:ok, tag} = LanguageTag.parse("x-private")
      assert tag.private_use == ["private"]
    end

    test "parses private use with multiple subtags" do
      assert {:ok, tag} = LanguageTag.parse("en-US-x-custom-tag")
      assert tag.language == :en
      assert tag.territory == :US
      assert tag.private_use == ["custom", "tag"]
    end
  end

  describe "parse/1 error cases" do
    test "returns error for invalid tag" do
      assert {:error, %Localize.ParseError{}} =
               LanguageTag.parse("not-valid-!")
    end

    test "returns error for empty string" do
      assert {:error, _} = LanguageTag.parse("")
    end
  end

  describe "parse!/1" do
    test "returns struct on success" do
      tag = LanguageTag.parse!("en-US")
      assert tag.language == :en
      assert tag.territory == :US
    end

    test "raises on error" do
      assert_raise Localize.ParseError, fn ->
        LanguageTag.parse!("!!!")
      end
    end
  end

  describe "to_string/1 on parsed (uncanonicalized) tags" do
    test "produces core subtags for a simple tag" do
      {:ok, tag} = LanguageTag.parse("en-US")
      assert LanguageTag.to_string(tag) == "en-US"
    end

    test "produces core subtags with script" do
      {:ok, tag} = LanguageTag.parse("zh-Hans-CN")
      assert LanguageTag.to_string(tag) == "zh-Hans-CN"
    end

    test "includes extensions from raw maps" do
      {:ok, tag} = LanguageTag.parse("en-US-u-ca-gregory-nu-arab")
      result = LanguageTag.to_string(tag)
      assert result =~ "en-US"
      assert result =~ "u-"
      assert result =~ "ca-gregory"
      assert result =~ "nu-arab"
    end
  end

  describe "canonicalize/1" do
    test "populates canonical_locale_id" do
      {:ok, tag} = LanguageTag.parse("en-US")
      assert tag.canonical_locale_id == nil

      {:ok, canonical} = LanguageTag.canonicalize(tag)
      assert canonical.canonical_locale_id == "en-US"
    end

    test "sorts variants alphabetically" do
      {:ok, tag} = LanguageTag.parse("en-scouse-fonipa")
      {:ok, canonical} = LanguageTag.canonicalize(tag)
      assert canonical.canonical_locale_id == "en-fonipa-scouse"
      assert canonical.language_variants == ["fonipa", "scouse"]
    end

    test "sorts u-extension keys alphabetically" do
      {:ok, tag} = LanguageTag.parse("en-US-u-nu-arab-ca-gregory")
      {:ok, canonical} = LanguageTag.canonicalize(tag)
      assert canonical.canonical_locale_id == "en-US-u-ca-gregory-nu-arab"
    end

    test "sorts extensions by singleton: t before u" do
      {:ok, tag} = LanguageTag.parse("en-US-u-ca-gregory-t-de")
      {:ok, canonical} = LanguageTag.canonicalize(tag)
      assert canonical.canonical_locale_id == "en-US-t-de-u-ca-gregory"
    end

    test "canonicalizes transform extension with language" do
      {:ok, tag} = LanguageTag.parse("de-DE-t-en-US-h0-hybrid")
      {:ok, canonical} = LanguageTag.canonicalize(tag)
      assert canonical.canonical_locale_id == "de-DE-t-en-us-h0-hybrid"
    end

    test "preserves script in title case" do
      {:ok, tag} = LanguageTag.parse("zh-hans-cn")
      {:ok, canonical} = LanguageTag.canonicalize(tag)
      assert canonical.canonical_locale_id == "zh-Hans-CN"
    end

    test "preserves territory in uppercase" do
      {:ok, tag} = LanguageTag.parse("en-us")
      {:ok, canonical} = LanguageTag.canonicalize(tag)
      assert canonical.canonical_locale_id == "en-US"
    end

    test "language is lowercase" do
      {:ok, tag} = LanguageTag.parse("EN")
      {:ok, canonical} = LanguageTag.canonicalize(tag)
      assert canonical.canonical_locale_id == "en"
    end

    test "preserves private use" do
      {:ok, tag} = LanguageTag.parse("en-x-custom-tag")
      {:ok, canonical} = LanguageTag.canonicalize(tag)
      assert canonical.canonical_locale_id == "en-x-custom-tag"
    end

    test "preserves UN M.49 region code" do
      {:ok, tag} = LanguageTag.parse("es-419")
      {:ok, canonical} = LanguageTag.canonicalize(tag)
      assert canonical.canonical_locale_id == "es-419"
    end

    test "to_string returns cached canonical name" do
      {:ok, tag} = LanguageTag.parse("en-US-u-nu-arab-ca-gregory")
      {:ok, canonical} = LanguageTag.canonicalize(tag)
      assert LanguageTag.to_string(canonical) == canonical.canonical_locale_id
    end
  end

  describe "canonicalize!/1" do
    test "returns canonicalized tag directly" do
      {:ok, tag} = LanguageTag.parse("en-US")
      canonical = LanguageTag.canonicalize!(tag)
      assert canonical.canonical_locale_id == "en-US"
    end
  end

  describe "new/1" do
    test "fully resolves a simple language tag" do
      {:ok, tag} = LanguageTag.new("en")
      assert tag.language == :en
      assert tag.script == :Latn
      assert tag.territory == :US
      assert tag.canonical_locale_id == "en"
      assert tag.cldr_locale_id == :en
    end

    test "fully resolves a language with territory" do
      {:ok, tag} = LanguageTag.new("zh-TW")
      assert tag.language == :zh
      assert tag.script == :Hant
      assert tag.territory == :TW
      assert tag.canonical_locale_id == "zh-Hant"
      assert tag.cldr_locale_id != nil
    end

    test "populates cldr_locale_id via best_match" do
      {:ok, tag} = LanguageTag.new("en-AU")
      assert tag.cldr_locale_id == :"en-AU"
    end

    test "resolves deprecated locale to cldr name" do
      {:ok, tag} = LanguageTag.new("iw")
      assert tag.language == :he
      assert tag.cldr_locale_id == :he
    end

    test "fully resolves with extensions" do
      {:ok, tag} = LanguageTag.new("en-US-u-ca-gregory")
      assert tag.language == :en
      assert tag.script == :Latn
      assert tag.territory == :US
      assert tag.canonical_locale_id == "en-u-ca-gregory"
      assert tag.cldr_locale_id != nil
    end

    test "preserves requested_locale_id" do
      {:ok, tag} = LanguageTag.new("EN-us")
      assert tag.requested_locale_id == "EN-us"
    end

    test "returns error for invalid input" do
      assert {:error, _} = LanguageTag.new("!!!")
    end
  end

  describe "new!/1" do
    test "returns resolved tag directly" do
      tag = LanguageTag.new!("en")
      assert tag.language == :en
      assert tag.script == :Latn
      assert tag.territory == :US
    end

    test "raises on invalid input" do
      assert_raise Localize.ParseError, fn ->
        LanguageTag.new!("!!!")
      end
    end
  end

  describe "add_likely_subtags/1" do
    test "populates missing script and territory" do
      {:ok, tag} = LanguageTag.parse("en")
      {:ok, max} = LanguageTag.add_likely_subtags(tag)
      assert max.language == :en
      assert max.script == :Latn
      assert max.territory == :US
    end

    test "populates missing script" do
      {:ok, tag} = LanguageTag.parse("zh-TW")
      {:ok, max} = LanguageTag.add_likely_subtags(tag)
      assert max.script == :Hant
    end

    test "does not overwrite existing fields" do
      {:ok, tag} = LanguageTag.parse("zh-Hans-CN")
      {:ok, max} = LanguageTag.add_likely_subtags(tag)
      assert max.language == :zh
      assert max.script == :Hans
      assert max.territory == :CN
    end
  end

  describe "remove_likely_subtags/1" do
    test "returns struct with all fields populated" do
      {:ok, tag} = LanguageTag.parse("en-Latn-US")
      {:ok, min} = LanguageTag.remove_likely_subtags(tag)
      assert min.language == :en
      assert min.script == :Latn
      assert min.territory == :US
      assert min.canonical_locale_id == "en"
    end

    test "favor script keeps script when ambiguous" do
      {:ok, tag} = LanguageTag.parse("zh-Hant-TW")
      {:ok, min} = LanguageTag.remove_likely_subtags(tag)
      assert min.canonical_locale_id == "zh-Hant"
      # Struct still has all fields
      assert min.script == :Hant
      assert min.territory == :TW
    end
  end

  describe "alias resolution in canonicalize/1" do
    test "resolves deprecated language code iw to he" do
      {:ok, tag} = LanguageTag.parse("iw")
      {:ok, canonical} = LanguageTag.canonicalize(tag)
      assert canonical.language == :he
    end

    test "resolves deprecated language code in to id" do
      {:ok, tag} = LanguageTag.parse("in")
      {:ok, canonical} = LanguageTag.canonicalize(tag)
      assert canonical.language == :id
    end

    test "resolves deprecated language code mo to ro" do
      {:ok, tag} = LanguageTag.parse("mo")
      {:ok, canonical} = LanguageTag.canonicalize(tag)
      assert canonical.language == :ro
    end

    test "resolves sh to sr-Latn (language alias carries script)" do
      {:ok, tag} = LanguageTag.parse("sh")
      {:ok, canonical} = LanguageTag.canonicalize(tag)
      assert canonical.language == :sr
      assert canonical.script == :Latn
    end

    test "language alias does not overwrite existing script" do
      {:ok, tag} = LanguageTag.parse("sh-Cyrl")
      {:ok, canonical} = LanguageTag.canonicalize(tag)
      assert canonical.language == :sr
      assert canonical.script == :Cyrl
    end

    test "resolves deprecated region code" do
      {:ok, tag} = LanguageTag.parse("de-DD")
      {:ok, canonical} = LanguageTag.canonicalize(tag)
      assert canonical.territory == :DE
    end

    test "resolves deprecated script code" do
      {:ok, tag} = LanguageTag.parse("en-Qaai")
      {:ok, canonical} = LanguageTag.canonicalize(tag)
      assert canonical.script == :Zinh
    end

    test "resolves deprecated variant" do
      {:ok, tag} = LanguageTag.parse("ja-Latn-heploc")
      {:ok, canonical} = LanguageTag.canonicalize(tag)
      assert "alalc97" in canonical.language_variants
    end

    test "aliases resolved via new/1 pipeline" do
      {:ok, tag} = LanguageTag.new("iw")
      assert tag.language == :he
      assert tag.script == :Hebr
      assert tag.territory == :IL
    end
  end

  describe "match_distance/2" do
    test "identical locales have zero distance" do
      assert Localize.LanguageTag.match_distance("en", "en") == 0
    end

    test "same language different territory" do
      assert Localize.LanguageTag.match_distance("en-AU", "en-GB") == 3
    end

    test "same language with territory vs without" do
      assert Localize.LanguageTag.match_distance("en-AU", "en") == 5
    end

    test "closely related languages" do
      assert Localize.LanguageTag.match_distance("nb", "no") == 1
    end

    test "one-way dialect match" do
      distance = Localize.LanguageTag.match_distance("gsw", "de")
      assert distance <= 10
    end

    test "completely different languages have high distance" do
      distance = Localize.LanguageTag.match_distance("en", "zh-Hans")
      assert distance > 100
    end
  end

  describe "struct fields" do
    test "fields are atoms" do
      {:ok, tag} = LanguageTag.parse("en-Latn-US")
      assert is_atom(tag.language)
      assert is_atom(tag.script)
      assert is_atom(tag.territory)
    end

    test "partially populated struct has correct defaults" do
      {:ok, tag} = LanguageTag.parse("en")
      assert tag.language_subtags == []
      assert tag.locale == %{}
      assert tag.transform == %{}
      assert tag.extensions == %{}
      assert tag.private_use == []
      assert tag.canonical_locale_id == nil
      assert tag.cldr_locale_id == nil
    end

    test "requested_locale_id preserves original input" do
      {:ok, tag} = LanguageTag.parse("EN-us")
      assert tag.requested_locale_id == "EN-us"
    end
  end

  describe "input length cap" do
    test "rejects oversized input without invoking the grammar" do
      cap = LanguageTag.max_locale_id_bytes()
      huge = String.duplicate("a", cap + 1)

      assert {:error, %Localize.InvalidLocaleError{locale_id: msg}} =
               LanguageTag.parse(huge)

      assert msg =~ "exceeds"
    end

    test "input at the cap is not rejected by the length guard" do
      cap = LanguageTag.max_locale_id_bytes()
      # At-cap input. Grammar may accept or reject; the important
      # assertion is that we don't see the cap-rejection error.
      at_cap = String.duplicate("a", cap)

      case LanguageTag.parse(at_cap) do
        {:ok, _} -> :ok
        {:error, %Localize.InvalidLocaleError{locale_id: msg}} -> refute msg =~ "exceeds"
        {:error, _} -> :ok
      end
    end
  end
end
