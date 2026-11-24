defmodule Localize.Locale.DirectionTest do
  use ExUnit.Case, async: true

  # The direction of each locale is its script's, from CLDR's script
  # metadata. On CLDR 49 it agrees with the `characterOrder` of every one
  # of the 657 locales that carry layout data.

  @right_to_left ~w(ar ar-EG he fa ur ps sd ckb dv yi syr nqo ks ug ff-Adlm rhg pa-Arab az-Arab ms-Arab)
  @left_to_right ~w(en en-AU fr de ja zh-Hant th zgh pa az sd-Deva ff ru hi und tlh)

  test "is right to left for a locale written in a right-to-left script" do
    for locale <- @right_to_left do
      assert {locale, Localize.Locale.direction(locale)} == {locale, {:ok, :rtl}}
    end
  end

  test "is left to right for a locale written in a left-to-right script" do
    for locale <- @left_to_right do
      assert {locale, Localize.Locale.direction(locale)} == {locale, {:ok, :ltr}}
    end
  end

  test "takes an atom or a language tag" do
    {:ok, hebrew} = Localize.validate_locale("he")

    assert Localize.Locale.direction(:ar) == {:ok, :rtl}
    assert Localize.Locale.direction(hebrew) == {:ok, :rtl}
  end

  test "follows a script given in the locale over the language's likely one" do
    assert Localize.Locale.direction("ur-Latn") == {:ok, :ltr}
    assert Localize.Locale.direction("en-Arab") == {:ok, :rtl}
  end

  test "returns an error for a value that is not a locale" do
    for locale <- ["!!!", "", 1, %{}, ["ar"], %Localize.LanguageTag{language: 1}] do
      assert {:error, %{__exception__: true}} = Localize.Locale.direction(locale)
    end
  end
end
