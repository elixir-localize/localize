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
  "en-US",
  "en-ZA",
  "es",
  "es-AR",
  "es-MX",
  "fr",
  "fr-CA",
  "fr-CH",
  "it",
  "it-CH",
  "ja",
  "ja-JP",
  "ko",
  "ky",
  "nl-BE",
  "pt",
  "pt-AO",
  "pt-BR",
  "pt-PT",
  "ru",
  "th-TH",
  "yue-Hans",
  "zh",
  "zh-CN",
  "zh-HK",
  "zh-Hans",
  "zh-Hant-TW",
  "zh-TW"
]

Mix.Tasks.Localize.DownloadLocales.run(test_locales)

# Integration tests (slow — spawn mix subprocesses, compile deps) are
# excluded by default. Run them with `mix test --include integration`.
ExUnit.start(exclude: [:integration])
