defmodule Localize.NilLocaleTest do
  # `nil` is not a locale. As an atom it was read as the language subtag
  # `nil` (Nila), which CLDR has no data for, so it resolved to the default
  # locale: `Localize.put_locale(nil)` set English.
  use ExUnit.Case, async: true

  test "validate_locale/1 returns an error" do
    assert {:error, %Localize.InvalidLocaleError{}} = Localize.validate_locale(nil)
  end

  test "put_locale/1 returns an error and leaves the process locale as it was" do
    {:ok, french} = Localize.put_locale(:fr)

    assert {:error, %Localize.InvalidLocaleError{}} = Localize.put_locale(nil)
    assert Localize.get_locale() == french
  end

  test "Locale.cldr_locale_id_from/1 returns an error" do
    assert {:error, %{__exception__: true}} = Localize.Locale.cldr_locale_id_from(nil)
  end

  test "LanguageTag.best_match/3 refuses a nil desired locale and skips a nil candidate" do
    assert {:error, %Localize.InvalidLocaleError{}} =
             Localize.LanguageTag.best_match(nil, [:en, :fr])

    assert {:ok, :fr, 0} = Localize.LanguageTag.best_match(:fr, [nil, :fr])
    assert {:error, _no_match} = Localize.LanguageTag.best_match(:fr, [nil], 79)
  end

  test "names no inflection locale" do
    assert Localize.Inflection.Locale.normalize(nil) == ""
  end

  # `nil` is also the language code for Nila. Its atom is `nil`, which a
  # tag reads as "no language", so `nil-ID` became Indonesian with the
  # canonical id `-ID`. CLDR has no data for Nila, and the code is refused.
  test "the language subtag \"nil\" is refused in any case and any tag" do
    for locale <- ["nil", "NIL", "nIL", "nil-ID", "nil-Latn-ID"] do
      assert {^locale, {:error, %Localize.InvalidLocaleError{}}} =
               {locale, Localize.validate_locale(locale)}
    end

    assert {:error, %Localize.InvalidSubtagError{key: :language, reason: :not_representable}} =
             Localize.LanguageTag.parse("nil-ID")
  end
end
