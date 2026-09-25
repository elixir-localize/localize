defmodule Localize.WrongTypeInputTest do
  @moduledoc """
  Public functions given options that are not a keyword list, or an argument
  or option value of the wrong type, return `{:error, exception}` carrying a
  Localize exception whose message renders, rather than raising. Predicates
  answer `false`, and bang variants raise the Localize exception.

  """

  use ExUnit.Case, async: true

  @not_keyword_lists [:bogus, nil, 42, "x", %{}, {1, 2}, [1]]
  @not_strings [nil, 42, %{}, {1, 2}, [1]]
  @not_numbers [nil, :bogus, "x", %{}, {1, 2}, [1]]
  @not_locales [42, 1.5, %{}, {1, 2}, [1]]
  @not_units [nil, :bogus, "meter", 42, %{}, {1, 2}, [1]]
  @not_lists [nil, :bogus, 42, "x", %{}, {1, 2}]
  @not_maps [nil, :bogus, 42, "x", {1, 2}, [1]]

  @zoned %{time_zone: "America/New_York", utc_offset: -18_000, std_offset: 0}

  defp failures(cases, expected?) do
    for {name, values, fun} <- cases,
        value <- values,
        result = fun.(value),
        not expected?.(result),
        do: {name, value, result}
  end

  defp localize_exception?(%{__exception__: true} = exception) do
    String.starts_with?(inspect(exception.__struct__), "Localize.") and
      is_binary(Exception.message(exception))
  end

  defp localize_exception?(_other), do: false

  defp invalid_value_error?({:error, %Localize.InvalidValueError{} = exception}),
    do: localize_exception?(exception)

  defp invalid_value_error?(_result), do: false

  defp localize_error?({:error, exception}), do: localize_exception?(exception)
  defp localize_error?(_result), do: false

  test "options that are not a keyword list are an InvalidValueError" do
    unit = Localize.Unit.new!(1, "meter")
    duration = %Localize.Duration{hour: 1}
    tag = Localize.LanguageTag.parse!("en-Latn-US")
    {:ok, ast} = Localize.Message.Parser.parse("Hello")
    {:ok, tokens} = Localize.Message.to_tokens("Hello")

    calls = [
      {"Localize.quote/2", &Localize.quote("abc", &1)},
      {"Localize.ellipsis/2", &Localize.ellipsis("abc", &1)},
      {"Localize.to_string/2", &Localize.to_string(~D[2024-07-06], &1)},
      {"Localize.LanguageTag.remove_likely_subtags/2",
       &Localize.LanguageTag.remove_likely_subtags(tag, &1)},
      {"Localize.Locale.get/3", &Localize.Locale.get(:en, [:number_systems], &1)},
      {"Localize.Locale.load/2", &Localize.Locale.load(:en, &1)},
      {"Localize.Locale.load_and_store/2", &Localize.Locale.load_and_store(:en, &1)},
      {"Localize.Locale.LocaleDisplay.display_name/2",
       &Localize.Locale.LocaleDisplay.display_name(:en, &1)},
      {"Localize.Currency.currencies_for_locale/2",
       &Localize.Currency.currencies_for_locale(:en, &1)},
      {"Localize.Currency.currency_strings/2", &Localize.Currency.currency_strings(:en, &1)},
      {"Localize.Currency.currency_for_code/2", &Localize.Currency.currency_for_code(:USD, &1)},
      {"Localize.Currency.pluralize/3", &Localize.Currency.pluralize(1, :USD, &1)},
      {"Localize.Territory.display_name/2", &Localize.Territory.display_name(:US, &1)},
      {"Localize.Territory.territory_names_for/1", &Localize.Territory.territory_names_for(&1)},
      {"Localize.Territory.territory_codes/1", &Localize.Territory.territory_codes(&1)},
      {"Localize.Territory.Subdivision.display_name/2",
       &Localize.Territory.Subdivision.display_name(:caon, &1)},
      {"Localize.Territory.Subdivision.subdivisions_for/1",
       &Localize.Territory.Subdivision.subdivisions_for(&1)},
      {"Localize.Language.display_name/2", &Localize.Language.display_name(:en, &1)},
      {"Localize.Language.languages_for/1", &Localize.Language.languages_for(&1)},
      {"Localize.Script.display_name/2", &Localize.Script.display_name(:Latn, &1)},
      {"Localize.Script.scripts_for/1", &Localize.Script.scripts_for(&1)},
      {"Localize.Calendar.display_name/3", &Localize.Calendar.display_name(:month, 1, &1)},
      {"Localize.Calendar.localize/3", &Localize.Calendar.localize(~D[2024-07-06], :month, &1)},
      {"Localize.Date.to_string/2", &Localize.Date.to_string(~D[2024-07-06], &1)},
      {"Localize.Date.to_parts/2", &Localize.Date.to_parts(~D[2024-07-06], &1)},
      {"Localize.Time.to_string/2", &Localize.Time.to_string(~T[10:30:00], &1)},
      {"Localize.DateTime.to_string/2",
       &Localize.DateTime.to_string(~U[2024-07-06 10:30:00Z], &1)},
      {"Localize.DateTime.Relative.to_string/2", &Localize.DateTime.Relative.to_string(1, &1)},
      {"Localize.DateTime.Timezone.non_location_format/3",
       &Localize.DateTime.Timezone.non_location_format(@zoned, :en, &1)},
      {"Localize.DateTime.Timezone.gmt_format/3",
       &Localize.DateTime.Timezone.gmt_format(@zoned, :en, &1)},
      {"Localize.DateTime.Timezone.iso_format/2",
       &Localize.DateTime.Timezone.iso_format(@zoned, &1)},
      {"Localize.Interval.to_string/3",
       &Localize.Interval.to_string(~D[2024-07-06], ~D[2024-07-10], &1)},
      {"Localize.Duration.to_string/2", &Localize.Duration.to_string(duration, &1)},
      {"Localize.Duration.to_time_string/2", &Localize.Duration.to_time_string(duration, &1)},
      {"Localize.List.to_string/2", &Localize.List.to_string(["a", "b"], &1)},
      {"Localize.List.intersperse/2", &Localize.List.intersperse(["a", "b"], &1)},
      {"Localize.Collation.compare/3", &Localize.Collation.compare("a", "b", &1)},
      {"Localize.Collation.sort/2", &Localize.Collation.sort(["b", "a"], &1)},
      {"Localize.Collation.sort_key/2", &Localize.Collation.sort_key("a", &1)},
      {"Localize.Collation.Options.new/1", &Localize.Collation.Options.new(&1)},
      {"Localize.Message.format/3", &Localize.Message.format("Hello", %{}, &1)},
      {"Localize.Message.canonical_message/2", &Localize.Message.canonical_message("Hello", &1)},
      {"Localize.Message.to_tokens/2", &Localize.Message.to_tokens("Hello", &1)},
      {"Localize.Message.jaro_distance/3", &Localize.Message.jaro_distance("a", "b", &1)},
      {"Localize.Message.Print.to_string/2", &Localize.Message.Print.to_string(ast, &1)},
      {"Localize.Message.JSON.to_json/2", &Localize.Message.JSON.to_json(ast, &1)},
      {"Localize.Message.Formatter.HTML.render/2",
       &Localize.Message.Formatter.HTML.render(tokens, &1)},
      {"Localize.Message.Formatter.ANSI.render/2",
       &Localize.Message.Formatter.ANSI.render(tokens, &1)},
      {"Localize.Number.Rbnf.to_string/3",
       &Localize.Number.Rbnf.to_string(1, :spellout_cardinal, &1)},
      {"Localize.Number.Formatter.Ratio.to_ratio_string/2",
       &Localize.Number.Formatter.Ratio.to_ratio_string(0.5, &1)},
      {"Localize.Number.Format.Options.validate_options/2",
       &Localize.Number.Format.Options.validate_options(0, &1)},
      {"Localize.Number.PluralRule.plural_type/2",
       &Localize.Number.PluralRule.plural_type(1, &1)},
      {"Localize.Unit.new/3", &Localize.Unit.new(1, "meter", &1)},
      {"Localize.Unit.parse/2", &Localize.Unit.parse("1 meter", &1)},
      {"Localize.Unit.to_string/2", &Localize.Unit.to_string(unit, &1)},
      {"Localize.Unit.to_parts/2", &Localize.Unit.to_parts(unit, &1)},
      {"Localize.Unit.to_range_string/3", &Localize.Unit.to_range_string(unit, unit, &1)},
      {"Localize.Unit.humanize/2", &Localize.Unit.humanize(unit, &1)},
      {"Localize.Unit.localize/2", &Localize.Unit.localize(unit, &1)},
      {"Localize.Unit.display_name/2", &Localize.Unit.display_name("meter", &1)},
      {"Localize.Unit.decompose/3", &Localize.Unit.decompose(unit, ["meter"], &1)},
      {"Localize.Unit.Preference.preferred_units/2",
       &Localize.Unit.Preference.preferred_units(unit, &1)}
    ]

    cases = for {name, fun} <- calls, do: {name, @not_keyword_lists, fun}

    assert failures(cases, &invalid_value_error?/1) == []
  end

  test "arguments of the wrong type are a Localize error" do
    unit = Localize.Unit.new!(1, "meter")

    cases = [
      {"Localize.quote/2", @not_strings, &Localize.quote(&1, [])},
      {"Localize.ellipsis/2", @not_strings, &Localize.ellipsis(&1, [])},
      {"Localize.with_locale/2", [nil, 42, "x", %{}, {1, 2}, [1]],
       &Localize.with_locale(:en, &1)},
      {"Localize.all_locale_ids/1", [:bogus, 42, "x", %{}, {1, 2}, [1]],
       &Localize.all_locale_ids(&1)},
      {"Localize.validate_calendar/1", @not_locales, &Localize.validate_calendar(&1)},
      {"Localize.validate_number_system/1", @not_locales, &Localize.validate_number_system(&1)},
      {"Localize.validate_measurement_system/1", @not_locales,
       &Localize.validate_measurement_system(&1)},
      {"Localize.LanguageTag.parse/1", @not_locales, &Localize.LanguageTag.parse(&1)},
      {"Localize.LanguageTag.new/1", @not_locales, &Localize.LanguageTag.new(&1)},
      {"Localize.LanguageTag.to_string/1", @not_locales, &Localize.LanguageTag.to_string(&1)},
      {"Localize.LanguageTag.canonicalize/1", @not_locales,
       &Localize.LanguageTag.canonicalize(&1)},
      {"Localize.LanguageTag.add_likely_subtags/1", @not_locales,
       &Localize.LanguageTag.add_likely_subtags(&1)},
      {"Localize.LanguageTag.remove_likely_subtags/2", @not_locales,
       &Localize.LanguageTag.remove_likely_subtags(&1, [])},
      {"Localize.Locale.parent/1", @not_locales, &Localize.Locale.parent(&1)},
      {"Localize.Locale.get/3 keys", [nil, :bogus, 42, "x", %{}, {1, 2}],
       &Localize.Locale.get(:en, &1)},
      {"Localize.Currency.currency_from_locale/1", @not_locales,
       &Localize.Currency.currency_from_locale(&1)},
      {"Localize.Currency.current_currency_from_locale/1", @not_locales,
       &Localize.Currency.current_currency_from_locale(&1)},
      {"Localize.Currency.territory_currencies/1", @not_locales,
       &Localize.Currency.territory_currencies(&1)},
      {"Localize.Currency.validate_currency/1", @not_locales,
       &Localize.Currency.validate_currency(&1)},
      {"Localize.Currency.pluralize/3", @not_numbers, &Localize.Currency.pluralize(&1, :USD, [])},
      {"Localize.Calendar.first_day_for_territory/1", @not_locales,
       &Localize.Calendar.first_day_for_territory(&1)},
      {"Localize.Calendar.weekend/1", @not_locales, &Localize.Calendar.weekend(&1)},
      {"Localize.Territory.territory_from_locale/1", @not_locales,
       &Localize.Territory.territory_from_locale(&1)},
      {"Localize.Territory.Subdivision.display_name/2", @not_locales,
       &Localize.Territory.Subdivision.display_name(&1, [])},
      {"Localize.Number.PluralRule.Cardinal.plural_rule/2 number", [nil, :bogus, "x", %{}, [1]],
       &Localize.Number.PluralRule.Cardinal.plural_rule(&1, :en)},
      {"Localize.Number.PluralRule.Cardinal.plural_rule/2 locale", @not_locales,
       &Localize.Number.PluralRule.Cardinal.plural_rule(1, &1)},
      {"Localize.Number.PluralRule.Cardinal.pluralize/3 number", @not_numbers,
       &Localize.Number.PluralRule.Cardinal.pluralize(&1, :en, %{other: "x"})},
      {"Localize.Number.PluralRule.Cardinal.pluralize/3 substitutions", @not_maps,
       &Localize.Number.PluralRule.Cardinal.pluralize(1, :en, &1)},
      {"Localize.Number.PluralRule.Cardinal.plural_rules_for/1", @not_locales,
       &Localize.Number.PluralRule.Cardinal.plural_rules_for(&1)},
      {"Localize.Number.PluralRule.Ordinal.plural_rule/2 number", [nil, :bogus, "x", %{}, [1]],
       &Localize.Number.PluralRule.Ordinal.plural_rule(&1, :en)},
      {"Localize.Number.PluralRule.Ordinal.pluralize/3 substitutions", @not_maps,
       &Localize.Number.PluralRule.Ordinal.pluralize(1, :en, &1)},
      {"Localize.Number.PluralRule.Ordinal.plural_rules_for/1", @not_locales,
       &Localize.Number.PluralRule.Ordinal.plural_rules_for(&1)},
      {"Localize.Number.PluralRule.Range.plural_rule/3", [42, "x", %{}, {1, 2}, [1]],
       &Localize.Number.PluralRule.Range.plural_rule(&1, :other, :en)},
      {"Localize.Number.Rbnf.to_string/3 number", @not_numbers,
       &Localize.Number.Rbnf.to_string(&1, :spellout_cardinal, [])},
      {"Localize.Number.Rbnf.to_string/3 rule name", @not_locales,
       &Localize.Number.Rbnf.to_string(1, &1, [])},
      {"Localize.Number.Formatter.Ratio.to_ratio_string/2", @not_numbers,
       &Localize.Number.Formatter.Ratio.to_ratio_string(&1, [])},
      {"Localize.Number.System.number_system_from_locale/1", @not_locales,
       &Localize.Number.System.number_system_from_locale(&1)},
      {"Localize.List.to_string/2", @not_lists, &Localize.List.to_string(&1, [])},
      {"Localize.Collation.compare/3", @not_strings, &Localize.Collation.compare(&1, "a", [])},
      {"Localize.Collation.sort/2", @not_lists, &Localize.Collation.sort(&1, [])},
      {"Localize.Collation.sort_key/2", [nil, :bogus, 42, %{}, {1, 2}],
       &Localize.Collation.sort_key(&1, [])},
      {"Localize.Message.format/3 message", @not_strings, &Localize.Message.format(&1, %{}, [])},
      {"Localize.Message.format/3 bindings", [:bogus, 42, "x", {1, 2}, [1]],
       &Localize.Message.format("Hello", &1, [])},
      {"Localize.Message.Parser.parse/1", @not_strings, &Localize.Message.Parser.parse(&1)},
      {"Localize.Duration.new/2", @not_units, &Localize.Duration.new(&1, ~D[2020-01-01])},
      {"Localize.Duration.new_from_seconds/1", @not_numbers,
       &Localize.Duration.new_from_seconds(&1)},
      {"Localize.Duration.to_string/2", @not_units, &Localize.Duration.to_string(&1, [])},
      {"Localize.Interval.greatest_difference/2", @not_maps,
       &Localize.Interval.greatest_difference(&1, ~D[2024-01-01])},
      {"Localize.DateTime.Timezone.non_location_format/3", @not_maps,
       &Localize.DateTime.Timezone.non_location_format(&1, :en, [])},
      {"Localize.Unit.to_string/2", @not_units, &Localize.Unit.to_string(&1, [])},
      {"Localize.Unit.to_parts/2", @not_units, &Localize.Unit.to_parts(&1, [])},
      {"Localize.Unit.to_iolist/2", @not_units, &Localize.Unit.to_iolist(&1, [])},
      {"Localize.Unit.humanize/2", @not_units, &Localize.Unit.humanize(&1, [])},
      {"Localize.Unit.localize/2", @not_units, &Localize.Unit.localize(&1, [])},
      {"Localize.Unit.convert/2", @not_units, &Localize.Unit.convert(&1, "foot")},
      {"Localize.Unit.compare/2", @not_units, &Localize.Unit.compare(&1, unit)},
      {"Localize.Unit.value/1", @not_units, &Localize.Unit.value(&1)},
      {"Localize.Unit.zero/1", @not_units, &Localize.Unit.zero(&1)},
      {"Localize.Unit.unit_category/1", [nil, :bogus, 42, %{}, {1, 2}, [1]],
       &Localize.Unit.unit_category(&1)},
      {"Localize.Unit.display_name/2", [nil, :bogus, 42, %{}, {1, 2}, [1]],
       &Localize.Unit.display_name(&1, [])},
      {"Localize.Unit.measurement_system_for_territory/2 territory", [42, "US", %{}, {1, 2}, [1]],
       &Localize.Unit.measurement_system_for_territory(&1, :default)},
      {"Localize.Unit.measurement_system_for_territory/2 category", [:bogus, nil, 42, "x"],
       &Localize.Unit.measurement_system_for_territory(:US, &1)},
      {"Localize.Unit.Math.add/2", @not_units, &Localize.Unit.Math.add(&1, unit)},
      {"Localize.Unit.Math.round/3", [nil, :bogus, "x", 1.5],
       &Localize.Unit.Math.round(unit, &1, :half_up)}
    ]

    assert failures(cases, &localize_error?/1) == []
  end

  test "option values of the wrong type are a Localize error" do
    unit = Localize.Unit.new!(1, "meter")
    duration = %Localize.Duration{hour: 1}
    not_digit_counts = [:bogus, "x", %{}, 1.5]

    cases = [
      {"Localize.Number.to_string/2 :fractional_digits", not_digit_counts,
       &Localize.Number.to_string(1.5, fractional_digits: &1)},
      {"Localize.Number.to_string/2 :min_fractional_digits", not_digit_counts,
       &Localize.Number.to_string(1.5, min_fractional_digits: &1)},
      {"Localize.Number.to_string/2 :max_fractional_digits", not_digit_counts,
       &Localize.Number.to_string(1.5, max_fractional_digits: &1)},
      {"Localize.Number.to_string/2 :maximum_integer_digits", not_digit_counts,
       &Localize.Number.to_string(1234, maximum_integer_digits: &1)},
      {"Localize.Number.to_string/2 :wrapper", [:bogus, "x", 42, fn -> :ok end],
       &Localize.Number.to_string(1, wrapper: &1)},
      {"Localize.Number.parse/2 :number", [:bogus, "x", 42],
       &Localize.Number.parse("1", number: &1)},
      {"Localize.Number.scan/2 :number", [:bogus, "x", 42],
       &Localize.Number.scan("1", number: &1)},
      {"Localize.Number.to_ratio_string/2 :max_denominator", [:bogus, "x", 0, 1.5],
       &Localize.Number.to_ratio_string(0.5, max_denominator: &1)},
      {"Localize.Number.to_ratio_string/2 :max_iterations", [:bogus, "x", 0, 1.5],
       &Localize.Number.to_ratio_string(0.5, max_iterations: &1)},
      {"Localize.Number.to_ratio_string/2 :epsilon", [:bogus, "x", 0, 42],
       &Localize.Number.to_ratio_string(0.5, epsilon: &1)},
      {"Localize.Collation.compare/3 :strength", [:bogus, "x", 42],
       &Localize.Collation.compare("a", "b", strength: &1)},
      {"Localize.Collation.compare/3 :alternate", [:bogus, "x", 42],
       &Localize.Collation.compare("a", "b", alternate: &1)},
      {"Localize.Collation.compare/3 :case_first", [:bogus, "x", 42],
       &Localize.Collation.compare("a", "b", case_first: &1)},
      {"Localize.Collation.compare/3 :max_variable", [:bogus, "x", 42],
       &Localize.Collation.compare("a", "b", max_variable: &1)},
      {"Localize.Collation.compare/3 :reorder", [42, %{}, {1, 2}, [1]],
       &Localize.Collation.compare("a", "b", reorder: &1)},
      {"Localize.Duration.to_string/2 :except", [:bogus, "x", 42, %{}],
       &Localize.Duration.to_string(duration, except: &1)},
      {"Localize.DateTime.Timezone.non_location_format/3 :type", [:bogus, "x", 42],
       &Localize.DateTime.Timezone.non_location_format(@zoned, :en, type: &1)},
      {"Localize.Unit.to_string/2 :list_options", [:bogus, "x", 42, %{}],
       &Localize.Unit.to_string([unit, unit], list_options: &1)},
      {"Localize.Unit.parse/2 :only", [42, %{}, {1, 2}, [%{}]],
       &Localize.Unit.parse("2 w", only: &1)},
      {"Localize.Locale.get/3 :provider", [:bogus, "x", 42, nil, Localize],
       &Localize.Locale.get(:en, [:number_systems], provider: &1)},
      {"Localize.Locale.load/2 :provider", [:bogus, "x", 42, nil, Localize],
       &Localize.Locale.load(:en, provider: &1)}
    ]

    assert failures(cases, &localize_error?/1) == []
  end

  test "predicates answer false for arguments of the wrong type" do
    not_currencies = [nil, :USD, 42, %{}]

    cases = [
      {"Localize.available_locale_id?/1", [42, %{}, {1, 2}, [1]],
       &Localize.available_locale_id?(&1)},
      {"Localize.Currency.historic?/1", not_currencies, &Localize.Currency.historic?(&1)},
      {"Localize.Currency.tender?/1", not_currencies, &Localize.Currency.tender?(&1)},
      {"Localize.Currency.current?/1", not_currencies, &Localize.Currency.current?(&1)},
      {"Localize.Currency.annotated?/1", not_currencies, &Localize.Currency.annotated?(&1)},
      {"Localize.Currency.unannotated?/1", not_currencies, &Localize.Currency.unannotated?(&1)},
      {"Localize.Collation.Options.nif_compatible?/1", [nil, 42, %{}],
       &Localize.Collation.Options.nif_compatible?(&1)},
      {"Localize.Unit.zero?/1", [nil, 0, "meter", %{}], &Localize.Unit.zero?(&1)},
      {"Localize.Unit.compatible?/2", [nil, 42, %{}, {1, 2}],
       &Localize.Unit.compatible?(&1, "meter")},
      {"Localize.Locale.loaded?/2 options", @not_keyword_lists,
       &Localize.Locale.loaded?(:en, &1)},
      {"Localize.Locale.loaded?/2 :provider", [:bogus, "x", 42, nil],
       &Localize.Locale.loaded?(:en, provider: &1)}
    ]

    assert failures(cases, &(&1 == false)) == []
  end

  test "bang variants raise a Localize exception for arguments of the wrong type" do
    cases = [
      {"Localize.LanguageTag.parse!/1", @not_locales, &Localize.LanguageTag.parse!(&1)},
      {"Localize.LanguageTag.new!/1", @not_locales, &Localize.LanguageTag.new!(&1)},
      {"Localize.LanguageTag.canonicalize!/1", @not_locales,
       &Localize.LanguageTag.canonicalize!(&1)},
      {"Localize.LanguageTag.add_likely_subtags!/1", @not_locales,
       &Localize.LanguageTag.add_likely_subtags!(&1)},
      {"Localize.Calendar.strftime_options!/1", @not_keyword_lists,
       &Localize.Calendar.strftime_options!(&1)},
      {"Localize.Currency.currencies_for_locale!/2", @not_keyword_lists,
       &Localize.Currency.currencies_for_locale!(:en, &1)},
      {"Localize.Territory.Subdivision.display_name!/2", @not_locales,
       &Localize.Territory.Subdivision.display_name!(&1, [])},
      {"Localize.Message.format!/3", @not_strings, &Localize.Message.format!(&1, %{}, [])},
      {"Localize.Message.Parser.parse!/1", @not_strings, &Localize.Message.Parser.parse!(&1)},
      {"Localize.Duration.to_string!/2", @not_units, &Localize.Duration.to_string!(&1, [])},
      {"Localize.Unit.new!/1", [nil, 42, %{}, {1, 2}, [1]], &Localize.Unit.new!(&1)},
      {"Localize.Unit.to_string!/2", @not_units, &Localize.Unit.to_string!(&1, [])},
      {"Localize.Unit.to_parts!/2", @not_units, &Localize.Unit.to_parts!(&1, [])},
      {"Localize.Unit.humanize!/2", @not_units, &Localize.Unit.humanize!(&1, [])},
      {"Localize.Unit.convert!/2", @not_units, &Localize.Unit.convert!(&1, "foot")},
      {"Localize.Unit.display_name!/2", [nil, 42, %{}, {1, 2}],
       &Localize.Unit.display_name!(&1, [])},
      {"Localize.Unit.Preference.preferred_units!/2", @not_units,
       &Localize.Unit.Preference.preferred_units!(&1, [])}
    ]

    failures =
      for {name, values, fun} <- cases,
          value <- values,
          exception = catch_error(fun.(value)),
          not localize_exception?(exception),
          do: {name, value, exception}

    assert failures == []
  end
end
