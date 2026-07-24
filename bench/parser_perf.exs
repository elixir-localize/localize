# Parser / parse-path performance harness.
#
#   mix run bench/parser_perf.exs
#
# Measures the parse cost of every parse surface in the library —
# language tags, units, MF2 messages, and the four leex/yecc CLDR
# pattern parsers (decimal formats, datetime formats, plural rules,
# RBNF) — across three regimes:
#
#   * cold    — raw/uncached parse of a representative input
#   * warm    — steady state, cache hit (the cached surfaces)
#   * distinct — high-cardinality stream where caching stops helping
#
# plus a decomposition of the language-tag pipeline (lex → parse →
# canonicalize → likely-subtags/data-load/cache) and the parse cost
# as a fraction of a full formatting operation.
#
# Self-contained (uses :timer.tc, not benchee, so it needs no extra
# dependency). See plans/PARSER_PERFORMANCE_INVESTIGATION.md for the
# July 2026 findings and methodology.

defmodule ParserPerf do
  @warmup 2_000

  # Median µs/op over `runs` timed passes of `iterations` calls of `fun`.
  def measure(fun, iterations \\ 50_000, runs \\ 5) do
    Enum.each(1..@warmup, fn _ -> fun.() end)

    1..runs
    |> Enum.map(fn _ ->
      {micros, _} = :timer.tc(fn -> Enum.each(1..iterations, fn _ -> fun.() end) end)
      micros / iterations
    end)
    |> median()
  end

  # Median µs/op cycling `fun` over a `pool` of distinct inputs — for
  # UNCACHED surfaces, gives a representative varied-input cost.
  def measure_cycle(pool, fun, iterations \\ 50_000, runs \\ 5) do
    inputs = Stream.cycle(pool) |> Enum.take(iterations)
    Enum.each(Enum.take(inputs, @warmup), fun)

    1..runs
    |> Enum.map(fn _ ->
      {micros, _} = :timer.tc(fn -> Enum.each(inputs, fun) end)
      micros / iterations
    end)
    |> median()
  end

  # µs/op for a single pass over a distinct `pool` — for CACHED
  # surfaces, this is the true cold (cache-miss) cost, uncontaminated
  # by warm hits on a second pass.
  def measure_pool_once(pool, fun) do
    {micros, _} = :timer.tc(fn -> Enum.each(pool, fun) end)
    micros / length(pool)
  end

  defp median(list) do
    sorted = Enum.sort(list)
    Enum.at(sorted, div(length(sorted), 2))
  end

  def row(label, us), do: :io.format("~-44s ~10.3f us/op~n", [label, us])
  def section(title), do: IO.puts("\n== #{title} ==")

  # Erase Localize's persistent_term locale caches so the next pass
  # over a distinct pool is genuinely cold.
  def clear_locale_cache do
    :persistent_term.get()
    |> Enum.each(fn
      {{Localize.Locale, _} = k, _} -> :persistent_term.erase(k)
      {{Localize.Locale.Provider.PersistentTerm, _} = k, _} -> :persistent_term.erase(k)
      _ -> :ok
    end)
  end
end

alias ParserPerf, as: P

# ── Input pools ───────────────────────────────────────────────────

langs =
  ~w(en fr de es it pt nl sv da nb fi pl cs ru uk ja ko zh ar he th vi id ms tr el hu ro bg hr sk sl et lv lt)

regions =
  ~w(US GB CA AU FR DE ES IT PT BR NL SE DK NO FI PL CZ RU UA JP KR CN TW SA IL TH VN ID MY TR AT CH BE)

u_variants = ["", "-u-nu-latn", "-u-ca-gregory", "-u-nu-arab", "-u-co-phonebk", "-u-hc-h23"]

locale_pool =
  for(l <- langs, r <- regions, u <- u_variants, do: "#{l}-#{r}#{u}")
  |> Enum.filter(&match?({:ok, _}, Localize.validate_locale(&1)))

pattern_pool =
  for digits <- 1..6, frac <- 0..4 do
    frac_part = if frac > 0, do: "." <> String.duplicate("0", frac), else: ""
    String.duplicate("#", digits) <> ",##0" <> frac_part
  end

unit_pool =
  ~w(kilometer meter mile foot kilogram gram pound ounce liter gallon
     celsius fahrenheit kilometer-per-hour meter-per-second byte kilobyte
     megabyte watt kilowatt hour minute second hectare acre)

