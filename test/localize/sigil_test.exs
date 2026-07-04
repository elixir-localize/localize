defmodule Localize.SigilTest do
  use ExUnit.Case, async: true

  import Localize.LanguageTag.Sigil

  describe "~l with full canonicalization" do
    test "produces a validated language tag with likely subtags resolved" do
      tag = ~l(en-US-u-ca-gregory)

      assert tag.language == :en
      assert tag.territory == :US
      assert tag.canonical_locale_id == "en-US-u-ca-gregory"
      assert tag.locale.ca == :gregorian
    end
  end

  describe "~l with the u modifier" do
    test "parses without canonicalization or likely subtags" do
      tag = ~l(en)u

      assert tag.requested_locale_id == "en"
      assert tag.canonical_locale_id == nil
      assert tag.script == nil
      assert tag.territory == nil
    end
  end

  describe "error handling" do
    test "raises ParseError for an invalid tag" do
      assert_raise Localize.ParseError, fn ->
        Code.eval_string("import Localize.LanguageTag.Sigil; ~l(zz-ZZZZ-!!)")
      end
    end

    test "raises ParseError for an invalid tag with the u modifier" do
      assert_raise Localize.ParseError, fn ->
        Code.eval_string("import Localize.LanguageTag.Sigil; ~l(no!good)u")
      end
    end
  end
end
