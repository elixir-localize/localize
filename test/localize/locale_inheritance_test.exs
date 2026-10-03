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
    test "a parent found by dropping a subtag resolves its own CLDR locale" do
      for {locale, expected} <- [
            {"ar-SA", [:ar, :ar, :und]},
            {"de-AT", [:de, :de, :und]},
            {"fr-CA", [:fr, :fr, :und]},
            {"es-419", [:es, :es, :und]},
            {"zh-Hant-HK", [:"zh-Hant", :und]},
            {"ca-ES-valencia", [:ca, :ca, :ca, :und]},
            {"ar-SA-u-nu-latn", [:ar, :ar, :und]}
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
