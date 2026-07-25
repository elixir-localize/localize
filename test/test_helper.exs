Application.put_env(:localize, :default_locale, :en)

# Pre-download every locale our tests reference so individual
# test cases don't pay a cold-cache locale download per run.
# Without this, the first call into any uncached locale stalls
# for 1-2 seconds while the ETF file streams from the CDN, which
# both inflates the suite's total wallclock and makes any
# "must complete in N ms" assertion (like the regression test
# for the `best_match` recursion fix in date_test.exs) brittle.
#
# Keep this list in sync with the locales referenced anywhere
# under `test/`. Extracted with:
#
#     grep -rhoE 'locale: :"[a-zA-Z][a-zA-Z\-]*"' test/ | sort -u
#
# Plus the locales explicitly named in `~D` / `Date.new`
# fixtures for non-Gregorian calendars (e.g. ja-JP for the
# Japanese imperial calendar, ar-SA for Islamic, th-TH for
# Buddhist).
#
# List the *canonical CLDR locale id* for each referenced locale:
# non-CLDR forms canonicalise at load time (en-US -> en,
# pt-BR -> pt, th-TH -> th, zh-TW -> zh-Hant, zh-HK -> zh-Hant-HK),
# and only canonical ids exist as generated ETF files on the CDN.
test_locales = [
  "aa",
  "am",
  "ar",
  "ar-SA",
  "de",
  "de-CH",
  "ee",
  "en",
  "en-AU",
  "en-CA",
  "en-GB",
  "en-ZA",
  "es",
  "es-AR",
  "es-MX",
  "fi",
  "fr",
  "fr-CA",
  "fr-CH",
  "hu",
  "it",
  "it-CH",
  "ja",
  "ko",
  "ky",
  "mr",
  "nl-BE",
  "pt",
  "pt-AO",
  "pt-PT",
  "ru",
  "th",
  "yue-Hans",
  "zh",
  "zh-Hans",
  "zh-Hant",
  "zh-Hant-HK"
]

Mix.Tasks.Localize.DownloadLocales.run(test_locales)

# Integration tests (slow — spawn mix subprocesses, compile deps) are
# excluded by default. Run them with `mix test --include integration`.
#
# The `:nif_differential` unit-formatting property compares against the
# system ICU with a version-calibrated skew quarantine, so it is opt-in
# rather than a portable gate. Run it in a known-ICU environment with
# `mix test --include nif_differential`.
ExUnit.start(exclude: [:integration, :nif_differential])
