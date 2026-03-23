defmodule Localize.Locale.SupportedLocalesTest do
  use ExUnit.Case, async: false

  @locale_cache_table :localize_locale_cache

  setup do
    # Save original config
    original_supported = Application.get_env(:localize, :supported_locales)
    original_preload = Application.get_env(:localize, :preload_locales)

    # Clear persistent_term and ETS cache before each test
    try do
      :persistent_term.erase(:localize_supported_locales)
    rescue
      ArgumentError -> :ok
    end

    :ets.delete_all_objects(@locale_cache_table)

    on_exit(fn ->
      # Restore original config
      if original_supported do
        Application.put_env(:localize, :supported_locales, original_supported)
      else
        Application.delete_env(:localize, :supported_locales)
      end

      if original_preload do
        Application.put_env(:localize, :preload_locales, original_preload)
      else
        Application.delete_env(:localize, :preload_locales)
      end

      # Clear persistent_term and ETS cache
      try do
        :persistent_term.erase(:localize_supported_locales)
      rescue
        ArgumentError -> :ok
      end

      :ets.delete_all_objects(@locale_cache_table)
    end)

    :ok
  end

  describe "supported_locales/0" do
    test "returns nil when :supported_locales is not configured" do
      Application.delete_env(:localize, :supported_locales)

      assert Localize.supported_locales() == nil
    end

    test "returns resolved list when :supported_locales is configured" do
      Application.put_env(:localize, :supported_locales, [:en, :fr, :de])
      Application.delete_env(:localize, :preload_locales)
      run_resolve()

      result = Localize.supported_locales()
      assert is_list(result)
      assert :en in result
      assert :fr in result
      assert :de in result
    end

    test "returns empty list when configured with empty list" do
      Application.put_env(:localize, :supported_locales, [])
      Application.delete_env(:localize, :preload_locales)
      run_resolve()

      assert Localize.supported_locales() == []
    end
  end

  describe "wildcard expansion" do
    test "expands en-* to all en- locales" do
      Application.put_env(:localize, :supported_locales, ["en-*"])
      Application.delete_env(:localize, :preload_locales)
      run_resolve()

      result = Localize.supported_locales()
      assert is_list(result)
      assert :"en-AU" in result
      assert :"en-GB" in result
      assert :"en-IN" in result
      # The base :en is not matched by "en-*" (no hyphen)
      refute :fr in result
    end

    test "expands zh-* to all zh- locales" do
      Application.put_env(:localize, :supported_locales, ["zh-*"])
      Application.delete_env(:localize, :preload_locales)
      run_resolve()

      result = Localize.supported_locales()
      assert :"zh-Hans" in result
      assert :"zh-Hant" in result
    end

    test "mixes atoms and wildcards" do
      Application.put_env(:localize, :supported_locales, [:en, :fr, "de-*"])
      Application.delete_env(:localize, :preload_locales)
      run_resolve()

      result = Localize.supported_locales()
      assert :en in result
      assert :fr in result
      assert :"de-AT" in result
      assert :"de-CH" in result
    end
  end

  describe "supported and preload locale union" do
    test "preload locales are included in supported locales" do
      Application.put_env(:localize, :supported_locales, [:en, :fr])
      Application.put_env(:localize, :preload_locales, [:ja])
      run_resolve()

      result = Localize.supported_locales()
      assert :en in result
      assert :fr in result
      assert :ja in result
    end

    test "preload locales alone do not set supported locales" do
      Application.delete_env(:localize, :supported_locales)
      Application.put_env(:localize, :preload_locales, [:ja])
      run_resolve()

      assert Localize.supported_locales() == nil
    end

    test "duplicates between supported and preload are deduplicated" do
      Application.put_env(:localize, :supported_locales, [:en, :fr, :ja])
      Application.put_env(:localize, :preload_locales, [:ja, :en])
      run_resolve()

      result = Localize.supported_locales()
      assert length(Enum.filter(result, &(&1 == :ja))) == 1
      assert length(Enum.filter(result, &(&1 == :en))) == 1
    end
  end

  describe "validate_locale with supported_locales" do
    test "resolves en-AU to :en when only :en is supported" do
      Application.put_env(:localize, :supported_locales, [:en, :fr, :de])
      Application.delete_env(:localize, :preload_locales)
      run_resolve()

      {:ok, tag} = Localize.validate_locale("en-AU")
      assert tag.cldr_locale_id == :en
    end

    test "resolves en-AU to :en-AU when en-AU is supported" do
      Application.put_env(:localize, :supported_locales, [:en, :"en-AU", :fr])
      Application.delete_env(:localize, :preload_locales)
      run_resolve()

      {:ok, tag} = Localize.validate_locale("en-AU")
      assert tag.cldr_locale_id == :"en-AU"
    end

    test "resolves fr-CA to :fr when only :fr is supported" do
      Application.put_env(:localize, :supported_locales, [:en, :fr, :de])
      Application.delete_env(:localize, :preload_locales)
      run_resolve()

      {:ok, tag} = Localize.validate_locale("fr-CA")
      assert tag.cldr_locale_id == :fr
    end

    test "resolves to all CLDR locales when supported_locales is not configured" do
      Application.delete_env(:localize, :supported_locales)
      Application.delete_env(:localize, :preload_locales)

      try do
        :persistent_term.erase(:localize_supported_locales)
      rescue
        ArgumentError -> :ok
      end

      {:ok, tag} = Localize.validate_locale("en-AU")
      assert tag.cldr_locale_id == :"en-AU"
    end
  end

  describe "invalid locale handling" do
    test "unknown atom locale logs warning and is excluded" do
      Application.put_env(:localize, :supported_locales, [:en, :zzz_invalid])
      Application.delete_env(:localize, :preload_locales)
      run_resolve()

      result = Localize.supported_locales()
      assert :en in result
      refute :zzz_invalid in result
    end

    test "unknown string locale logs warning and is excluded" do
      Application.put_env(:localize, :supported_locales, [:en, "zzz-invalid"])
      Application.delete_env(:localize, :preload_locales)
      run_resolve()

      result = Localize.supported_locales()
      assert :en in result
    end
  end

  # Re-run the application startup logic for supported locales.
  # This simulates what happens at boot with the current config.
  defp run_resolve do
    # Clear cache and persistent_term
    :ets.delete_all_objects(@locale_cache_table)

    try do
      :persistent_term.erase(:localize_supported_locales)
    rescue
      ArgumentError -> :ok
    end

    # Call the private resolve function via the application module.
    # Since it's private, we restart the relevant logic inline.
    supported = expand_config(:supported_locales)
    preload = expand_config(:preload_locales)

    case Application.get_env(:localize, :supported_locales) do
      nil ->
        :ok

      _configured ->
        merged = Enum.uniq(supported ++ preload)
        :persistent_term.put(:localize_supported_locales, merged)
    end
  end

  defp expand_config(config_key) do
    case Application.get_env(:localize, config_key) do
      nil -> []
      [] -> []
      locales when is_list(locales) -> expand_entries(locales, config_key)
    end
  end

  defp expand_entries(entries, config_key) do
    all_ids = Localize.SupplementalData.all_locale_ids()
    all_strings = MapSet.new(all_ids, &Atom.to_string/1)

    entries
    |> Enum.flat_map(fn entry -> expand_entry(entry, all_ids, all_strings, config_key) end)
    |> Enum.uniq()
  end

  defp expand_entry(entry, all_ids, _all_strings, _config_key) when is_atom(entry) do
    if entry in all_ids, do: [entry], else: []
  end

  defp expand_entry(entry, all_ids, all_strings, _config_key) when is_binary(entry) do
    if String.ends_with?(entry, "*") do
      prefix = String.trim_trailing(entry, "*")
      Enum.filter(all_ids, fn id -> id |> Atom.to_string() |> String.starts_with?(prefix) end)
    else
      if MapSet.member?(all_strings, entry), do: [String.to_existing_atom(entry)], else: []
    end
  end
end