message_pool = [
  "Hello {$name}!",
  "You have {$count :number} messages.",
  ".match {$count :number} one {{{$count} item}} * {{{$count} items}}",
  "The {$item} costs {$price :currency currency=USD}.",
  "{$a} and {$b} and {$c}",
  "Plain text with no placeholders at all."
]

P.clear_locale_cache()
IO.puts("locale pool: #{length(locale_pool)} distinct valid locales")

# ── Cold parse cost (raw/uncached entry, representative input) ─────

P.section("Cold parse cost (raw/uncached entry)")

P.row(
  "rfc5646 lex+parse (nimble_parsec)",
  P.measure(fn -> Localize.Rfc5646.Parser.parse(:language_tag, "en-US") end)
)

P.row(
  "language_tag parse (+struct+canon)",
  P.measure(fn -> Localize.LanguageTag.parse("en-US") end)
)

P.row(
  "unit new (nimble_parsec)",
  P.measure_cycle(unit_pool, fn id -> Localize.Unit.new(1, id) end)
)

P.row(
  "mf2 parse (nimble_parsec)",
  P.measure_cycle(message_pool, &Localize.Message.Parser.parse/1)
)

P.row(
  "decimal pattern (leex/yecc, raw)",
  P.measure(fn -> Localize.Number.Format.Compiler.format_to_metadata("#,##0.00") end)
)

P.row(
  "datetime pattern (leex tokenize)",
  P.measure(fn -> Localize.DateTime.Format.Compiler.tokenize("y-MM-dd HH:mm") end)
)

P.row(
  "plural rule (leex/yecc)",
  P.measure(fn -> Localize.Number.PluralRule.Compiler.parse("i = 1 and v = 0") end)
)

P.row(
  "rbnf rule (leex/yecc)",
  P.measure(fn -> Localize.Number.Rbnf.Rule.parse("=%spellout-numbering=") end)
)

# ── Warm cost (cache hit, steady state) ────────────────────────────

P.section("Warm cost (cache hit, steady state)")

P.row(
  "validate_locale warm (persistent_term)",
  P.measure(fn -> Localize.validate_locale("en-US") end)
)

P.row(
  "decimal pattern warm (FormatCache)",
  P.measure(fn -> Localize.Number.Formatter.Decimal.metadata("#,##0.00") end)
)

# ── High-cardinality (distinct inputs — caching stops helping) ─────

P.section("High-cardinality: distinct-input cost")
P.clear_locale_cache()

P.row(
  "validate_locale distinct (full pipeline)",
  P.measure_pool_once(locale_pool, &Localize.validate_locale/1)
)

P.row(
  "decimal pattern distinct (raw compile)",
  P.measure_pool_once(pattern_pool, fn p ->
    Localize.Number.Format.Compiler.format_to_metadata(p)
  end)
)

# ── Language-tag pipeline decomposition ────────────────────────────
# Deltas isolate each stage:
#   rfc5646            = lex + parse
#   language_tag parse = + struct build + canonicalize
#   validate_locale    = + likely-subtags + first-touch data load + cache

P.section("Language-tag pipeline decomposition")
lex = P.measure(fn -> Localize.Rfc5646.Parser.parse(:language_tag, "en-US") end)
lt = P.measure(fn -> Localize.LanguageTag.parse("en-US") end)
P.clear_locale_cache()
cold_full = P.measure_pool_once(locale_pool, &Localize.validate_locale/1)
P.row("  lex+parse", lex)
P.row("  + struct/canonicalize (delta)", lt - lex)
P.row("  + likely-subtags/data-load/cache (delta)", cold_full - lt)
P.row("  = cold full pipeline", cold_full)

# ── Parse cost as a fraction of the full operation ─────────────────

P.section("Parse cost as a fraction of the full operation")

novel_patterns =
  for a <- 1..6, b <- 1..5 do
    String.duplicate("#", a) <> ",##0." <> String.duplicate("0", b) <> "%"
  end

parse_only =
  P.measure_pool_once(pattern_pool, fn p ->
    Localize.Number.Format.Compiler.format_to_metadata(p)
  end)

full_op =
  P.measure_pool_once(novel_patterns, fn p -> Localize.Number.to_string(1234.5, format: p) end)

P.row("decimal pattern parse (per op)", parse_only)
P.row("full to_string, novel pattern (per op)", full_op)

IO.puts("\nDone.")
