defmodule Localize.WrongTypeFallbackTest do
  @moduledoc """
  The functions the public API builds on answer an argument of the wrong type
  with their documented fallback — an error tuple, `nil`, `false`, `[]`, `""`
  or `:error` — rather than raising.

  """

  use ExUnit.Case, async: true

  defp outcome(fun, value) do
    fun.(value)
  rescue
    exception -> {:raised, exception}
  end

  defp failures(cases) do
    for {name, values, fun, expected} <- cases,
        value <- values,
        result = outcome(fun, value),
        not expected?(expected, value, result),
        do: {name, value, result}
  end

  defp expected?(predicate, _value, result) when is_function(predicate, 1),
    do: predicate.(result)

  defp expected?(predicate, value, result) when is_function(predicate, 2),
    do: predicate.(value, result)

  defp localize_error?({:error, %{__exception__: true} = exception}) do
    String.starts_with?(inspect(exception.__struct__), "Localize.") and
      is_binary(Exception.message(exception))
  end

  defp localize_error?(_result), do: false

  defp message_error?({:error, message}), do: is_binary(message)
  defp message_error?(_result), do: false

  test "number internals" do
    cases = [
      {"Localize.Number.Transliterate.transliterate_digits/2 string", [nil, 42, %{}],
       &Localize.Number.Transliterate.transliterate_digits(&1, %{}), &localize_error?/1},
      {"Localize.Number.Transliterate.transliterate_digits/2 map", [nil, :bogus, 42, "x"],
       &Localize.Number.Transliterate.transliterate_digits("123", &1), &localize_error?/1},
      {"Localize.Number.System.to_system/2", [nil, :bogus, "x", %{}],
       &Localize.Number.System.to_system(&1, :thai), &localize_error?/1},
      {"Localize.Number.System.generate_transliteration_map/2", [nil, 42, :bogus],
       &Localize.Number.System.generate_transliteration_map(&1, "0123456789"),
       &localize_error?/1},
      {"Localize.Number.Symbol.number_symbols_for/2", [42, %{}, {1, 2}],
       &Localize.Number.Symbol.number_symbols_for(:en, &1), &localize_error?/1},
      {"Localize.Number.Format.Compiler.tokenize/1", [nil, 42, %{}],
       &Localize.Number.Format.Compiler.tokenize/1,
       &match?({:error, %Localize.InvalidValueError{}, 1}, &1)},
      {"Localize.Number.Format.Compiler.parse/1", [42, %{}, {1, 2}, [1]],
       &Localize.Number.Format.Compiler.parse/1, &message_error?/1},
      {"Localize.Number.Format.Compiler.compile/1", [nil, 42, %{}, [1]],
       &Localize.Number.Format.Compiler.compile/1, &message_error?/1},
      {"Localize.Number.Format.Compiler.format_to_metadata/1",
       [nil, 42, %{}, [1], [positive: :bogus]],
       &Localize.Number.Format.Compiler.format_to_metadata/1, &message_error?/1},
      {"Localize.Number.Parser.resolve/3 list", [nil, :bogus, "x"],
       &Localize.Number.Parser.resolve(&1, fn _string, _options -> nil end, []),
       &localize_error?/1},
      {"Localize.Number.Parser.resolve/3 resolver", [nil, :bogus, fn -> 1 end],
       &Localize.Number.Parser.resolve(["x"], &1, []), &localize_error?/1},
      {"Localize.Number.Parser.find_and_replace/3 map", [nil, :bogus, [1]],
       &Localize.Number.Parser.find_and_replace(&1, "x"), &localize_error?/1},
      {"Localize.Number.Parser.find_and_replace/3 string", [nil, 42, :bogus],
       &Localize.Number.Parser.find_and_replace(%{}, &1), &localize_error?/1},
      {"Localize.Number.PluralRule.plural_type/2", [nil, :bogus, %{}],
       &Localize.Number.PluralRule.plural_type(&1, []), &localize_error?/1},
      {"Localize.Number.PluralRule.Cardinal.plural_rule/3 rounding", [0, -1, :bogus, "x"],
       &Localize.Number.PluralRule.Cardinal.plural_rule(1.5, :en, &1), &localize_error?/1},
      {"Localize.Number.PluralRule.Ordinal.plural_rule/3 rounding", [0, -1, :bogus, "x"],
       &Localize.Number.PluralRule.Ordinal.plural_rule(1.5, :en, &1), &localize_error?/1},
      {"Localize.Number.PluralRule.Ordinal.pluralize/3 number", [nil, :bogus, "x", %{}],
       &Localize.Number.PluralRule.Ordinal.pluralize(&1, :en, %{other: "x"}), &localize_error?/1},
      {"Localize.Number.PluralRule.Range.plural_rule/3 end category", [42, "x", :bogus],
       &Localize.Number.PluralRule.Range.plural_rule(:one, &1, :en), &localize_error?/1},
      {"Localize.Number.PluralRule.Range.plural_rule_for/3", [nil, :bogus],
       &Localize.Number.PluralRule.Range.plural_rule_for(&1, 2, :en), &localize_error?/1}
    ]

    assert failures(cases) == []
  end

  test "unit internals" do
    unit = Localize.Unit.new!(1, "meter")
    no_value = Localize.Unit.new!("meter")
    not_units = [nil, :bogus, 42, "meter"]

    single =
      for {name, fun} <- [
            {"negate/1", &Localize.Unit.Math.negate/1},
            {"invert/1", &Localize.Unit.Math.invert/1},
            {"abs/1", &Localize.Unit.Math.abs/1},
            {"ceil/1", &Localize.Unit.Math.ceil/1},
            {"floor/1", &Localize.Unit.Math.floor/1},
            {"trunc/1", &Localize.Unit.Math.trunc/1},
            {"sqrt/1", &Localize.Unit.Math.sqrt/1},
            {"cbrt/1", &Localize.Unit.Math.cbrt/1}
          ] do
        {"Localize.Unit.Math.#{name}", not_units, fun, &localize_error?/1}
      end

    cases =
      single ++
        [
          {"Localize.Unit.Math.add/2", [nil, 42, "meter"], &Localize.Unit.Math.add(unit, &1),
           &localize_error?/1},
          {"Localize.Unit.Math.sub/2", [nil, 42, "meter"], &Localize.Unit.Math.sub(unit, &1),
           &localize_error?/1},
          {"Localize.Unit.Math.mult/2 unit", [nil, :bogus, "meter", no_value],
           &Localize.Unit.Math.mult(&1, 2), &localize_error?/1},
          {"Localize.Unit.Math.mult/2 multiplier", [nil, :bogus, "x", %{}],
           &Localize.Unit.Math.mult(unit, &1), &localize_error?/1},
          {"Localize.Unit.Math.div/2 unit", [nil, :bogus, "meter", no_value],
           &Localize.Unit.Math.div(&1, 2), &localize_error?/1},
          {"Localize.Unit.Math.div/2 divisor", [nil, :bogus, "x", %{}],
           &Localize.Unit.Math.div(unit, &1), &localize_error?/1},
          {"Localize.Unit.Math.round/3 unit", [nil, :bogus, 42],
           &Localize.Unit.Math.round(&1, 0, :half_up), &localize_error?/1},
          {"Localize.Unit.Math.round/3 mode", [:bogus, "x", 42],
           &Localize.Unit.Math.round(unit, 0, &1), &localize_error?/1},
          {"Localize.Unit.Math.sin/1", [nil, 42], &Localize.Unit.Math.sin/1, &message_error?/1},
          {"Localize.Unit.Math.apply_dimensionless/2", [:bogus, "x"],
           &Localize.Unit.Math.apply_dimensionless(&1, unit), &message_error?/1},
          {"Localize.Unit.BaseUnit.base_unit/1", [nil, 42, %{}],
           &Localize.Unit.BaseUnit.base_unit/1, &localize_error?/1},
          {"Localize.Unit.BaseUnit.decompose/1", [nil, 42, "meter", %{}],
           &Localize.Unit.BaseUnit.decompose/1, &localize_error?/1},
          {"Localize.Unit.BaseUnit.recompose/1", [nil, 42, "x", [1]],
           &Localize.Unit.BaseUnit.recompose/1, &localize_error?/1},
          {"Localize.Unit.Canonical.canonicalize/1", [nil, 42, "meter"],
           &Localize.Unit.Canonical.canonicalize/1, &localize_error?/1},
          {"Localize.Unit.Canonical.from_components/2 numerator", [nil, 42, "x"],
           &Localize.Unit.Canonical.from_components(&1, []), &localize_error?/1},
          {"Localize.Unit.Canonical.from_components/2 denominator", [nil, 42, "x"],
           &Localize.Unit.Canonical.from_components([], &1), &localize_error?/1},
          {"Localize.Unit.Conversion.convert/3", [nil, :bogus, "x"],
           &Localize.Unit.Conversion.convert(&1, "meter", "foot"), &localize_error?/1},
          {"Localize.Unit.CustomRegistry.load_file/1", [nil, 42, :bogus],
           &Localize.Unit.CustomRegistry.load_file/1, &message_error?/1},
          {"Localize.Unit.CustomRegistry.register_batch/1", [nil, 42, "x", [1]],
           &Localize.Unit.CustomRegistry.register_batch/1, &localize_error?/1},
          {"Localize.Unit.Data.si_prefix_atom/1", [nil, 42, :kilo],
           &Localize.Unit.Data.si_prefix_atom/1, &is_nil/1},
          {"Localize.Unit.Parser.parse/1", [nil, 42, %{}], &Localize.Unit.Parser.parse/1,
           &localize_error?/1},
          {"Localize.Unit.Parser.unit_identifier/2 binary", [nil, 42, %{}],
           &Localize.Unit.Parser.unit_identifier/1,
           &match?({:error, _message, "", %{}, {1, 0}, 0}, &1)},
          {"Localize.Unit.Parser.unit_identifier/2 options", [:bogus, 42, %{}],
           &Localize.Unit.Parser.unit_identifier("meter", &1),
           &match?({:error, _message, "", %{}, {1, 0}, 0}, &1)}
        ]

    assert failures(cases) == []
  end

  test "message, list, locale and date internals" do
    {:ok, tokens} = Localize.Message.to_tokens("Hello")

    cases = [
      {"Localize.Message.Formatter.Plain.render/1", [nil, :bogus, 42, "x"],
       &Localize.Message.Formatter.Plain.render/1, &localize_error?/1},
      {"Localize.Message.Formatter.render/3", [:bogus, nil, "html"],
       &Localize.Message.Formatter.render(tokens, &1, []), &localize_error?/1},
      {"Localize.Message.Formatter.HTML.render/2 :span_tag", [42, :bogus, %{}],
       &Localize.Message.Formatter.HTML.render(tokens, span_tag: &1), &localize_error?/1},
      {"Localize.Message.Formatter.HTML.render/2 :class_prefix", [42, :bogus, %{}],
       &Localize.Message.Formatter.HTML.render(tokens, class_prefix: &1), &localize_error?/1},
      {"Localize.Message.Formatter.ANSI.render/2 :palette",
       [:bogus, 42, %{variable: [:not_a_colour]}, %{variable: :red}],
       &Localize.Message.Formatter.ANSI.render(tokens, palette: &1), &localize_error?/1},
      {"Localize.List.Pattern.new/1", [nil, :bogus, 42, "x"], &Localize.List.Pattern.new/1,
       &localize_error?/1},
      {"Localize.List.Pattern.from_locale_data/1", [nil, :bogus, 42, [1]],
       &Localize.List.Pattern.from_locale_data/1, &localize_error?/1},
      {"Localize.LanguageTag.U.parse/1", [nil, 42, %{}, [1]], &Localize.LanguageTag.U.parse/1,
       &localize_error?/1},
      {"Localize.LanguageTag.U.encode/1", [nil, 42, "x", %{}], &Localize.LanguageTag.U.encode/1,
       &localize_error?/1},
      {"Localize.Locale.locale_id_from_posix/1", [nil, 42, %{}],
       &Localize.Locale.locale_id_from_posix/1, &localize_error?/1},
      {"Localize.Locale.locale_id_from/4", [42, %{}, {1, 2}],
       &Localize.Locale.locale_id_from(&1, nil, nil, []), &localize_error?/1},
      {"Localize.Locale.gettext_locale_id/2", ["x", 42, %{}],
       &Localize.Locale.gettext_locale_id(:en, &1), &localize_error?/1},
      {"Localize.Locale.expand_locale_list/2", [nil, :bogus, 42, "x"],
       &Localize.Locale.expand_locale_list/1, &localize_error?/1},
      {"Localize.Locale.store/3 locale id", ["en", 42, %{}], &Localize.Locale.store(&1, %{}, []),
       &localize_error?/1},
      {"Localize.Locale.store/3 locale data", [nil, "x", 42, [1]],
       &Localize.Locale.store(:en, &1, []), &localize_error?/1},
      {"Localize.Script.display_name/2", [42, %{}, {1, 2}], &Localize.Script.display_name(&1, []),
       &localize_error?/1},
      {"Localize.DateTime.SemanticSkeleton.new/2", [nil, 42, %{}],
       &Localize.DateTime.SemanticSkeleton.new(&1, []), &localize_error?/1},
      {"Localize.DateTime.SemanticSkeleton.to_classical_skeleton/2", [nil, :bogus, "YMD", %{}],
       &Localize.DateTime.SemanticSkeleton.to_classical_skeleton/1, &localize_error?/1}
    ]

    assert failures(cases) == []
  end

  test "inflection internals" do
    not_concepts = [nil, 42, %{}]

    cases = [
      {"Localize.Inflection.inflect/3 phrase", [nil, 42, %{}],
       &Localize.Inflection.inflect(&1, :de, %{}), &localize_error?/1},
      {"Localize.Inflection.inflect/3 constraints", [:bogus, 42, "x"],
       &Localize.Inflection.inflect("Haus", :de, &1), &localize_error?/1},
      {"Localize.Inflection.feature/3", [42, %{}, {1, 2}],
       &Localize.Inflection.feature("Haus", :de, &1), &localize_error?/1},
      {"Localize.Inflection.known?/2", [nil, 42, %{}], &Localize.Inflection.known?(&1, :de),
       &(&1 == false)},
      {"Localize.Inflection.pronoun/3", [:bogus, 42, "x"],
       &Localize.Inflection.pronoun(:en, nil, &1), &localize_error?/1},
      {"Localize.Inflection.quantify/4", [:bogus, 42, %{}],
       &Localize.Inflection.quantify("1", "day", :en, &1), &localize_error?/1},
      {"Localize.Inflection.Feature.to_internal/1", [42, %{}, {1, 2}],
       &Localize.Inflection.Feature.to_internal/1, &(&2 == inspect(&1))},
      {"Localize.Inflection.Feature.normalize_constraints/1", [nil, :bogus, 42, "x"],
       &Localize.Inflection.Feature.normalize_constraints/1, &(&1 == %{})},
      {"Localize.Inflection.Feature.constraints/1", [nil, :bogus, 42, "x"],
       &Localize.Inflection.Feature.constraints/1, &localize_error?/1},
      {"Localize.Inflection.Dictionary.binary_properties/2", [nil, :bogus, "x", %{}],
       &Localize.Inflection.Dictionary.binary_properties(:de, &1), &is_nil/1},
      {"Localize.Inflection.Dictionary.property_name/2", [nil, :bogus, "x", -1],
       &Localize.Inflection.Dictionary.property_name(:de, &1), &is_nil/1},
      {"Localize.Inflection.Dictionary.property_names/2", [nil, :bogus, "x"],
       &Localize.Inflection.Dictionary.property_names(:de, &1), &(&1 == [])},
      {"Localize.Inflection.Dictionary.has_all_properties?/3", [nil, :bogus, "x"],
       &Localize.Inflection.Dictionary.has_all_properties?(:de, "Haus", &1), &(&1 == false)},
      {"Localize.Inflection.Dictionary.matching_inflections/3", [nil, :bogus, %{}],
       &Localize.Inflection.Dictionary.matching_inflections("Haus", 0, &1), &(&1 == [])},
      {"Localize.Inflection.Data.metadata/1", ["de", 42, %{}],
       &Localize.Inflection.Data.metadata/1, &(&2 == {:error, {:invalid_locale, &1}})},
      {"Localize.Inflection.Data.lookup/2 locale", ["de", 42],
       &Localize.Inflection.Data.lookup(&1, "Haus"), &is_nil/1},
      {"Localize.Inflection.Data.lookup/2 word", [nil, 42, :bogus],
       &Localize.Inflection.Data.lookup(:de, &1), &is_nil/1},
      {"Localize.Inflection.Locale.normalize/1", [42, %{}, {1, 2}, [1]],
       &Localize.Inflection.Locale.normalize/1, &(&1 == "")},
      {"Localize.Inflection.Inflector.inflect/5 word", [nil, 42, %{}],
       &Localize.Inflection.Inflector.inflect(:de, &1, 1, [], []), &(&1 == :error)},
      {"Localize.Inflection.Inflector.inflect/5 constraints", [%{}, :bogus],
       &Localize.Inflection.Inflector.inflect(:de, "Haus", 1, &1, []), &(&1 == :error)},
      {"Localize.Inflection.Inflector.inflect_word/5", [:bogus, "x", %{}],
       &Localize.Inflection.Inflector.inflect_word(:de, "Haus", &1, [], []), &(&1 == :error)},
      {"Localize.Inflection.Inflector.reinflect/6", [nil, 42, %{}],
       &Localize.Inflection.Inflector.reinflect(&1, 0, 1, [], "Haus", :first), &(&1 == :error)},
      {"Localize.Inflection.Provider.file_url/1", [nil, 42, :bogus],
       &Localize.Inflection.Provider.file_url/1, &localize_error?/1},
      {"Localize.Inflection.Provider.download_file/1", [nil, 42, :bogus],
       &Localize.Inflection.Provider.download_file/1, &localize_error?/1},
      {"Localize.Inflection.SpeakableString.speak/1", [nil, :bogus, 42, %{}],
       &Localize.Inflection.SpeakableString.speak/1, &localize_error?/1},
      {"Localize.Inflection.SpeakableString.concat/2 left", [nil, 42, %{}],
       &Localize.Inflection.SpeakableString.concat(&1, "x"), &localize_error?/1},
      {"Localize.Inflection.SpeakableString.concat/2 right", [nil, 42, %{}],
       &Localize.Inflection.SpeakableString.concat("x", &1), &localize_error?/1},
      {"Localize.Inflection.Concept.new/3", [nil, 42, %{}, {1, 2}],
       &Localize.Inflection.Concept.new(:de, &1), &localize_error?/1},
      {"Localize.Inflection.Concept.put_constraint/3", not_concepts,
       &Localize.Inflection.Concept.put_constraint(&1, :case, "dative"), &localize_error?/1},
      {"Localize.Inflection.Concept.feature_value/2", not_concepts,
       &Localize.Inflection.Concept.feature_value(&1, :case), &is_nil/1},
      {"Localize.Inflection.Concept.exists?/1", not_concepts,
       &Localize.Inflection.Concept.exists?/1, &(&1 == false)},
      {"Localize.Inflection.Concept.to_speakable_string/1", not_concepts,
       &Localize.Inflection.Concept.to_speakable_string/1, &localize_error?/1},
      {"Localize.Inflection.ConceptList.and_list/2 locale", [42, %{}, {1, 2}],
       &Localize.Inflection.ConceptList.and_list(&1, []), &localize_error?/1},
      {"Localize.Inflection.ConceptList.and_list/2 concepts", [nil, :bogus, "x", %{}],
       &Localize.Inflection.ConceptList.and_list(:de, &1), &localize_error?/1},
      {"Localize.Inflection.ConceptList.or_list/2 concepts", [nil, :bogus, "x", %{}],
       &Localize.Inflection.ConceptList.or_list(:de, &1), &localize_error?/1},
      {"Localize.Inflection.ConceptList.put_separator/3", [nil, 42],
       &Localize.Inflection.ConceptList.put_separator(&1, :item_delimiter, ", "),
       &localize_error?/1},
      {"Localize.Inflection.ConceptList.size/1", not_concepts,
       &Localize.Inflection.ConceptList.size/1, &localize_error?/1},
      {"Localize.Inflection.ConceptList.exists?/1", not_concepts,
       &Localize.Inflection.ConceptList.exists?/1, &(&1 == false)},
      {"Localize.Inflection.ConceptList.put_constraint/3", not_concepts,
       &Localize.Inflection.ConceptList.put_constraint(&1, :case, "dative"), &localize_error?/1},
      {"Localize.Inflection.ConceptList.feature_value/2", not_concepts,
       &Localize.Inflection.ConceptList.feature_value(&1, :case), &is_nil/1},
      {"Localize.Inflection.ConceptList.to_speakable_string/1", not_concepts,
       &Localize.Inflection.ConceptList.to_speakable_string/1, &localize_error?/1},
      {"Localize.Inflection.PronounConcept.put_constraint/3", not_concepts,
       &Localize.Inflection.PronounConcept.put_constraint(&1, :case, "dative"),
       &localize_error?/1},
      {"Localize.Inflection.PronounConcept.clear_constraint/2", not_concepts,
       &Localize.Inflection.PronounConcept.clear_constraint(&1, :case), &localize_error?/1},
      {"Localize.Inflection.PronounConcept.reset/1", not_concepts,
       &Localize.Inflection.PronounConcept.reset/1, &localize_error?/1},
      {"Localize.Inflection.PronounConcept.feature_value/2", not_concepts,
       &Localize.Inflection.PronounConcept.feature_value(&1, :case), &is_nil/1},
      {"Localize.Inflection.PronounConcept.exists?/1", not_concepts,
       &Localize.Inflection.PronounConcept.exists?/1, &(&1 == false)},
      {"Localize.Inflection.PronounConcept.custom_match?/1", not_concepts,
       &Localize.Inflection.PronounConcept.custom_match?/1, &(&1 == false)},
      {"Localize.Inflection.PronounConcept.to_speakable_string/2", not_concepts,
       &Localize.Inflection.PronounConcept.to_speakable_string/1, &is_nil/1},
      {"Localize.Inflection.Quantify.quantify_formatted/4 concept", [nil, 42, "day"],
       &Localize.Inflection.Quantify.quantify_formatted(:en, "1", &1, []), &localize_error?/1},
      {"Localize.Inflection.Quantify.quantify_formatted/4 locale", [42, %{}],
       &Localize.Inflection.Quantify.quantify_formatted(&1, "1", nil, []), &localize_error?/1},
      {"Localize.Inflection.Quantify.quantify_formatted/4 options", [:bogus, 42],
       &Localize.Inflection.Quantify.quantify_formatted(:en, "1", nil, &1), &localize_error?/1}
    ]

    assert failures(cases) == []
  end

  test "validity checks and exception messages" do
    cases = [
      {"Localize.Validity.Language.validate/1", [42, 1.5, %{}, {1, 2}, [1]],
       &Localize.Validity.Language.validate/1, &(&2 == {:error, &1})},
      {"Localize.Validity.Script.validate/1", [42, 1.5, %{}, {1, 2}, [1]],
       &Localize.Validity.Script.validate/1, &(&2 == {:error, &1})},
      {"Localize.Validity.Subdivision.validate/1", [42, 1.5, %{}, {1, 2}, [1]],
       &Localize.Validity.Subdivision.validate/1, &(&2 == {:error, &1})},
      {"Localize.Validity.Unit.validate/1", [42, 1.5, %{}, {1, 2}, [1]],
       &Localize.Validity.Unit.validate/1, &(&2 == {:error, &1})},
      {"Localize.Validity.Territory.validate/1", [1.5, %{}, {1, 2}, [1]],
       &Localize.Validity.Territory.validate/1, &(&2 == {:error, &1})},
      {"Localize.Validity.Variant.validate/1", [42, :bogus, %{}, {1, 2}],
       &Localize.Validity.Variant.validate/1, &(&2 == {:error, &1})},
      {"Localize.Exception.safe_message/3 context", [42, nil, %{}],
       &Localize.Exception.safe_message(&1, "Hello", []), &(&1 == "Hello")},
      {"Localize.Exception.safe_message/3 message", [42, nil, %{}],
       &Localize.Exception.safe_message("unit", &1, []), &(&2 == inspect(&1))},
      {"Localize.Exception.safe_message/3 bindings", [:bogus, 42, %{}],
       &Localize.Exception.safe_message("unit", "Hello", &1), &(&1 == "Hello")},
      {"Localize.ParseError.line_column/2 input", [nil, 42, %{}],
       &Localize.ParseError.line_column(&1, 0), &(&1 == {1, 1})},
      {"Localize.ParseError.line_column/2 offset", [nil, -1, "x"],
       &Localize.ParseError.line_column("abc", &1), &(&1 == {1, 1})}
    ]

    assert failures(cases) == []
  end

  test "further argument positions and option values" do
    unit = Localize.Unit.new!(1, "meter")
    no_value = Localize.Unit.new!("meter")
    duration = %Localize.Duration{hour: 1}
    zoned = %{time_zone: "America/New_York", utc_offset: -18_000, std_offset: 0}
    tag = Localize.LanguageTag.parse!("en")
    distance = Localize.LanguageTag.default_distance()
    {:ok, tokens} = Localize.Message.to_tokens("Hello")
    returns? = &(not match?({:raised, _exception}, &1))

    expand_quietly = fn entry ->
      {result, _log} =
        ExUnit.CaptureLog.with_log(fn -> Localize.Locale.expand_locale_list([entry]) end)

      result
    end

    cases = [
      {"Localize.ellipsis/2 :format", [:bogus, 42], &Localize.ellipsis("abc def", format: &1),
       &localize_error?/1},
      {"Localize.ellipsis/2 :location", [:bogus, 42], &Localize.ellipsis("abc def", location: &1),
       &localize_error?/1},
      {"Localize.ellipsis/2 list :location", [:bogus, 42],
       &Localize.ellipsis(["abc", "def"], location: &1), &localize_error?/1},
      {"Localize.put_supported_locales/1", [:bogus, 42, "x", [1]],
       &Localize.put_supported_locales/1, &localize_error?/1},
      {"Localize.Calendar.min_days_for_territory/1", [42, %{}],
       &Localize.Calendar.min_days_for_territory/1, &localize_error?/1},
      {"Localize.Calendar.weekdays/1", [42, %{}], &Localize.Calendar.weekdays/1,
       &localize_error?/1},
      {"Localize.Collation.compare/3 second string", [nil, 42],
       &Localize.Collation.compare("a", &1, []), &localize_error?/1},
      {"Localize.Collation.compare/3 :locale", [42, %{}],
       &Localize.Collation.compare("a", "b", locale: &1), &localize_error?/1},
      {"Localize.Collation.compare/3 unparseable locale", ["x x"],
       &Localize.Collation.compare("a", "b", locale: &1), returns?},
      {"Localize.Collation.compare/3 options struct", [Localize.Collation.Options.new()],
       &Localize.Collation.compare("a", "b", &1), returns?},
      {"Localize.Collation.sort/2 members", [42, nil], &Localize.Collation.sort(["a", &1], []),
       &localize_error?/1},
      {"Localize.Collation.sort_key/2 code points", [-1, 0x110000],
       &Localize.Collation.sort_key([&1], []), &localize_error?/1},
      {"Localize.Collation.Options.from_locale/1", [42, %{}],
       &Localize.Collation.Options.from_locale/1, &localize_error?/1},
      {"Localize.Currency.current_currency_for_territory/1", [42, %{}],
       &Localize.Currency.current_currency_for_territory/1, &is_nil/1},
      {"Localize.Currency.currency_format_from_locale/1", [42, %{}],
       &Localize.Currency.currency_format_from_locale/1, &localize_error?/1},
      {"Localize.Currency.currency_history_for_locale/1", [42, %{}],
       &Localize.Currency.currency_history_for_locale/1, &localize_error?/1},
      {"Localize.Currency.currency_filter/3", [:bogus, 42, "x"],
       &Localize.Currency.currency_filter(&1, :all, nil), &localize_error?/1},
      {"Localize.Currency.currencies_for_locale/2 :only", [42, 1.5, %{}],
       &Localize.Currency.currencies_for_locale(:en, only: &1), &localize_error?/1},
      {"Localize.DateTime.Timezone.short_zone_id/1", [42, nil, %{}],
       &Localize.DateTime.Timezone.short_zone_id/1, returns?},
      {"Localize.DateTime.Timezone.parse_offset/2 options", [:bogus, 42],
       &Localize.DateTime.Timezone.parse_offset("+05:00", &1), &localize_error?/1},
      {"Localize.DateTime.Timezone.iso_format/2 datetime", [%{}, %{utc_offset: "x"}],
       &Localize.DateTime.Timezone.iso_format(&1, []), &localize_error?/1},
      {"Localize.DateTime.Timezone.iso_format/2 :format", [:bogus, 42],
       &Localize.DateTime.Timezone.iso_format(zoned, format: &1), &localize_error?/1},
      {"Localize.DateTime.Timezone.exemplar_city/3 options", [:bogus, 42],
       &Localize.DateTime.Timezone.exemplar_city("America/New_York", :en, &1),
       &localize_error?/1},
      {"Localize.DateTime.Timezone.exemplar_city/3 zone", [42, nil],
       &Localize.DateTime.Timezone.exemplar_city(&1, :en, []), &localize_error?/1},
      {"Localize.DateTime.Timezone.location_name/3 options", [:bogus, 42],
       &Localize.DateTime.Timezone.location_name("America/New_York", :en, &1),
       &localize_error?/1},
      {"Localize.DateTime.Timezone.location_name/3 zone", [42, nil],
       &Localize.DateTime.Timezone.location_name(&1, :en, []), &localize_error?/1},
      {"Localize.DateTime.Timezone.non_location_format/3 zone", [nil, 42],
       &Localize.DateTime.Timezone.non_location_format(%{zoned | time_zone: &1}, :en, []),
       returns?},
      {"Localize.Duration.new/1", [42, nil, "x"], &Localize.Duration.new/1, &localize_error?/1},
      {"Localize.Duration.to_parts/2", [nil, :bogus, 42], &Localize.Duration.to_parts(&1, []),
       &localize_error?/1},
      {"Localize.Duration.to_string/2 :display", [:bogus, [hour: :sometimes]],
       &Localize.Duration.to_string(duration, display: &1), &localize_error?/1},
      {"Localize.Duration.to_time_string/2 :format", [42, %{}],
       &Localize.Duration.to_time_string(duration, format: &1), &localize_error?/1},
      {"Localize.Duration.to_time_string!/2", [nil, 42],
       &Localize.Duration.to_time_string!(&1, []), &raised_localize_exception?/1},
      {"Localize.Interval.to_parts/3 options", [:bogus, 42],
       &Localize.Interval.to_parts(~D[2024-07-06], ~D[2024-07-10], &1), &localize_error?/1},
      {"Localize.Interval.to_string/3 open start", [42, "x"],
       &Localize.Interval.to_string(nil, &1, []), &localize_error?/1},
      {"Localize.Interval.greatest_difference/2 to", [nil, 42],
       &Localize.Interval.greatest_difference(~D[2024-01-01], &1), &localize_error?/1},
      {"Localize.Interval.to_string/3 :fields", ["x", 42],
       &Localize.Interval.to_string(~D[2024-07-06], ~D[2024-07-10], fields: &1),
       &localize_error?/1},
      {"Localize.LanguageTag.best_match/3 supported", [:bogus, 42],
       &Localize.LanguageTag.best_match("en", &1, distance), &localize_error?/1},
      {"Localize.LanguageTag.best_match/3 desired", [42, %{}],
       &Localize.LanguageTag.best_match(&1, [:en], distance), &localize_error?/1},
      {"Localize.LanguageTag.remove_likely_subtags!/2", [42, %{}],
       &Localize.LanguageTag.remove_likely_subtags!(&1, []), &raised_localize_exception?/1},
      {"Localize.List.to_parts/2", [nil, :bogus, 42], &Localize.List.to_parts(&1, []),
       &localize_error?/1},
      {"Localize.List.to_string/2 :list_style", [:bogus, 42],
       &Localize.List.to_string(["a", "b"], list_style: &1), &localize_error?/1},
      {"Localize.Language.language_names_for/1", [:bogus, 42],
       &Localize.Language.language_names_for/1, &localize_error?/1},
      {"Localize.Script.script_names_for/1", [:bogus, 42], &Localize.Script.script_names_for/1,
       &localize_error?/1},
      {"Localize.Locale.LocaleDisplay.type_value_name/2 options", [:bogus, 42],
       &Localize.Locale.LocaleDisplay.type_value_name("yes", &1), &localize_error?/1},
      {"Localize.Locale.locale_id_from/4 variants", [:bogus, 42],
       &Localize.Locale.locale_id_from(:en, nil, nil, &1), &localize_error?/1},
      {"Localize.Locale.store/3 options", [:bogus, 42], &Localize.Locale.store(:en, %{}, &1),
       &localize_error?/1},
      {"Localize.Locale.gettext_locale_id/2 backend", [Localize, :bogus],
       &Localize.Locale.gettext_locale_id(:en, &1), &localize_error?/1},
      {"Localize.Locale.gettext_locale_id/2 locale", [42, %{}],
       &Localize.Locale.gettext_locale_id(&1, Localize.Gettext), &localize_error?/1},
      {"Localize.Locale.gettext_locale_id/2 locale forms", [tag, "en"],
       &Localize.Locale.gettext_locale_id(&1, Localize.Gettext), returns?},
      {"Localize.Locale.expand_locale_list/2 entries", [:not_a_locale, 42], expand_quietly,
       &(&1 == [])},
      {"Localize.Message.JSON.to_json/2 ast", [:bogus, 42],
       &Localize.Message.JSON.to_json(&1, []), &localize_error?/1},
      {"Localize.Message.JSON.to_json/2 parts", [:bogus, 42],
       &Localize.Message.JSON.to_json([&1], []), returns?},
      {"Localize.Message.Print.to_string/2 nodes", [:bogus, 42],
       &Localize.Message.Print.to_string([&1], []), returns?},
      {"Localize.Message.Highlighter.to_tokens/1 nodes", [:bogus, 42],
       &Localize.Message.Highlighter.to_tokens([&1]), returns?},
      {"Localize.Message.Formatter.HTML.render/2 tokens", [nil, :bogus, 42],
       &Localize.Message.Formatter.HTML.render(&1, []), &localize_error?/1},
      {"Localize.Message.Formatter.ANSI.render/2 tokens", [nil, :bogus, 42],
       &Localize.Message.Formatter.ANSI.render(&1, []), &localize_error?/1},
      {"Localize.Message.Formatter.ANSI.render/2 palette codes", ["red", 42],
       &Localize.Message.Formatter.ANSI.render(tokens, palette: %{variable: [&1]}),
       &localize_error?/1},
      {"Localize.Number.PluralRule.plural_type/2 :type", [:bogus, 42],
       &Localize.Number.PluralRule.plural_type(1, type: &1), &localize_error?/1},
      {"Localize.Number.PluralRule.Cardinal.pluralize/3 locale", [42, %{}],
       &Localize.Number.PluralRule.Cardinal.pluralize(1, &1, %{other: "x"}), &localize_error?/1},
      {"Localize.Number.PluralRule.Cardinal.plural_rule/2 number string", ["1", "1.50"],
       &Localize.Number.PluralRule.Cardinal.plural_rule(&1, :en), &is_atom/1},
      {"Localize.Number.PluralRule.Ordinal.pluralize/3 locale", [42, %{}],
       &Localize.Number.PluralRule.Ordinal.pluralize(1, &1, %{other: "x"}), &localize_error?/1},
      {"Localize.Number.PluralRule.Ordinal.plural_rule/2 locale", [42, %{}],
       &Localize.Number.PluralRule.Ordinal.plural_rule(1, &1), &localize_error?/1},
      {"Localize.Number.PluralRule.Ordinal.pluralize/3 Decimal",
       [Decimal.new("1E+1"), Decimal.new("1.0"), Decimal.new("1.5")],
       &Localize.Number.PluralRule.Ordinal.pluralize(&1, :en, %{other: "x"}), &(&1 == "x")},
      {"Localize.Territory.translate_territory/3 options", [:bogus, 42],
       &Localize.Territory.translate_territory("Germany", :en, &1), &localize_error?/1},
      {"Localize.Territory.to_territory_code/2", [42, nil, %{}],
       &Localize.Territory.to_territory_code(&1, :en), &localize_error?/1},
      {"Localize.Territory.normalize_name/1", [42, nil, %{}],
       &Localize.Territory.normalize_name/1, returns?},
      {"Localize.Unit.new/3 unit", [42, nil, %{}], &Localize.Unit.new(1, &1, []),
       &localize_error?/1},
      {"Localize.Unit.parse/2 string", [42, nil, %{}], &Localize.Unit.parse(&1, []),
       &localize_error?/1},
      {"Localize.Unit.parse_unit_name/2 options", [:bogus, 42],
       &Localize.Unit.parse_unit_name("meter", &1), &localize_error?/1},
      {"Localize.Unit.parse_unit_name/2 name", [42, nil, %{}],
       &Localize.Unit.parse_unit_name(&1, []), &localize_error?/1},
      {"Localize.Unit.convert/2 target", [42, nil, %{}], &Localize.Unit.convert(unit, &1),
       &localize_error?/1},
      {"Localize.Unit.convert_measurement_system/2", [nil, 42, "meter"],
       &Localize.Unit.convert_measurement_system(&1, :metric), &localize_error?/1},
      {"Localize.Unit.to_range_string/3 end", [nil, 42, "meter"],
       &Localize.Unit.to_range_string(unit, &1, []), &localize_error?/1},
      {"Localize.Unit.to_range_parts/3 start", [nil, 42, "meter"],
       &Localize.Unit.to_range_parts(&1, unit, []), &localize_error?/1},
      {"Localize.Unit.compare/2 second unit", [nil, 42, "meter"],
       &Localize.Unit.compare(unit, &1), &localize_error?/1},
      {"Localize.Unit.decompose/3 targets", [:bogus, 42], &Localize.Unit.decompose(unit, &1, []),
       &localize_error?/1},
      {"Localize.Unit.decompose/3 unit", [nil, 42, "meter"],
       &Localize.Unit.decompose(&1, ["meter"], []), &localize_error?/1},
      {"Localize.Unit.Math.sub/2 first unit", [nil, 42, "meter"],
       &Localize.Unit.Math.sub(&1, unit), &localize_error?/1},
      {"Localize.Unit.Math.mult/2 unit without a value", [no_value],
       &Localize.Unit.Math.mult(unit, &1), &localize_error?/1},
      {"Localize.Unit.Math.div/2 unit without a value", [no_value],
       &Localize.Unit.Math.div(unit, &1), &localize_error?/1},
      {"Localize.Unit.BaseUnit.decompose/1 single unit", [42, nil],
       &Localize.Unit.BaseUnit.decompose({:single_unit, &1}), &localize_error?/1},
      {"Localize.Unit.BaseUnit.decompose/1 unit payload", [42, nil, "x"],
       &Localize.Unit.BaseUnit.decompose({:unit, &1}), &localize_error?/1},
      {"Localize.Unit.BaseUnit.decompose/1 components", [42, :bogus],
       &Localize.Unit.BaseUnit.decompose({:unit, [numerator: &1]}), &localize_error?/1},
      {"Localize.Unit.BaseUnit.decompose/1 single unit base", [[], [base: 42]],
       &Localize.Unit.BaseUnit.decompose({:single_unit, &1}), &localize_error?/1},
      {"Localize.Unit.Canonical.canonicalize/1 unit payload", [42, nil, "x"],
       &Localize.Unit.Canonical.canonicalize({:unit, &1}), &localize_error?/1},
      {"Localize.Unit.Canonical.canonicalize/1 mixed payload", [42, nil, "x"],
       &Localize.Unit.Canonical.canonicalize({:mixed_unit, &1}), &localize_error?/1},
      {"Localize.Inflection.ConceptList.and_list/2 members", [42, "x"],
       &Localize.Inflection.ConceptList.and_list(:de, [&1]), &localize_error?/1},
      {"Localize.Inflection.ConceptList.put_separator/3 field", [:bogus, 42],
       &Localize.Inflection.ConceptList.put_separator(
         %Localize.Inflection.ConceptList{},
         &1,
         ", "
       ), &localize_error?/1},
      {"Localize.Inflection.ConceptList.size/1", [%Localize.Inflection.ConceptList{concepts: []}],
       &Localize.Inflection.ConceptList.size/1, &(&1 == 0)},
      {"Localize.Inflection.pronoun/3 non-pair constraint", [1, "x"],
       &Localize.Inflection.pronoun(:en, nil, [{:person, "first"}, &1]), returns?}
    ]

    assert failures(cases) == []
  end

  defp raised_localize_exception?({:raised, %{__exception__: true} = exception}) do
    String.starts_with?(inspect(exception.__struct__), "Localize.") and
      is_binary(Exception.message(exception))
  end

  defp raised_localize_exception?(_result), do: false
end
