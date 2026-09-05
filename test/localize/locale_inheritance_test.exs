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
end
