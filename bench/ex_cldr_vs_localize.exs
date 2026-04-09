# Benchmarks comparing ex_cldr_* against Localize.
#
# Run with:
#
#     MIX_ENV=bench mix run bench/ex_cldr_vs_localize.exs
#
# Covers:
#   * Number formatting (decimal, currency, percent)
#   * Date/time formatting (short, medium, long)
#   * Unit formatting (short, long)
#
# Every scenario is exercised in three locales — `:en`, `:de`,
# `:ja` — matching the locales compiled into `Bench.Cldr`. That
# keeps the comparison apples-to-apples: ex_cldr embeds those
# locales in its backend BEAM file, and Localize has them in the
# on-disk ETF cache.
#
# For every library and every locale we run two variants:
#
#   * **raw**        — pass a bare atom (Localize) or string (ex_cldr)
#                      as the `:locale` option. This forces option
#                      validation on every call.
#
#   * **validated**  — pre-compute a `%Localize.LanguageTag{}` (or
#                      `%Cldr.LanguageTag{}`) once, reuse it on
#                      every call. This skips option validation and
#                      isolates the cost of the formatting path
#                      itself, not the locale-resolution path.
#
# Comparing the two variants shows how much of each library's
# per-call cost is option validation vs. formatting proper.

defmodule BenchHelper do
  @moduledoc false

  @doc """
  Returns a list of
  `{label, localize_raw, localize_validated, cldr_raw, cldr_validated}`
  tuples, one per locale. The raw entry is the bare value a user
  would normally pass; the validated entry is the language-tag
  struct produced by calling the library's own `validate_locale/1`
  up front.
  """
  def locales do
    Enum.map(
      [
        {"en", :en, "en"},
        {"de", :de, "de"},
        {"ja", :ja, "ja"}
      ],
      fn {label, localize_raw, cldr_raw} ->
        {:ok, %Localize.LanguageTag{} = localize_tag} =
          Localize.validate_locale(localize_raw)

        {:ok, %Cldr.LanguageTag{} = cldr_tag} =
          Bench.Cldr.validate_locale(cldr_raw)

        {label, localize_raw, localize_tag, cldr_raw, cldr_tag}
      end
    )
  end

  def number_inputs do
    [
      {"integer", 1_234_567},
      {"decimal", 1_234_567.89},
      {"small", 42.5},
      {"percent_value", 0.1234}
    ]
  end

  def unit_inputs do
    [
      {"length_m", {100, :meter}},
      {"length_km", {42, :kilometer}},
      {"mass_kg", {2.5, :kilogram}},
      {"temp_c", {20, :celsius}}
    ]
  end

  def run(title, jobs) do
    IO.puts("\n=== #{title} ===\n")

    Benchee.run(
      jobs,
      warmup: 1,
      time: 3,
      memory_time: 1,
      print: [fast_warning: false]
    )
  end
end

# ── Ensure both stacks are loaded and warm ───────────────────────

IO.puts("\nCompiling ex_cldr backend...")
{:module, Bench.Cldr} = Code.ensure_loaded(Bench.Cldr)

IO.puts("Warming Localize locale cache...")
locales = BenchHelper.locales()

# ── Number formatting: decimal ───────────────────────────────────

number_jobs =
  for {input_label, number} <- BenchHelper.number_inputs(),
      {locale_label, l_raw, l_tag, c_raw, c_tag} <- locales,
      entry <-
        [
          {"ex_cldr raw #{input_label} / #{locale_label}",
           fn -> Cldr.Number.to_string(number, Bench.Cldr, locale: c_raw) end},
          {"ex_cldr validated #{input_label} / #{locale_label}",
           fn -> Cldr.Number.to_string(number, Bench.Cldr, locale: c_tag) end},
          {"localize raw #{input_label} / #{locale_label}",
           fn -> Localize.Number.to_string(number, locale: l_raw) end},
          {"localize validated #{input_label} / #{locale_label}",
           fn -> Localize.Number.to_string(number, locale: l_tag) end}
        ],
      into: %{},
      do: entry

BenchHelper.run("Number formatting: decimal", number_jobs)

# ── Number formatting: currency ──────────────────────────────────

