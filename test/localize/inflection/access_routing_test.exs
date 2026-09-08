defmodule Localize.Inflection.AccessRoutingTest do
  # `:inflection` is a locale-data category: `Localize.Locale.get(locale,
  # [:inflection | rest])` routes through the provider to the separate
  # inflection term, inheriting the locale fallback chain and letting a
  # custom provider intercept inflection reads (the customization seam).
  use ExUnit.Case, async: false

  alias Localize.Locale

  # A custom provider that overrides one inflection path and delegates
  # everything else — CLDR and the rest of inflection — to the default.
  defmodule CustomProvider do
    @behaviour Localize.Locale.Provider

    @default Localize.Locale.Provider.PersistentTerm

    defdelegate load(locale), to: @default
    defdelegate store(locale_id, locale_data), to: @default
    defdelegate loaded?(locale), to: @default

    @impl true
    def get(_locale, [:inflection, :custom_marker], _options), do: {:ok, :intercepted}
    def get(locale, keys, options), do: @default.get(locale, keys, options)
  end

  test "[:inflection | rest] routes to the inflection term" do
    assert {:ok, features} = Locale.get(:en, [:inflection, :features])
    assert is_map(features)

    assert {:ok, pronouns} = Locale.get(:en, [:inflection, :pronouns])
    assert is_list(pronouns)
  end

  test "inflection reads inherit the locale fallback chain (en-AU -> en)" do
    assert Locale.get(:"en-AU", [:inflection, :grammeme_names]) ==
             Locale.get(:en, [:inflection, :grammeme_names])
  end

  test "a missing inflection key is a structured not-found error" do
    assert {:error, %Localize.ItemNotFoundError{}} =
             Locale.get(:en, [:inflection, :no_such_field])
  end

  test "a custom provider intercepts inflection reads and delegates the rest" do
    # Intercepted inflection path.
    assert {:ok, :intercepted} =
             Locale.get(:en, [:inflection, :custom_marker], provider: CustomProvider)

    # Delegated inflection path still resolves real data.
    assert {:ok, features} = Locale.get(:en, [:inflection, :features], provider: CustomProvider)
    assert is_map(features)

    # Delegated CLDR path is unaffected.
    assert {:ok, _} = Locale.get(:en, [:languages, "en"], provider: CustomProvider)
  end
end
