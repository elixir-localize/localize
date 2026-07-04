defmodule Localize.Validity.TTest do
  use ExUnit.Case, async: true

  alias Localize.Validity.T
  alias Localize.Validity.T.Fields

  describe "fields/0 and field_mapping/0" do
    test "fields covers every t extension key" do
      assert T.fields() == [:d0, :h0, :i0, :k0, :language, :m0, :s0, :t0, :x0]
    end

    test "field_mapping maps BCP 47 string keys to struct field atoms" do
      mapping = T.field_mapping()
      assert mapping["m0"] == :m0
      assert mapping["language"] == :language
      assert map_size(mapping) == 9
    end

    test "Fields.inverse_field_mapping/0 inverts the field mapping" do
      inverse = Fields.inverse_field_mapping()
      assert inverse[:m0] == "m0"
      assert inverse[:language] == "language"
      assert map_size(inverse) == map_size(Fields.field_mapping())
    end
  end

  describe "decode/2 with mechanism and keyboard keys" do
    test "decodes a valid m0 mechanism value" do
      assert T.decode("m0", "ungegn") == {:ok, {:m0, :ungegn}}
    end

    test "decodes a valid d0 destination value" do
      assert T.decode("d0", "ascii") == {:ok, {:d0, :ascii}}
    end

    test "decodes a valid s0 source value" do
      assert T.decode("s0", "accents") == {:ok, {:s0, :accents}}
    end

    test "decodes a valid i0 input method value" do
      assert T.decode("i0", "pinyin") == {:ok, {:i0, :pinyin}}
    end

    test "decodes a valid k0 keyboard value" do
      assert T.decode("k0", "dvorak") == {:ok, {:k0, :dvorak}}
    end

    test "decodes a valid h0 hybrid value" do
      assert T.decode("h0", "hybrid") == {:ok, {:h0, :hybrid}}
    end

    test "decodes a valid t0 machine translation value" do
      assert T.decode("t0", "und") == {:ok, {:t0, :und}}
    end

    test "returns an InvalidSubtagError for an invalid value" do
      assert {:error, %Localize.InvalidSubtagError{} = exception} = T.decode("m0", "bogus")
      assert exception.key == "m0"
      assert exception.value == "bogus"
    end

    test "returns an InvalidSubtagError for an unknown key" do
      assert {:error, %Localize.InvalidSubtagError{key: "q9"}} = T.decode("q9", "whatever")
    end
  end

  describe "decode/2 with date subtags" do
    test "decodes a year-only date to a 1-tuple" do
      assert T.decode("m0", "2007") == {:ok, {:m0, {2007}}}
    end

    test "decodes a year-month date to a 2-tuple" do
      assert T.decode("m0", "200703") == {:ok, {:m0, {2007, 3}}}
    end

    test "decodes a full date to a 3-tuple" do
      assert T.decode("m0", "20070315") == {:ok, {:m0, {2007, 3, 15}}}
    end

    test "decodes a value list with a trailing date" do
      assert T.decode("m0", ["ungegn", "2007"]) == {:ok, {:m0, [:ungegn, {2007}]}}
    end

    test "rejects a value list where the date is not last" do
      assert {:error, %Localize.InvalidSubtagError{key: "m0"}} =
               T.decode("m0", ["2007", "ungegn"])
    end

    test "rejects a value list containing an invalid value" do
      assert {:error, %Localize.InvalidSubtagError{key: "m0"}} =
               T.decode("m0", ["ungegn", "bogus"])
    end
  end

  describe "decode/2 with language and private use keys" do
    test "passes through an already parsed language tag" do
      {:ok, language_tag} = Localize.LanguageTag.parse("it")
      assert T.decode("language", {:ok, language_tag}) == {:ok, {:language, language_tag}}
    end

    test "propagates a language parse error" do
      error = {:error, :bad_tag}
      assert T.decode("language", error) == {:error, :bad_tag}
    end

    test "passes through x0 private use values" do
      assert T.decode("x0", ["foo", "bar"]) == {:ok, {:x0, ["foo", "bar"]}}
    end
  end

  describe "encode/2" do
    test "encodes an atom value back to its BCP 47 string" do
      assert T.encode(:m0, :ungegn) == {"m0", "ungegn"}
      assert T.encode(:h0, :hybrid) == {"h0", "hybrid"}
    end

    test "encodes an x0 private use list as hyphen-joined subtags" do
      assert T.encode(:x0, ["foo", "bar"]) == {"x0", "foo-bar"}
    end

    test "encodes a value list including a year-only date" do
      assert T.encode(:m0, [:ungegn, {2007}]) == {"m0", "ungegn-2007"}
    end

    test "encodes a nil language as nil" do
      assert T.encode(:language, nil) == {"language", nil}
    end

    test "encodes a language tag value as its downcased string form" do
      {:ok, language_tag} = Localize.LanguageTag.parse("en-US")
      assert T.encode(:language, language_tag) == {"language", "en-us"}
    end
  end

  describe "valid_list/2" do
    test "accumulates valid values in reverse order" do
      assert T.valid_list("m0", ["ungegn", "bgn"]) == {:ok, [:bgn, :ungegn]}
    end

    test "returns a date-order error when a date precedes another value" do
      assert {:error, %Localize.InvalidSubtagError{reason: :date_not_last}} =
               T.valid_list("m0", ["2007", "ungegn"])
    end
  end

  describe "wrap/2" do
    test "wraps a term in a tagged tuple" do
      assert T.wrap([:a], :ok) == {:ok, [:a]}
    end
  end
end
