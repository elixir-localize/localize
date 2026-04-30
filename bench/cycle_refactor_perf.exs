# Benchmark targeting the hot paths that changed during the
# compile-cycle refactor (Phases 1–4): functions whose call sites
# moved from compile-time module attributes to runtime
# `:persistent_term`-cached function calls.
#
# Run with:
#
#     MIX_ENV=bench mix run bench/cycle_refactor_perf.exs
#
# Each scenario warms its persistent_term cache once before
# Benchee starts, so we measure steady-state lookup cost (not the
# first-call build cost).

# Warm caches by invoking each path once.
_ = Localize.validate_calendar("gregorian")
_ = Localize.validate_number_system("latn")
_ = Localize.available_locale_id?("en-AU")
{:ok, en_au_tag} = Localize.LanguageTag.parse("en-AU")
_ = Localize.LanguageTag.canonicalize(en_au_tag)
_ = Localize.Locale.parent("en-AU")
_ = Localize.Currency.validate_currency("USD")
_ = Localize.Calendar.first_day_for_territory(:US)
_ = Localize.Calendar.weekend(:US)
_ = Localize.DateTime.Timezone.territories_by_timezone()
_ = Localize.DateTime.Timezone.fetch_short_zone("ausyd")
_ = Localize.Unit.Conversion.convert(1, "kilometer", "meter")
_ = Localize.Unit.BaseUnit.base_unit("foot")

{:ok, alias_tag} = Localize.LanguageTag.parse("zh-CN")

Benchee.run(
  %{
    "validate_calendar/1 (string)" => fn ->
      Localize.validate_calendar("gregorian")
    end,
    "validate_number_system/1 (string)" => fn ->
      Localize.validate_number_system("latn")
    end,
    "available_locale_id?/1 (string)" => fn ->
      Localize.available_locale_id?("en-AU")
    end,
    "available_locale_id?/1 (unknown)" => fn ->
      Localize.available_locale_id?("xx-YY-ZZZZ")
    end,
    "LanguageTag.canonicalize/1 (alias)" => fn ->
      Localize.LanguageTag.canonicalize(alias_tag)
    end,
    "Locale.parent/1 (en-AU)" => fn ->
      Localize.Locale.parent("en-AU")
    end,
    "Currency.validate_currency/1 (atom)" => fn ->
      Localize.Currency.validate_currency(:USD)
    end,
    "Currency.known_currency_codes/0" => fn ->
      Localize.Currency.known_currency_codes()
    end,
    "Calendar.first_day_for_territory/1" => fn ->
      Localize.Calendar.first_day_for_territory(:US)
    end,
    "Calendar.weekend/1" => fn ->
      Localize.Calendar.weekend(:US)
    end,
    "Timezone.fetch_short_zone/1" => fn ->
      Localize.DateTime.Timezone.fetch_short_zone("ausyd")
    end,
    "Unit.Conversion.convert/3 (km→m)" => fn ->
      Localize.Unit.Conversion.convert(1, "kilometer", "meter")
    end,
    "Unit.BaseUnit.base_unit/1 (foot)" => fn ->
      Localize.Unit.BaseUnit.base_unit("foot")
    end
  },
  time: 2,
  warmup: 1,
  memory_time: 0,
  print: [benchmarking: false, configuration: false],
  formatters: [{Benchee.Formatters.Console, extended_statistics: false}]
)
