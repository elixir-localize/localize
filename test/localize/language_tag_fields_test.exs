defmodule Localize.LanguageTagFieldsTest do
  @moduledoc """
  Functions that take a language tag, called with structs built by hand
  whose fields have the wrong shape.

  Library code must not raise on invalid input, so every call returns its
  documented result or an error. A field left as `nil` where a list or map
  belongs is empty, and a subtag given as a string resolves to its atom; any
  other shape is an invalid locale. The first day of the week for the US
  comes from CLDR 49's week data (Sunday, day 7).

  """

  use ExUnit.Case, async: true

  @malformations [
    language: "en",
    language: 42,
    script: "Latn",
    script: 42,
    territory: "US",
    territory: 42,
    language_variants: nil,
    language_variants: "x",
    language_variants: [42],
    language_subtags: nil,
    language_subtags: "x",
    locale: nil,
    locale: "x",
    transform: nil,
    transform: "x",
    extensions: nil,
    extensions: "x",
    extensions: %{"a" => 42},
    private_use: nil,
    private_use: "x",
    requested_locale_id: 42,
    canonical_locale_id: 42,
    cldr_locale_id: "en",
    cldr_locale_id: :zz_not_a_locale
  ]

  # A function rather than an attribute, since the calls capture arguments.
  defp calls do
    [
      {"Localize.validate_locale/1", &Localize.validate_locale/1},
      {"Calendar.first_day_for_locale/1", &Localize.Calendar.first_day_for_locale/1},
      {"Currency.currency_format_from_locale/1",
       &Localize.Currency.currency_format_from_locale/1},
      {"Currency.currency_from_locale/1", &Localize.Currency.currency_from_locale/1},
      {"Currency.currency_history_for_locale/1",
       &Localize.Currency.currency_history_for_locale/1},
      {"Currency.current_currency_from_locale/1",
       &Localize.Currency.current_currency_from_locale/1},
      {"Inflection.Locale.normalize/1", &Localize.Inflection.Locale.normalize/1},
      {"Locale.cldr_locale_id_from/1", &Localize.Locale.cldr_locale_id_from/1},
      {"Locale.parent/1", &Localize.Locale.parent/1},
      {"Cardinal.plural_rule/2", &Localize.Number.PluralRule.Cardinal.plural_rule(1, &1)},
      {"Cardinal.plural_rules_for/1", &Localize.Number.PluralRule.Cardinal.plural_rules_for/1},
      {"Ordinal.plural_rule/2", &Localize.Number.PluralRule.Ordinal.plural_rule(1, &1)},
      {"Ordinal.plural_rules_for/1", &Localize.Number.PluralRule.Ordinal.plural_rules_for/1},
      {"Number.System.number_system_from_locale/1",
       &Localize.Number.System.number_system_from_locale/1},
      {"Territory.children/1", &Localize.Territory.children/1},
      {"Territory.contains?/2", &Localize.Territory.contains?(&1, :US)},
      {"Territory.info/1", &Localize.Territory.info/1},
      {"Territory.parent/1", &Localize.Territory.parent/1},
      {"Territory.territory_from_locale/1", &Localize.Territory.territory_from_locale/1},
      {"Territory.to_currency_code/1", &Localize.Territory.to_currency_code/1},
      {"Territory.unicode_flag/1", &Localize.Territory.unicode_flag/1},
      {"Subdivision.for_territory/1", &Localize.Territory.Subdivision.for_territory/1},
      {"Time.hour_format_from_locale/1", &Localize.Time.hour_format_from_locale/1},
      {"LanguageTag.to_string/1", &Localize.LanguageTag.to_string/1},
      {"LanguageTag.canonicalize/1", &Localize.LanguageTag.canonicalize/1},
      {"LanguageTag.best_match/2", &Localize.LanguageTag.best_match(&1, [:en, :fr])},
      {"LanguageTag.add_likely_subtags/1", &Localize.LanguageTag.add_likely_subtags/1},
      {"LanguageTag.remove_likely_subtags/1", &Localize.LanguageTag.remove_likely_subtags/1},
      {"LocaleDisplay.display_name/1", &Localize.Locale.LocaleDisplay.display_name/1},
      {"Number.to_string/2", &Localize.Number.to_string(1234, locale: &1)},
      {"Date.to_string/2", &Localize.Date.to_string(~D[2024-07-06], locale: &1)},
      {"List.to_string/2", &Localize.List.to_string(["a", "b"], locale: &1)},
      {"Unit.to_string/2", &Localize.Unit.to_string(Localize.Unit.new!(1, "meter"), locale: &1)}
    ]
  end

  setup_all do
    {:ok, validated} = Localize.validate_locale("en-US")

    %{
      validated: validated,
      unvalidated: %{validated | cldr_locale_id: nil, canonical_locale_id: nil}
    }
  end

  test "no function taking a language tag raises on fields of the wrong shape", context do
    raised =
      for {base_name, base} <- [validated: context.validated, unvalidated: context.unvalidated],
          {field, value} <- @malformations,
          {call_name, fun} <- calls(),
          outcome = outcome(fun, Map.put(base, field, value)),
          match?({:raised, _exception}, outcome) do
        {call_name, base_name, field, value, outcome}
      end

    assert raised == []
  end

  test "empty fields given as nil are empty and string subtags are atoms", context do
    assert {:ok, tag} =
             Localize.validate_locale(%{context.unvalidated | language_variants: nil})

    assert tag.language_variants == []

    assert {:ok, %Localize.LanguageTag{territory: :US}} =
             Localize.validate_locale(%{context.unvalidated | territory: "US"})

    assert {:error, %Localize.InvalidLocaleError{}} =
             Localize.validate_locale(%{context.unvalidated | territory: 42})

    assert Localize.LanguageTag.to_string(%{context.unvalidated | extensions: "x"}) ==
             "en-Latn-US"
  end

  test "a first-day keyword CLDR does not define falls back to the territory's", context do
    tag = %{context.validated | locale: %Localize.LanguageTag.U{fw: :bogus}}

    assert Localize.Calendar.first_day_for_locale(tag) == 7
  end

  defp outcome(fun, tag) do
    case fun.(tag) do
      {:error, _reason} -> :error
      _value -> :ok
    end
  rescue
    exception -> {:raised, exception.__struct__}
  end
end
