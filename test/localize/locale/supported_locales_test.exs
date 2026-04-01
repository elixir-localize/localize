defmodule Localize.Locale.SupportedLocalesTest do
  use ExUnit.Case, async: false

  setup do
    original_supported = Localize.supported_locales()

    on_exit(fn ->
      Localize.put_supported_locales(original_supported)
    end)

    :ok
  end

  describe "supported_locales/0" do
    test "returns all locale IDs when persistent_term is not set" do
      :persistent_term.erase({:localize, :supported_locales})
      assert Localize.supported_locales() == Localize.all_locale_ids()
    end

    test "returns the list set by put_supported_locales/1" do
      Localize.put_supported_locales([:en, :fr, :de])

      result = Localize.supported_locales()
      assert is_list(result)
      assert :en in result
      assert :fr in result
      assert :de in result
    end

    test "returns empty list when set to empty list" do
      Localize.put_supported_locales([])
      assert Localize.supported_locales() == []
    end
  end

  describe "validate_locale with supported_locales" do
    test "resolves en-AU to :en when only :en is supported" do
      Localize.put_supported_locales([:en, :fr, :de])

      {:ok, tag} = Localize.validate_locale("en-AU")
      assert tag.cldr_locale_id == :en
    end

    test "resolves en-AU to :en-AU when en-AU is supported" do
      Localize.put_supported_locales([:en, :"en-AU", :fr])

      {:ok, tag} = Localize.validate_locale("en-AU")
      assert tag.cldr_locale_id == :"en-AU"
    end

    test "resolves fr-CA to :fr when only :fr is supported" do
      Localize.put_supported_locales([:en, :fr, :de])

      {:ok, tag} = Localize.validate_locale("fr-CA")
      assert tag.cldr_locale_id == :fr
    end

    test "resolves to all CLDR locales when supported_locales is not set" do
      # Use all_locale_ids to restore the full set, which also clears the cache
      Localize.put_supported_locales(Localize.all_locale_ids())

      {:ok, tag} = Localize.validate_locale("en-AU")
      assert tag.cldr_locale_id == :"en-AU"
    end
  end
end
