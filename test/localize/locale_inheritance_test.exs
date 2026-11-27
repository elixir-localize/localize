defmodule Localize.LocaleInheritanceTest do
  use ExUnit.Case, async: true

  alias Localize.LanguageTag
  alias Localize.Locale

  describe "parent/1" do
    test "standard territory inheritance strips territory" do
      {:ok, parent} = Locale.parent("en-AU")
      assert parent.language == :en
      assert parent.territory == :"001"
    end

    test "standard region-group inheritance strips to language" do
      {:ok, parent} = Locale.parent("en-001")
      assert parent.language == :en
      assert parent.territory == nil
    end

    test "language-only locale inherits from und" do
      {:ok, parent} = Locale.parent("en")
      assert parent.language == :und
    end

    test "und (root) has no parent" do
      assert {:error, %Localize.NoParentError{}} = Locale.parent("und")
    end

    # CLDR's parent locales: `en-AU` inherits from `en-001`, which inherits
    # from `en`, which inherits from root. Each parent names its CLDR
    # locale, so no caller has to validate it again, and keeps the child's
    # extensions.
    test "each parent carries its CLDR locale id" do
      {:ok, tag} = Localize.validate_locale("en-AU-u-nu-arab")

      chain =
        Stream.unfold(tag, fn tag ->
          case Locale.parent(tag) do
            {:ok, parent} -> {parent, parent}
            {:error, %Localize.NoParentError{}} -> nil
          end
        end)
        |> Enum.to_list()

      assert Enum.map(chain, & &1.cldr_locale_id) == [:"en-001", :en, :und]
      assert Enum.all?(chain, &(&1.locale.nu == :arab))
    end

    # CLDR 49 removed `<parentLocale parent="fr_HT" locales="ht"/>` (it also
    # dropped `ht` from the coverage levels), so Haitian Creole no longer
    # inherits French. It is asserted here rather than simply deleted because
    # a silent return of the mapping would change resolution for every `ht`
    # lookup, and we would want to see that.
    test "ht no longer inherits from fr-HT (CLDR 49)" do
      {:ok, parent} = Locale.parent("ht")
      assert parent.language == :und
    end

    test "non-standard parent from CLDR parentLocales data" do
      {:ok, parent} = Locale.parent("nb")
      assert parent.language == :no

      {:ok, parent} = Locale.parent("zh-Hant-MO")
      assert parent.language == :zh
      assert parent.script == :Hant
      assert parent.territory == :HK

      {:ok, parent} = Locale.parent("es-AR")
      assert parent.language == :es
      assert parent.territory == :"419"

      {:ok, parent} = Locale.parent("pt-AO")
      assert parent.language == :pt
      assert parent.territory == :PT
    end

    test "non-standard script locale inherits from und" do
      {:ok, parent} = Locale.parent("sr-Latn")
      assert parent.language == :und
    end

    test "extensions are transferred to parent" do
      {:ok, parent} = Locale.parent("en-AU-u-ca-buddhist")
      assert parent.language == :en
      assert parent.territory == :"001"
      assert parent.locale != %{}

      canonical = LanguageTag.to_string(parent)
      assert canonical =~ "u-ca-buddhist"
    end

    test "accepts a LanguageTag struct" do
      {:ok, tag} = LanguageTag.new("en-AU")
      {:ok, parent} = Locale.parent(tag)
      assert parent.language == :en
      assert parent.territory == :"001"
    end

    test "script-territory locale strips territory first" do
      {:ok, parent} = Locale.parent("zh-Hant-TW")
      # zh-Hant-TW is not in parent_locales, so strip territory → zh-Hant
      assert parent.language == :zh
      assert parent.script == :Hant
      assert parent.territory == nil
    end

    test "full inheritance chain from en-AU to und" do
      chain =
        Stream.unfold("en-AU", fn locale ->
          case Locale.parent(locale) do
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
          case Locale.parent(locale) do
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

  # A validated tag names the CLDR locale whose data it uses, so each
  # ancestor must name its own, following CLDR's locale inheritance:
  # ar-SA's parent is ar, not ar-SA again.
  describe "parent/1 of a validated tag" do
    # A parent built by stripping subtags from a validated child must not keep
    # the child's CLDR locale id: `PersistentTerm.get/3` reads `cldr_locale_id`
    # straight out of a tag rather than re-resolving it, so a stale id would
    # read the child's data for the parent (#48). Main resolves this already;
    # these pin it.
    test "resolves the parent's own CLDR locale id, not the child's" do
      for {locale, parent_id} <- [{:"fr-CA", :fr}, {:"de-AT", :de}, {:"ar-SA", :ar}] do
        {:ok, tag} = Localize.validate_locale(locale)
        {:ok, parent} = Locale.parent(tag)

        assert Locale.cldr_locale_id_from(parent) == {:ok, parent_id},
               "the parent of #{locale} did not resolve to #{inspect(parent_id)}"
      end
    end

    test "spells a number with the rules of the parent its data comes from" do
      assert Localize.Number.to_string(21, format: :spellout, locale: :"fr-CA") ==
               {:ok, "vingt-et-un"}
    end

    # Each CLDR locale appears once: the walk truncated the maximized
    # subtags (`ar-Arab-SA`, `ar-Arab`, `ar`), so `ar` was reached twice.
    test "a parent found by dropping a subtag resolves its own CLDR locale" do
      for {locale, expected} <- [
            {"ar-SA", [:ar, :und]},
            {"de-AT", [:de, :und]},
            {"fr-CA", [:fr, :und]},
            {"es-419", [:es, :und]},
            {"zh-Hant-HK", [:"zh-Hant", :und]},
            {"ca-ES-valencia", [:ca, :und]},
            {"ar-SA-u-nu-latn", [:ar, :und]}
          ] do
        {:ok, tag} = Localize.validate_locale(locale)
        assert cldr_chain(tag) == expected, locale
      end
    end

    test "a parent from CLDR's parent locales is unchanged" do
      for {locale, expected} <- [
            {"es-MX", [:"es-419", :es, :und]},
            {"en-AU", [:"en-001", :en, :und]},
            {"pt-AO", [:"pt-PT", :pt, :und]},
            {"zh-Hant-MO", [:"zh-Hant-HK", :"zh-Hant", :und]}
          ] do
        {:ok, tag} = Localize.validate_locale(locale)
        assert cldr_chain(tag) == expected, locale
      end
    end

    test "a tag whose data is root's walks to root, not to its likely subtags" do
      # A validated und carries the likely subtags en-Latn-US.
      for locale <- ["und", "root", "tlh"] do
        {:ok, tag} = Localize.validate_locale(locale)
        assert cldr_chain(tag) == [:und], locale
      end
    end

    # A validated tag's subtags are maximized: `az` is `az-Latn-AZ`, and
    # truncating them named `az`'s own child `az-Latn` as its parent.
    test "is read as the CLDR locale it resolved to" do
      for {locale, expected} <- [
            {"az", [:und]},
            {"pa", [:und]},
            {"kk-KZ", [:kk, :und]},
            {"zh-TW", [:und]},
            {"sr-ME", [:"sr-Latn", :und]}
          ] do
        {:ok, tag} = Localize.validate_locale(locale)
        assert {locale, cldr_chain(tag)} == {locale, expected}
      end
    end

    test "walks the same chain as fallback_chain/2 for every CLDR locale" do
      for locale_id <- Localize.SupplementalData.all_locale_ids(), locale_id != :und do
        {:ok, tag} = Localize.LanguageTag.new(Atom.to_string(locale_id))
        {:ok, [^locale_id | parents]} = Locale.fallback_chain(locale_id)

        assert {locale_id, cldr_chain(tag)} == {locale_id, parents ++ [:und]}
      end
    end
  end

  describe "parent/2 with a component" do
    test "takes the component's own parents" do
      for {locale, parent} <- [{"yue", "zh-Hant"}, {"yue-Hans", "zh-Hans"}, {"yue-CN", "zh-Hans"}] do
        assert {:ok, tag} = Locale.parent(locale, component: :collations)
        assert {locale, LanguageTag.to_string(tag)} == {locale, parent}
      end
    end

    # TR35: component parents "are now not merged, but instead are treated
    # as stand-alone", and the non-likely-script rule is for the main
    # component only.
    test "reads the component's parents on their own, without the main ones" do
      for {locale, component, parent} <- [
            {"zh-Hant", :collations, "zh"},
            {"sr-Latn", :collations, "sr"},
            {"hi-Latn", :collations, "hi"},
            {"es-AR", :plurals, "es"},
            {"en-AU", :plurals, "en"},
            {"pt-AO", :grammatical_features, "pt"},
            {"az-Cyrl", :segmentations, "az"}
          ] do
        assert {:ok, tag} = Locale.parent(locale, component: component)
        assert {locale, component, LanguageTag.to_string(tag)} == {locale, component, parent}
      end
    end

    # CLDR lists `nb` and `nn` → `no` in the main component only; the data
    # pass adds them to `collations` as a marked correction of that gap.
    test "takes nb and nn to no for collations, by the marked correction" do
      for locale <- ["nb", "nn"] do
        assert {:ok, tag} = Locale.parent(locale, component: :collations)
        assert {locale, LanguageTag.to_string(tag)} == {locale, "no"}
      end
    end

    test "is the main component by default" do
      for locale <- ["en-AU", "zh-Hant", "nb", "yue"] do
        assert Locale.parent(locale) == Locale.parent(locale, component: :main), locale
      end
    end

    test "reaches the root from every CLDR locale, without a cycle, for every component" do
      for component <- [:collations, :grammatical_features, :plurals, :segmentations],
          locale_id <- Localize.SupplementalData.all_locale_ids(),
          locale_id != :und do
        chain = string_chain(Atom.to_string(locale_id), component: component)

        assert {component, locale_id, List.last(chain)} == {component, locale_id, "und"}
        assert {component, locale_id, Enum.uniq(chain)} == {component, locale_id, chain}
      end
    end

    test "is an error for a component that is not one, or options that are not a list" do
      assert {:error, %Localize.InvalidValueError{expected: :component}} =
               Locale.parent("en-AU", component: :numbers)

      assert {:error, %Localize.InvalidValueError{expected: :component}} =
               Locale.parent("en-AU", component: "collations")

      assert {:error, %Localize.InvalidValueError{}} =
               Locale.parent("en-AU", %{component: :collations})
    end
  end

  describe "parent/1 follows TR35" do
    test "gives the root for a script that is not the language's likely script" do
      for locale <- ["ru-Latn", "en-Cyrl", "ja-Latn", "el-Latn", "sr-Latn", "zh-Hant", "az-Cyrl"] do
        assert {:ok, %LanguageTag{language: :und, script: nil, territory: nil}} =
                 Locale.parent(locale),
               locale
      end
    end

    test "gives the root for every language and script CLDR uses where the script is not likely" do
      tags =
        for id <- Localize.SupplementalData.all_locale_ids(),
            do: LanguageTag.new!(Atom.to_string(id))

      languages =
        tags
        |> Enum.map(& &1.language)
        |> Enum.uniq()

      scripts =
        tags
        |> Enum.map(& &1.script)
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()

      listed = Localize.SupplementalData.parent_locales()

      for language <- languages, language != :und, script <- scripts do
        name = "#{language}-#{script}"
        {:ok, parent} = Locale.parent(name)

        assert {name, LanguageTag.to_string(parent)} ==
                 {name, Map.get(listed, name, unlisted_parent(language, script))}
      end
    end

    test "truncates a language's likely script" do
      for {locale, parent} <- [{"ru-Cyrl", "ru"}, {"sr-Cyrl", "sr"}, {"zh-Hans", "zh"}] do
        assert {:ok, tag} = Locale.parent(locale)
        assert {locale, LanguageTag.to_string(tag)} == {locale, parent}
      end
    end

    test "gives every locale CLDR lists under the non-likely-script rule a script the rule gives" do
      for {name, "und"} <- Localize.SupplementalData.parent_locales(),
          [language, script] <- [String.split(name, "-")],
          String.length(script) == 4 do
        {:ok, tag} = LanguageTag.new(language)
        assert {name, Atom.to_string(tag.script) != script} == {name, true}
      end
    end

    test "reads a script likely subtags imply as absent when looking up CLDR's parent locales" do
      for {locale, parent} <- [
            {"en-Latn-RO", "en-150"},
            {"es-Latn-BR", "es-419"},
            {"pt-Latn-AO", "pt-PT"}
          ] do
        assert {:ok, tag} = Locale.parent(locale)
        assert {locale, LanguageTag.to_string(tag)} == {locale, parent}
      end
    end

    test "truncates a script that is not implied, rather than dropping it" do
      assert {:ok, tag} = Locale.parent("sr-Latn-ME")
      assert LanguageTag.to_string(tag) == "sr-Latn"
    end

    test "drops one variant at a time" do
      assert {:ok, tag} = Locale.parent("sl-biske-rozaj")
      assert [_one_variant] = tag.language_variants

      assert {:ok, tag} = Locale.parent("ca-ES-valencia")
      assert LanguageTag.to_string(tag) == "ca-ES"
    end

    test "takes a locale id atom" do
      assert {:ok, tag} = Locale.parent(:"en-AU")
      assert LanguageTag.to_string(tag) == "en-001"
    end

    test "reaches the root from every CLDR locale, without a cycle" do
      for locale_id <- Localize.SupplementalData.all_locale_ids(), locale_id != :und do
        chain = string_chain(Atom.to_string(locale_id))

        assert {locale_id, List.last(chain)} == {locale_id, "und"}
        assert {locale_id, Enum.uniq(chain)} == {locale_id, chain}
      end
    end

    test "keeps the child's likely script, or gives the root" do
      for locale_id <- Localize.SupplementalData.all_locale_ids(), locale_id != :und do
        name = Atom.to_string(locale_id)
        {:ok, parent} = Locale.parent(name)
        parent_name = LanguageTag.to_string(parent)

        if parent_name != "und" do
          assert {name, likely_script(parent_name)} == {name, likely_script(name)}
        end
      end
    end
  end

  defp string_chain(name, options \\ []) do
    name
    |> Stream.unfold(fn name ->
      case Locale.parent(name, options) do
        {:ok, parent} ->
          parent_name = LanguageTag.to_string(parent)
          {parent_name, parent_name}

        {:error, _reason} ->
          nil
      end
    end)
    |> Enum.take(12)
  end

  # A language and script CLDR does not list: the language where the script
  # is its likely one, the root otherwise.
  defp unlisted_parent(language, script) do
    if LanguageTag.new!(Atom.to_string(language)).script == script do
      Atom.to_string(language)
    else
      "und"
    end
  end

  defp likely_script(name) do
    {:ok, tag} = LanguageTag.new(name)
    tag.script
  end

  # The CLDR locale of each ancestor of a tag, up to the root.
  defp cldr_chain(tag) do
    tag
    |> Stream.unfold(fn tag ->
      case Locale.parent(tag) do
        {:ok, parent} ->
          {:ok, locale_id} = Locale.cldr_locale_id_from(parent)
          {locale_id, parent}

        {:error, _reason} ->
          nil
      end
    end)
    |> Enum.to_list()
  end
end

defmodule Localize.LocaleInheritanceAtomTest do
  # Not async: counting atoms needs no other test making atoms meanwhile.
  use ExUnit.Case, async: false

  test "parent/1 makes no atom from the locale it is given" do
    # One locale of each shape first, so data read on first use is loaded
    # before counting.
    for locale <- ["ru-Latn", "en-x-parentwarm", "zzwarm-Latn", "en-Latn-QW"] do
      Localize.Locale.parent(locale)
    end

    locales =
      for index <- 1..500, do: ["en-x-parent#{index}", "zz#{index}-Latn", "en-Latn-Q#{index}"]

    before = :erlang.system_info(:atom_count)

    for locale <- List.flatten(locales) do
      Localize.Locale.parent(locale)
    end

    assert :erlang.system_info(:atom_count) == before
  end
end

defmodule Localize.LocaleInheritanceConfiguredTest do
  # Changes the supported locales for the whole node, so it runs alone.
  use ExUnit.Case, async: false

  setup do
    original_supported = Localize.supported_locales()
    on_exit(fn -> Localize.put_supported_locales(original_supported) end)
  end

  # A parent's `:cldr_locale_id` names a configured locale, so reading a
  # tag by it sent RBNF's walk round in a cycle.
  test "every validated tag's parents reach the root under a restricted configuration" do
    :ok = Localize.put_supported_locales([:en, :fr, :nb])

    for locale_id <- Localize.SupplementalData.all_locale_ids() do
      {:ok, tag} = Localize.validate_locale(locale_id)
      chain = walk(tag)

      assert {locale_id, Enum.count_until(chain, 8) < 8} == {locale_id, true}
      assert {locale_id, List.last(chain)} == {locale_id, :und}
    end
  end

  defp walk(tag) do
    tag
    |> Stream.unfold(fn tag ->
      case Localize.Locale.parent(tag) do
        {:ok, parent} -> {parent.cldr_locale_id, parent}
        {:error, _reason} -> nil
      end
    end)
    |> Enum.take(8)
  end
end
