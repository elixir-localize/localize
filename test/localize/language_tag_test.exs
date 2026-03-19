defmodule Localize.LanguageTagTest do
  use ExUnit.Case, async: true

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
      assert {:error, {Localize.LanguageTag.ParseError, _message}} =
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
      assert_raise Localize.LanguageTag.ParseError, fn ->
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
      assert_raise Localize.LanguageTag.ParseError, fn ->
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

  describe "best_match/3" do
    test "finds exact match" do
      {:ok, match, score} = LanguageTag.best_match("en-US", ["en-US", "fr", "de"])
      assert match == "en-US"
      assert score == 0
    end

    test "finds closest regional match" do
      {:ok, match, _} = LanguageTag.best_match("en-AU", ["en", "en-GB", "fr"])
      assert match == "en-GB"
    end

    test "finds best script match for zh-HK" do
      {:ok, match, _} = LanguageTag.best_match("zh-HK", ["zh", "zh-Hans", "zh-Hant", "en"])
      assert match == "zh-Hant"
    end

    test "matches dialect to parent language" do
      {:ok, match, _} = LanguageTag.best_match("gsw", ["de", "fr", "it", "en"])
      assert match == "de"
    end

    test "returns default locale when no match within threshold" do
      # When no match is within threshold, the CLDR algorithm returns
      # the first supported locale as the default.
      assert {:ok, "en", _} = LanguageTag.best_match("zh", ["en", "fr"], 5)
    end

    test "returns error for empty supported list" do
      assert {:error, _} = LanguageTag.best_match("zh", [], 5)
    end

    test "respects custom distance threshold" do
      # gsw → de has distance ~8, so threshold 5 returns de as default
      assert {:ok, "de", _} = LanguageTag.best_match("gsw", ["de"], 5)
      # Threshold 10 accepts it as a proper match
      assert {:ok, "de", _} = LanguageTag.best_match("gsw", ["de"], 10)
    end

    test "prefers lower distance" do
      {:ok, match, _} = LanguageTag.best_match("pt-BR", ["pt", "pt-PT", "es"])
      assert match == "pt"
    end

    test "accepts a LanguageTag struct as desired" do
      {:ok, tag} = LanguageTag.new("en-AU")
      {:ok, match, score} = LanguageTag.best_match(tag, ["en", "en-GB", "fr"])
      assert match == "en-GB"
      assert score == 3
    end

    test "accepts atom as desired" do
      {:ok, match, _} = LanguageTag.best_match(:"en-AU", ["en", "en-GB", "fr"])
      assert match == "en-GB"
    end

    test "accepts atoms in supported list" do
      {:ok, match, _} = LanguageTag.best_match("en-AU", [:en, :"en-GB", :fr])
      assert match == :"en-GB"
    end

    test "returns original atom form from supported" do
      {:ok, match, score} = LanguageTag.best_match("en", [:en, :fr])
      assert match == :en
      assert is_atom(match)
      assert score == 0
    end
  end

  describe "parent/1" do
    test "standard territory inheritance strips territory" do
      {:ok, parent} = LanguageTag.parent("en-AU")
      assert parent.language == :en
      assert parent.territory == :"001"
    end

    test "standard region-group inheritance strips to language" do
      {:ok, parent} = LanguageTag.parent("en-001")
      assert parent.language == :en
      assert parent.territory == nil
    end

    test "language-only locale inherits from und" do
      {:ok, parent} = LanguageTag.parent("en")
      assert parent.language == :und
    end

    test "und (root) has no parent" do
      assert {:error, {Localize.NoParentError, _}} = LanguageTag.parent("und")
    end

    test "non-standard parent from CLDR parentLocales data" do
      {:ok, parent} = LanguageTag.parent("nb")
      assert parent.language == :no

      {:ok, parent} = LanguageTag.parent("ht")
      assert parent.language == :fr
      assert parent.territory == :HT

      {:ok, parent} = LanguageTag.parent("zh-Hant-MO")
      assert parent.language == :zh
      assert parent.script == :Hant
      assert parent.territory == :HK

      {:ok, parent} = LanguageTag.parent("es-AR")
      assert parent.language == :es
      assert parent.territory == :"419"

      {:ok, parent} = LanguageTag.parent("pt-AO")
      assert parent.language == :pt
      assert parent.territory == :PT
    end

    test "non-standard script locale inherits from und" do
      {:ok, parent} = LanguageTag.parent("sr-Latn")
      assert parent.language == :und
    end

    test "extensions are transferred to parent" do
      {:ok, parent} = LanguageTag.parent("en-AU-u-ca-buddhist")
      assert parent.language == :en
      assert parent.territory == :"001"
      assert parent.locale != %{}

      canonical = LanguageTag.to_string(parent)
      assert canonical =~ "u-ca-buddhist"
    end

    test "accepts a LanguageTag struct" do
      {:ok, tag} = LanguageTag.new("en-AU")
      {:ok, parent} = LanguageTag.parent(tag)
      assert parent.language == :en
      assert parent.territory == :"001"
    end

    test "script-territory locale strips territory first" do
      {:ok, parent} = LanguageTag.parent("zh-Hant-TW")
      # zh-Hant-TW is not in parent_locales, so strip territory → zh-Hant
      # But zh-Hant IS in parent_locales → und
      # Actually, zh-Hant-TW strips territory first → zh-Hant
      assert parent.language == :zh
      assert parent.script == :Hant
      assert parent.territory == nil
    end

    test "full inheritance chain from en-AU to und" do
      chain =
        Stream.unfold("en-AU", fn locale ->
          case LanguageTag.parent(locale) do
            {:ok, parent} ->
              parent_string = LanguageTag.to_string(parent)
              {parent_string, parent}

            {:error, _} ->
              nil
          end
        end)
        |> Enum.to_list()

      assert chain == ["en-001", "en", "und"]
    end

    test "full inheritance chain from es-MX" do
      chain =
        Stream.unfold("es-MX", fn locale ->
          case LanguageTag.parent(locale) do
            {:ok, parent} ->
              parent_string = LanguageTag.to_string(parent)
              {parent_string, parent}

            {:error, _} ->
              nil
          end
        end)
        |> Enum.to_list()

      assert chain == ["es-419", "es", "und"]
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
end