currency_jobs =
  for {locale_label, l_raw, l_tag, c_raw, c_tag} <- locales,
      entry <-
        [
          {"ex_cldr raw USD / #{locale_label}",
           fn ->
             Cldr.Number.to_string(1_234.56, Bench.Cldr, locale: c_raw, currency: :USD)
           end},
          {"ex_cldr validated USD / #{locale_label}",
           fn ->
             Cldr.Number.to_string(1_234.56, Bench.Cldr, locale: c_tag, currency: :USD)
           end},
          {"localize raw USD / #{locale_label}",
           fn -> Localize.Number.to_string(1_234.56, locale: l_raw, currency: :USD) end},
          {"localize validated USD / #{locale_label}",
           fn -> Localize.Number.to_string(1_234.56, locale: l_tag, currency: :USD) end}
        ],
      into: %{},
      do: entry

BenchHelper.run("Number formatting: currency", currency_jobs)

# ── Number formatting: percent ───────────────────────────────────

percent_jobs =
  for {locale_label, l_raw, l_tag, c_raw, c_tag} <- locales,
      entry <-
        [
          {"ex_cldr raw percent / #{locale_label}",
           fn ->
             Cldr.Number.to_string(0.1234, Bench.Cldr, locale: c_raw, format: :percent)
           end},
          {"ex_cldr validated percent / #{locale_label}",
           fn ->
             Cldr.Number.to_string(0.1234, Bench.Cldr, locale: c_tag, format: :percent)
           end},
          {"localize raw percent / #{locale_label}",
           fn -> Localize.Number.to_string(0.1234, locale: l_raw, format: :percent) end},
          {"localize validated percent / #{locale_label}",
           fn -> Localize.Number.to_string(0.1234, locale: l_tag, format: :percent) end}
        ],
      into: %{},
      do: entry

BenchHelper.run("Number formatting: percent", percent_jobs)

# ── Date formatting ──────────────────────────────────────────────

date_jobs =
  for format <- [:short, :medium, :long],
      {locale_label, l_raw, l_tag, c_raw, c_tag} <- locales,
      entry <-
        [
          {"ex_cldr raw #{format} / #{locale_label}",
           fn ->
             Cldr.Date.to_string(~D[2025-07-10], Bench.Cldr,
               locale: c_raw,
               format: format
             )
           end},
          {"ex_cldr validated #{format} / #{locale_label}",
           fn ->
             Cldr.Date.to_string(~D[2025-07-10], Bench.Cldr,
               locale: c_tag,
               format: format
             )
           end},
          {"localize raw #{format} / #{locale_label}",
           fn ->
             Localize.Date.to_string(~D[2025-07-10], locale: l_raw, format: format)
           end},
          {"localize validated #{format} / #{locale_label}",
           fn ->
             Localize.Date.to_string(~D[2025-07-10], locale: l_tag, format: format)
           end}
        ],
      into: %{},
      do: entry

BenchHelper.run("Date formatting", date_jobs)

# ── Time formatting ──────────────────────────────────────────────

time_jobs =
  for format <- [:short, :medium],
      {locale_label, l_raw, l_tag, c_raw, c_tag} <- locales,
      entry <-
        [
          {"ex_cldr raw #{format} / #{locale_label}",
           fn ->
             Cldr.Time.to_string(~T[14:30:45], Bench.Cldr,
               locale: c_raw,
               format: format
             )
           end},
          {"ex_cldr validated #{format} / #{locale_label}",
           fn ->
             Cldr.Time.to_string(~T[14:30:45], Bench.Cldr,
               locale: c_tag,
               format: format
             )
           end},
          {"localize raw #{format} / #{locale_label}",
           fn ->
             Localize.Time.to_string(~T[14:30:45], locale: l_raw, format: format)
           end},
          {"localize validated #{format} / #{locale_label}",
           fn ->
             Localize.Time.to_string(~T[14:30:45], locale: l_tag, format: format)
           end}
        ],
      into: %{},
      do: entry

BenchHelper.run("Time formatting", time_jobs)

# ── DateTime formatting ──────────────────────────────────────────

