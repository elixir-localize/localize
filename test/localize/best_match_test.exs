defmodule Localize.BestMatchTest do
  use ExUnit.Case, async: true

  alias Localize.LanguageTag

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

    test "returns error when no match within explicit threshold" do
      # With a threshold below the default, no fallback occurs —
      # the function returns an error if nothing matches.
      assert {:error, _} = LanguageTag.best_match("zh", ["en", "fr"], 5)
    end

    test "returns default locale when no match within default threshold" do
      # With the default threshold (80), the CLDR algorithm always
      # returns a result — the first supported locale as fallback.
      assert {:ok, "en", _} = LanguageTag.best_match("zh", ["en", "fr"])
    end

    test "returns error for empty supported list" do
      assert {:error, _} = LanguageTag.best_match("zh", [], 5)
    end

    test "respects custom distance threshold" do
      # gsw → de has distance ~8, so threshold 5 rejects it
      assert {:error, _} = LanguageTag.best_match("gsw", ["de"], 5)
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

  describe "best_match/3 tie-breaking" do
    # The distance trie scores every candidate sharing the desired
    # script and territory identically, so these would otherwise be
    # decided by whichever the caller happened to list first.

    test "prefers the territory's own language over another language in that territory" do
      # Samogitian is spoken in Lithuania; `lt` and `en-LT` are both 80 away.
      assert {:ok, "lt", 80} = LanguageTag.best_match("sgs", ["en-LT", "lt"])
    end

    test "the tie-break is independent of the order of the supported list" do
      assert {:ok, "lt", 80} = LanguageTag.best_match("sgs", ["lt", "en-LT"])
      assert {:ok, "lt", 80} = LanguageTag.best_match("sgs", ["en-LT", "lt"])
    end

    test "applies to Livonian in Latvia" do
      assert {:ok, "lv", 80} = LanguageTag.best_match("liv", ["en-LV", "lv"])
    end

    test "does not override a genuinely closer match" do
      # `lt-LT` is no further away than `lt`, but neither beats an exact match.
      assert {:ok, "sgs", 0} = LanguageTag.best_match("sgs", ["en-LT", "lt", "sgs"])
    end

    test "leaves list order deciding when no candidate is the territory language" do
      # Neither `fr` nor `de` is the predominant language of Lithuania.
      assert {:ok, "fr", _} = LanguageTag.best_match("sgs", ["fr", "de"])
      assert {:ok, "de", _} = LanguageTag.best_match("sgs", ["de", "fr"])
    end

    test "a desired locale that maximizes to no territory still matches" do
      assert {:ok, _match, _score} = LanguageTag.best_match("und-Cyrl", ["ru", "en"])
    end
  end

  # The root locale in the supported list matches a desired root and
  # nothing else. `Localize.supported_locales/0` always holds it, as the
  # atom `:und`; scored as a candidate it maximizes to `en-Latn-US`, an
  # exact match for `en` and `en-US`, so a configuration whose only
  # English locale was `en-GB` resolved English to `:und` (#71).
  describe "best_match/3 with the root locale in the supported list" do
    test "en and en-US match en-GB, not the root, wherever the root is listed" do
      for desired <- [:en, :"en-US", :"en-AU", :"en-CA"], supported <- root_placements() do
        assert {:ok, :"en-GB", score} = LanguageTag.best_match(desired, supported),
               "#{inspect(desired)} in #{inspect(supported)}"

        assert score < LanguageTag.default_distance()
      end
    end

    test "every form of the root is kept out of the candidates" do
      for root <- root_forms() do
        assert {:ok, :"en-GB", 5} = LanguageTag.best_match(:en, [:"en-GB", :fi, root]),
               inspect(root)

        assert {:ok, :"en-GB", 5} = LanguageTag.best_match(:en, [root, :"en-GB", :fi]),
               inspect(root)
      end
    end

    test "a locale with no near match falls back to the first locale that is not the root" do
      for root <- root_forms() do
        assert {:ok, :"en-GB", 80} = LanguageTag.best_match(:zh, [root, :"en-GB", :fi]),
               inspect(root)
      end
    end

    test "a strict threshold does not return the root for another locale" do
      for root <- root_forms() do
        assert {:error, %Localize.LocaleMatchError{}} =
                 LanguageTag.best_match(:en, [:fi, root], 0),
               inspect(root)
      end
    end

    test "a desired root matches the root as the caller listed it" do
      for desired <- [:und, :root, "und", "root"], root <- root_forms() do
        assert {:ok, ^root, 0} = LanguageTag.best_match(desired, [:"en-GB", :fi, root]),
               "#{inspect(desired)} in #{inspect(root)}"
      end
    end

    test "a desired root with no root listed takes the first supported locale" do
      assert {:ok, :"en-GB", 80} = LanguageTag.best_match(:und, [:"en-GB", :fi])
    end

    test "a list of the root alone matches no other locale" do
      for root <- root_forms() do
        assert {:error, %Localize.LocaleMatchError{}} = LanguageTag.best_match(:en, [root]),
               inspect(root)
      end
    end

    # The invariant behind all of the above: adding the root to a
    # supported list changes the match of no other locale.
    test "adding the root changes the match of no installed locale" do
      desired_locales = Localize.Test.InstalledLocales.all() -- [:und]

      for supported <- supported_sets(), desired <- desired_locales do
        expected = LanguageTag.best_match(desired, supported)
        label = "#{inspect(desired)} in #{inspect(supported)}"

        assert LanguageTag.best_match(desired, supported ++ [:und]) == expected, label
        assert LanguageTag.best_match(desired, [:und | supported]) == expected, label
        refute match?({:ok, :und, _score}, expected), label
      end
    end
  end

  defp root_placements do
    [
      [:"en-GB", :"sv-FI", :fi, :und],
      [:und, :"en-GB", :"sv-FI", :fi],
      [:"en-GB", :und, :"sv-FI", :fi],
      [:"en-GB", :"sv-FI", :fi]
    ]
  end

  defp root_forms do
    {:ok, root_tag} = Localize.validate_locale(:und)
    [:und, :root, "und", "root", root_tag]
  end

  defp supported_sets do
    [
      [:"en-GB", :"sv-FI", :fi],
      [:"en-AU", :fr],
      [:"fr-CA", :"pt-PT", :"zh-Hant"],
      [:de, :ja, :ar],
      [:"es-MX"]
    ]
  end
end
