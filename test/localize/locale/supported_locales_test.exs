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

    test "returns root alone when set to empty list", context do
      Localize.put_supported_locales([])
      assert Localize.supported_locales() == [:und]
      Localize.put_supported_locales(context.original_supported)
    end

    test "adds :und to a list that does not name it, and once only", context do
      Localize.put_supported_locales([:en, :fr])
      assert Localize.supported_locales() == [:en, :fr, :und]

      Localize.put_supported_locales([:und, :en])
      assert Localize.supported_locales() == [:und, :en]

      Localize.put_supported_locales(context.original_supported)
    end
  end

  describe "supported_locales/0 lazy resolution" do
    setup do
      original_env = Application.get_env(:localize, :supported_locales)

      on_exit(fn ->
        case original_env do
          nil -> Application.delete_env(:localize, :supported_locales)
          value -> Application.put_env(:localize, :supported_locales, value)
        end
      end)

      :ok
    end

    test "resolves and caches from application env when cache is empty", context do
      :persistent_term.erase({:localize, :supported_locales})
      Application.put_env(:localize, :supported_locales, [:en, :fr, :de])

      result = Localize.supported_locales()

      assert Enum.sort(result) == [:de, :en, :fr, :und]
      assert :persistent_term.get({:localize, :supported_locales}) == result

      Localize.put_supported_locales(context.original_supported)
    end

    test "expands wildcard entries from application env", context do
      :persistent_term.erase({:localize, :supported_locales})
      Application.put_env(:localize, :supported_locales, ["en-*"])

      result = Localize.supported_locales()

      assert :"en-AU" in result
      assert :"en-GB" in result
      refute :en in result
      assert :und in result
      assert Enum.all?(result -- [:und], &(&1 |> Atom.to_string() |> String.starts_with?("en-")))
      assert :persistent_term.get({:localize, :supported_locales}) == result

      Localize.put_supported_locales(context.original_supported)
    end

    test "falls back to all locale IDs without caching when env is not set", context do
      :persistent_term.erase({:localize, :supported_locales})
      Application.delete_env(:localize, :supported_locales)

      assert Localize.supported_locales() == Localize.all_locale_ids()
      assert :persistent_term.get({:localize, :supported_locales}, :not_set) == :not_set

      Localize.put_supported_locales(context.original_supported)
    end

    test "validate_locale honors application env when cache is empty", context do
      :persistent_term.erase({:localize, :supported_locales})
      Localize.Locale.Loader.clear_locale_cache()
      Application.put_env(:localize, :supported_locales, [:"de-CH", :"en-CH", :"fr-CH", :"it-CH"])

      {:ok, tag} = Localize.validate_locale("de")

      assert tag.cldr_locale_id == :"de-CH"

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

  # Root is a supported locale whether or not it is configured, so `und`
  # resolves to itself and every parent chain ends at it (#68).
  describe "root with supported_locales that do not name it" do
    test "und resolves to :und, not to the default locale", context do
      Localize.put_supported_locales([:en, :ru, :nb])

      {:ok, tag} = Localize.validate_locale(:und)
      assert tag.cldr_locale_id == :und

      Localize.put_supported_locales(context.original_supported)
    end

    test "every parent chain ends at :und", context do
      Localize.put_supported_locales([:en, :da, :ru, :"zh-Hant"])

      for locale <- [:da, :ru, :"en-AU", :"zh-Hant"] do
        {:ok, tag} = Localize.validate_locale(locale)
        assert List.last(cldr_chain(tag)) == :und, inspect(locale)
      end

      Localize.put_supported_locales(context.original_supported)
    end

    test "a spellout rule set the locale lacks is an error, not English words", context do
      Localize.put_supported_locales([:en, :ru, :nb])

      assert {:error, %Localize.UnknownRbnfRuleError{locale: :ru}} =
               Localize.Number.Rbnf.to_string(2_000_000, :spellout_cardinal, locale: :ru)

      assert {:error, %Localize.UnknownRbnfRuleError{locale: :nb}} =
               Localize.Number.to_string(3, format: :spellout, locale: :nb)

      Localize.put_supported_locales(context.original_supported)
    end

    test "root's own rule sets are still reached", context do
      Localize.put_supported_locales([:en, :ru])

      assert Localize.Number.Rbnf.to_string(1999, :roman_upper, locale: :ru) == {:ok, "MCMXCIX"}

      Localize.put_supported_locales(context.original_supported)
    end

    test "a parent's rules are reached once the parent is supported", context do
      Localize.put_supported_locales([:en, :nb])

      assert {:error, %Localize.UnknownRbnfRuleError{}} =
               Localize.Number.to_string(3, format: :spellout, locale: :nb)

      Localize.put_supported_locales([:en, :nb, :no])
      assert Localize.Number.to_string(3, format: :spellout, locale: :nb) == {:ok, "tre"}

      Localize.put_supported_locales(context.original_supported)
    end
  end

  # The CLDR locale of each ancestor of a tag, up to the root.
  defp cldr_chain(tag) do
    tag
    |> Stream.unfold(fn tag ->
      case Localize.Locale.parent(tag) do
        {:ok, parent} ->
          {:ok, locale_id} = Localize.Locale.cldr_locale_id_from(parent)
          {locale_id, parent}

        {:error, _reason} ->
          nil
      end
    end)
    |> Enum.to_list()
  end
end