datetime_jobs =
  for format <- [:short, :medium, :long],
      {locale_label, l_raw, l_tag, c_raw, c_tag} <- locales,
      entry <-
        [
          {"ex_cldr raw #{format} / #{locale_label}",
           fn ->
             Cldr.DateTime.to_string(~N[2025-07-10 14:30:45], Bench.Cldr,
               locale: c_raw,
               format: format
             )
           end},
          {"ex_cldr validated #{format} / #{locale_label}",
           fn ->
             Cldr.DateTime.to_string(~N[2025-07-10 14:30:45], Bench.Cldr,
               locale: c_tag,
               format: format
             )
           end},
          {"localize raw #{format} / #{locale_label}",
           fn ->
             Localize.DateTime.to_string(~N[2025-07-10 14:30:45],
               locale: l_raw,
               format: format
             )
           end},
          {"localize validated #{format} / #{locale_label}",
           fn ->
             Localize.DateTime.to_string(~N[2025-07-10 14:30:45],
               locale: l_tag,
               format: format
             )
           end}
        ],
      into: %{},
      do: entry

BenchHelper.run("DateTime formatting", datetime_jobs)

# ── Unit formatting ──────────────────────────────────────────────
#
# ex_cldr_units and Localize differ on unit struct construction:
#   * ex_cldr: Cldr.Unit.new!(value, unit_atom) → %Cldr.Unit{}
#   * Localize: Localize.Unit.new!(value, "unit-string") → %Localize.Unit{}
#
# Both construction and formatting are part of the hot path, so we
# build fresh structs inside each benchmarked function to keep the
# comparison fair. The locale remains the only thing varied
# between raw and validated variants.

unit_long_jobs =
  for {input_label, {value, unit}} <- BenchHelper.unit_inputs(),
      {locale_label, l_raw, l_tag, c_raw, c_tag} <- locales,
      entry <-
        [
          {"ex_cldr raw #{input_label} / #{locale_label}",
           fn ->
             unit_struct = Cldr.Unit.new!(value, unit)
             Cldr.Unit.to_string(unit_struct, Bench.Cldr, locale: c_raw)
           end},
          {"ex_cldr validated #{input_label} / #{locale_label}",
           fn ->
             unit_struct = Cldr.Unit.new!(value, unit)
             Cldr.Unit.to_string(unit_struct, Bench.Cldr, locale: c_tag)
           end},
          {"localize raw #{input_label} / #{locale_label}",
           fn ->
             unit_struct = Localize.Unit.new!(value, to_string(unit))
             Localize.Unit.to_string(unit_struct, locale: l_raw)
           end},
          {"localize validated #{input_label} / #{locale_label}",
           fn ->
             unit_struct = Localize.Unit.new!(value, to_string(unit))
             Localize.Unit.to_string(unit_struct, locale: l_tag)
           end}
        ],
      into: %{},
      do: entry

BenchHelper.run("Unit formatting (long)", unit_long_jobs)

unit_short_jobs =
  for {input_label, {value, unit}} <- BenchHelper.unit_inputs(),
      {locale_label, l_raw, l_tag, c_raw, c_tag} <- locales,
      entry <-
        [
          {"ex_cldr raw #{input_label} / #{locale_label}",
           fn ->
             unit_struct = Cldr.Unit.new!(value, unit)
             Cldr.Unit.to_string(unit_struct, Bench.Cldr, locale: c_raw, style: :short)
           end},
          {"ex_cldr validated #{input_label} / #{locale_label}",
           fn ->
             unit_struct = Cldr.Unit.new!(value, unit)
             Cldr.Unit.to_string(unit_struct, Bench.Cldr, locale: c_tag, style: :short)
           end},
          {"localize raw #{input_label} / #{locale_label}",
           fn ->
             unit_struct = Localize.Unit.new!(value, to_string(unit))
             Localize.Unit.to_string(unit_struct, locale: l_raw, format: :short)
           end},
          {"localize validated #{input_label} / #{locale_label}",
           fn ->
             unit_struct = Localize.Unit.new!(value, to_string(unit))
             Localize.Unit.to_string(unit_struct, locale: l_tag, format: :short)
           end}
        ],
      into: %{},
      do: entry

BenchHelper.run("Unit formatting (short)", unit_short_jobs)

IO.puts("\nDone.\n")
