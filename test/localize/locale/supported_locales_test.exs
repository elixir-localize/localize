defmodule Localize.Locale.SupportedLocalesTest do
  use ExUnit.Case, async: false

  setup do
    original_supported = Localize.supported_locales()

    on_exit(fn ->
      Localize.put_supported_locales(original_supported)
    end)

    %{original_supported: original_supported}
  end

  describe "supported_locales/0" do
    test "returns all locale IDs when persistent_term is not set", context do
      :persistent_term.erase({:localize, :supported_locales})
      assert Localize.supported_locales() == Localize.all_locale_ids()
      Localize.put_supported_locales(context.original_supported)
    end

    test "returns the list set by put_supported_locales/1", context do
      Localize.put_supported_locales([:en, :fr, :de])

      result = Localize.supported_locales()
      assert is_list(result)
      assert :en in result
      assert :fr in result
      assert :de in result
      Localize.put_supported_locales(context.original_supported)
    end

    test "returns empty list when set to empty list", context do
      Localize.put_supported_locales([])
      assert Localize.supported_locales() == []
      Localize.put_supported_locales(context.original_supported)
    end
  end

  describe "validate_locale with supported_locales" do
    test "resolves en-AU to :en when only :en is supported", context do
      Localize.put_supported_locales([:en, :fr, :de])

      {:ok, tag} = Localize.validate_locale("en-AU")
      assert tag.cldr_locale_id == :en
      Localize.put_supported_locales(context.original_supported)
    end

    test "resolves en-AU to :en-AU when en-AU is supported", context do
      Localize.put_supported_locales([:en, :"en-AU", :fr])

      {:ok, tag} = Localize.validate_locale("en-AU")
      assert tag.cldr_locale_id == :"en-AU"
      Localize.put_supported_locales(context.original_supported)
    end

    test "resolves fr-CA to :fr when only :fr is supported", context do
      Localize.put_supported_locales([:en, :fr, :de])

      {:ok, tag} = Localize.validate_locale("fr-CA")
      assert tag.cldr_locale_id == :fr
      Localize.put_supported_locales(context.original_supported)
    end

    test "resolves to all CLDR locales when supported_locales is not set", context do
      Localize.put_supported_locales(Localize.all_locale_ids())

      {:ok, tag} = Localize.validate_locale("en-AU")
      assert tag.cldr_locale_id == :"en-AU"
      Localize.put_supported_locales(context.original_supported)
    end
  end
end
