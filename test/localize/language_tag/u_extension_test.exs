defmodule Localize.LanguageTag.UExtensionTest do
  use ExUnit.Case, async: true

  alias Localize.LanguageTag.U

  doctest Localize.LanguageTag.U

  describe "parse/1" do
    test "parses bare keyword subtags" do
      assert {:ok, %U{ca: :gregorian, hc: :h23}} = U.parse("ca-gregory-hc-h23")
    end

    test "accepts a leading u- singleton and a leading dash" do
      assert {:ok, %U{nu: :thai}} = U.parse("u-nu-thai")
      assert {:ok, %U{co: :phonebook}} = U.parse("-u-co-phonebk")
    end

    test "decodes values to their canonical atoms" do
      assert {:ok, %U{ca: :iso8601}} = U.parse("ca-iso8601")
      assert {:ok, %U{rg: territory}} = U.parse("rg-uszzzz")
      assert territory != nil
    end

    test "matches the struct produced by validate_locale on a full tag" do
      {:ok, tag} = Localize.validate_locale("en-u-ca-gregory-hc-h23-nu-thai")
      {:ok, u} = U.parse("ca-gregory-hc-h23-nu-thai")
      assert u == tag.locale
    end

    test "returns a parse error for invalid input" do
      assert {:error, %Localize.ParseError{}} = U.parse("not a u extension")
      assert {:error, %Localize.ParseError{}} = U.parse("")
    end
  end

  describe "parse!/1" do
    test "returns the struct on success" do
      assert %U{hc: :h12} = U.parse!("hc-h12")
    end

    test "raises on invalid input" do
      assert_raise Localize.ParseError, fn -> U.parse!("") end
    end
  end

  describe "encode/1" do
    test "round-trips parse output to canonical pairs" do
      {:ok, u} = U.parse("hc-h23-ca-gregory")
      assert U.encode(u) == [{"ca", "gregory"}, {"hc", "h23"}]
    end

    test "encodes with the preferred spelling, never a deprecated alias" do
      # BCP 47 deprecates "islamicc" in favour of "islamic-civil";
      # both decode, only the preferred form is encoded.
      {:ok, u} = U.parse("ca-islamicc")
      assert U.encode(u) == [{"ca", "islamic-civil"}]
      assert to_string(u) == "ca-islamic-civil"
    end
  end

  describe "parse/1 across the keyword space" do
    test "decodes calendar, collation and currency keys" do
      assert {:ok, %U{ca: :buddhist}} = U.parse("ca-buddhist")
      assert {:ok, %U{co: :dictionary}} = U.parse("co-dict")
      assert {:ok, %U{cu: :USD}} = U.parse("cu-usd")
    end

    test "decodes formatting keys" do
      assert {:ok, %U{cf: :account}} = U.parse("cf-account")
      assert {:ok, %U{em: :emoji}} = U.parse("em-emoji")
      assert {:ok, %U{fw: :mon}} = U.parse("fw-mon")
      assert {:ok, %U{hc: :h11}} = U.parse("hc-h11")
      assert {:ok, %U{lb: :strict}} = U.parse("lb-strict")
      assert {:ok, %U{lw: :phrase}} = U.parse("lw-phrase")
      assert {:ok, %U{ms: :imperial}} = U.parse("ms-uksystem")
      assert {:ok, %U{mu: :celsius}} = U.parse("mu-celsius")
      assert {:ok, %U{ss: :standard}} = U.parse("ss-standard")
      assert {:ok, %U{va: :posix}} = U.parse("va-posix")
    end

    test "decodes collation option keys with alias resolution" do
      assert {:ok, %U{ka: :non_ignorable}} = U.parse("ka-noignore")
      assert {:ok, %U{kb: :yes}} = U.parse("kb-true")
      assert {:ok, %U{kc: :no}} = U.parse("kc-false")
      assert {:ok, %U{kf: :lower}} = U.parse("kf-lower")
      assert {:ok, %U{kh: :no}} = U.parse("kh-false")
      assert {:ok, %U{kk: :yes}} = U.parse("kk-true")
      assert {:ok, %U{kn: :yes}} = U.parse("kn-true")
      assert {:ok, %U{ks: :primary}} = U.parse("ks-level1")
      assert {:ok, %U{kv: :space}} = U.parse("kv-space")
    end

    test "decodes a kr reorder list" do
      assert {:ok, %U{kr: [:Latn, :digit]}} = U.parse("kr-latn-digit")
    end

    test "decodes dictionary break exclusion scripts" do
      assert {:ok, %U{dx: :Thai}} = U.parse("dx-thai")
    end

    test "decodes region and subdivision overrides" do
      assert {:ok, %U{rg: :US}} = U.parse("rg-uszzzz")
      assert {:ok, %U{rg: :gbeng}} = U.parse("rg-gbeng")
      assert {:ok, %U{sd: :usca}} = U.parse("sd-usca")
    end

    test "resolves timezone ids to canonical IANA names" do
      assert {:ok, %U{tz: "Australia/Sydney"}} = U.parse("tz-ausyd")
      # est5edt is deprecated; it resolves through usnyc.
      assert {:ok, %U{tz: "America/New_York"}} = U.parse("tz-est5edt")
    end

    test "returns an InvalidSubtagError for an invalid keyword value" do
      assert {:error, %Localize.InvalidSubtagError{key: "hc", value: "h25"}} =
               U.parse("hc-h25")
    end
  end

  describe "to_string/1" do
    test "renders multiple keywords sorted by key" do
      {:ok, u} = U.parse("nu-thai-tz-ausyd-ca-buddhist")
      assert U.to_string(u) == "ca-buddhist-nu-thai-tz-ausyd"
      assert to_string(u) == "ca-buddhist-nu-thai-tz-ausyd"
    end

    test "renders an empty map as an empty string" do
      assert U.to_string(%{}) == ""
    end
  end

  describe "round trip through validate_locale/1" do
    test "canonical_locale_id resolves deprecated timezone ids" do
      {:ok, tag} = Localize.validate_locale("en-u-tz-est5edt")
      assert tag.canonical_locale_id == "en-u-tz-usnyc"
    end

    test "canonical_locale_id prefers islamic-civil over islamicc" do
      {:ok, tag} = Localize.validate_locale("en-u-ca-islamicc")
      assert tag.canonical_locale_id == "en-u-ca-islamic-civil"
    end

    test "keyword order is canonicalized alphabetically" do
      {:ok, tag} = Localize.validate_locale("en-u-nu-latn-cu-usd")
      assert tag.canonical_locale_id == "en-u-cu-usd-nu-latn"
    end
  end

  describe "Validity.U decode/encode (used directly by consumers such as Tempo)" do
    alias Localize.Validity.U, as: Validity

    test "decode accepts struct-field atom keys and BCP 47 string keys" do
      assert {:ok, {:ca, :islamic_civil}} = Validity.decode(:ca, "islamic_civil")
      assert {:ok, {:ca, :islamic_civil}} = Validity.decode("ca", "islamic_civil")
    end

    test "decode accepts the canonical hyphenated calendar spelling" do
      assert {:ok, {:ca, :islamic_civil}} = Validity.decode(:ca, "islamic-civil")
      assert {:ok, {:ca, :islamic_umalqura}} = Validity.decode(:ca, "islamic-umalqura")
    end

    test "decode folds deprecated spellings into the canonical atom" do
      assert {:ok, {:ca, :islamic_civil}} = Validity.decode("ca", "islamicc")
      assert {:ok, {:ca, :ethiopic_amete_alem}} = Validity.decode("ca", "ethioaa")
    end

    test "encode accepts atom and string keys" do
      assert {"hc", "h23"} = Validity.encode(:hc, :h23)
      assert {"hc", "h23"} = Validity.encode("hc", :h23)
    end

    test "encode emits the preferred BCP 47 spelling" do
      assert {"ca", "islamic-civil"} = Validity.encode(:ca, :islamic_civil)
      assert {"ca", "gregory"} = Validity.encode(:ca, :gregorian)
    end
  end
end
