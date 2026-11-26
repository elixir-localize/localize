defmodule Localize.Locale.FallbackChainTest do
  use ExUnit.Case, async: true

  alias Localize.Locale

  test "follows CLDR's parent locales, nearest first" do
    for {locale, chain} <- [
          {"fr-CA", [:"fr-CA", :fr]},
          {"en-AU", [:"en-AU", :"en-001", :en]},
          {"en-150", [:"en-150", :"en-001", :en]},
          {"es-MX", [:"es-MX", :"es-419", :es]},
          {"pt-AO", [:"pt-AO", :"pt-PT", :pt]},
          {"zh-Hant-HK", [:"zh-Hant-HK", :"zh-Hant"]},
          {"zh-Hans-SG", [:"zh-Hans-SG", :"zh-Hans", :zh]},
          {"hi-Latn", [:"hi-Latn", :"en-IN", :"en-001", :en]},
          {"ca-ES-valencia", [:"ca-ES-valencia", :ca]},
          {"nb", [:nb, :no]},
          {"en", [:en]}
        ] do
      assert {locale, Locale.fallback_chain(locale)} == {locale, {:ok, chain}}
    end
  end

  test "takes the script a locale's likely subtags give it, never its language's other script" do
    assert Locale.fallback_chain("zh-HK") == {:ok, [:"zh-Hant-HK", :"zh-Hant"]}
    assert Locale.fallback_chain("sr-ME") == {:ok, [:"sr-Latn-ME", :"sr-Latn"]}
    assert Locale.fallback_chain("sr-Latn") == {:ok, [:"sr-Latn"]}
  end

  test "takes atoms, POSIX strings and language tags, and ignores extensions" do
    {:ok, tag} = Localize.validate_locale("en-AU")

    for locale <- [:"en-AU", "en_AU", "en-AU-u-ca-buddhist", tag] do
      assert Locale.fallback_chain(locale) == {:ok, [:"en-AU", :"en-001", :en]}, inspect(locale)
    end
  end

  test "is empty for the root and for a locale that resolves to it" do
    assert Locale.fallback_chain("und") == {:ok, []}
    assert Locale.fallback_chain(:und) == {:ok, []}
    assert Locale.fallback_chain("tlh") == {:ok, []}
  end

  test "keeps only the :supported locales, in chain order" do
    assert Locale.fallback_chain("en-AU", supported: [:en, :fr]) == {:ok, [:en]}
    assert Locale.fallback_chain("en-AU", supported: ["en", "en-001"]) == {:ok, [:"en-001", :en]}
    assert Locale.fallback_chain("fr-CA", supported: [:de]) == {:ok, []}

    assert Locale.fallback_chain("fr-CA", supported: [nil, 42, "not a locale!", :fr]) ==
             {:ok, [:fr]}

    assert Locale.fallback_chain("fr-CA", supported: nil) == {:ok, [:"fr-CA", :fr]}
  end

  test "returns an error, never raises, for a locale or option it cannot use" do
    for {locale, options} <- [
          {nil, []},
          {42, []},
          {"", []},
          {"not a locale!", []},
          {%{}, []},
          {"fr-CA", %{}},
          {"fr-CA", supported: "fr"},
          {"fr-CA", supported: %{}}
        ] do
      assert {:error, %{__exception__: true}} = Locale.fallback_chain(locale, options),
             inspect({locale, options})
    end
  end
end

defmodule Localize.Locale.FallbackChainConfiguredTest do
  # Changes the supported locales for the whole node, so it runs alone.
  use ExUnit.Case, async: false

  setup do
    original_supported = Localize.supported_locales()
    on_exit(fn -> Localize.put_supported_locales(original_supported) end)
  end

  # The chain names the CLDR locales a locale falls back through, whatever
  # Localize is configured for: with only `en` and `fr` configured,
  # `validate_locale/1` serves `pt-BR` from `en`, but a translation stored
  # for Portuguese is still found under `pt`.
  test "is the same whatever Localize is configured for" do
    inputs = ["fr-CA", "en-AU", "fr", "pt-BR", "sv", "zh-Hans", "de-CH", "nb"]
    full = Map.new(inputs, &{&1, Localize.Locale.fallback_chain(&1)})

    :ok = Localize.put_supported_locales([:en, :fr])

    for input <- inputs do
      assert {input, Localize.Locale.fallback_chain(input)} == {input, full[input]}
    end

    assert Localize.Locale.fallback_chain("pt-BR") == {:ok, [:pt]}
    assert Localize.Locale.fallback_chain("zh-Hans") == {:ok, [:"zh-Hans", :zh]}
  end

  test "resolves a validated tag from the locale it was asked for" do
    :ok = Localize.put_supported_locales([:en, :fr])
    {:ok, tag} = Localize.validate_locale("pt-BR")

    assert tag.cldr_locale_id == :en
    assert Localize.Locale.fallback_chain(tag) == {:ok, [:pt]}
  end

  test "resolves :supported entries the same way" do
    :ok = Localize.put_supported_locales([:en, :fr])

    assert Localize.Locale.fallback_chain("pt-BR", supported: ["pt-BR", "en"]) == {:ok, [:pt]}
    assert Localize.Locale.fallback_chain("pt-BR", supported: [:en]) == {:ok, []}
  end
end
