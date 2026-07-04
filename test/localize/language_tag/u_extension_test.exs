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
