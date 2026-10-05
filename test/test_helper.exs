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
# Calendrical's tests read this cache too (its test_helper.exs points
# `:locale_cache_dir` here), so the locales they reference are listed as
# well: bal, cy, da, he and nnh.
#
# List the *canonical CLDR locale id* for each referenced locale:
# non-CLDR forms canonicalise at load time (en-US -> en,
# pt-BR -> pt, th-TH -> th, zh-TW -> zh-Hant, zh-HK -> zh-Hant-HK),
# and only canonical ids exist as generated ETF files on the CDN.
test_locales = [
  "aa",
  "am",
  "ar",
  "ar-EG",
  "ar-SA",
  "bal",
  "be",
  "bg",
  "bn",
  "ckb",
  "cy",
  "da",
  "de",
  "de-AT",
  "de-CH",
  "dz",
  "ebu",
  "ee",
  "el",
  "en",
  "en-AU",
  "en-CA",
  "en-GB",
  "en-IE",
  "en-JM",
  "en-ZA",
  "es",
  "es-AR",
  "es-MX",
  "fa",
  "ff-Adlm",
  "fi",
  "fo",
  "fr",
  "fr-CA",
  "fr-CH",
  "gl",
  "he",
  "hi",
  "hu",
  "it",
  "it-CH",
  "ja",
  "ko",
  "ku",
  "ky",
  "mn",
  "mr",
  "ms",
  "my",
  "ne",
  "nl",
  "nl-BE",
  "nnh",
  "oc",
  "or",
  "pl",
  "pt",
  "pt-AO",
  "pt-PT",
  "raj",
  "ru",
  "sd-Deva",
  "su",
  "sv",
  "sv-AX",
  "sw",
  "th",
  "uk",
  "vi",
  "yue-Hans",
  "zh",
  "zh-Hans",
  "zh-Hant",
  "zh-Hant-HK"
]

# A test of "every locale" walks these (`Localize.Test.InstalledLocales`),
# on every machine. A loaded locale stays in `:persistent_term`, about
# 1.2 MB each, so a test that walked all 657 beside the rest of the suite
# ran the VM out of literal memory, and in CI each one that is not listed
# here would be fetched from the CDN.
Application.put_env(:localize, :test_locales, test_locales)

# The locale cache is shared by every branch checked out here, so running
# another branch's tests leaves that branch's data in place of this one's,
# and data for a CLDR pre-release is not on the CDN to download again. A
# test locale whose cached copy is missing or stale is therefore regenerated
# from the CLDR sources when the recorded ones are present; the download
# below fetches anything still missing.
if Localize.Data.sources_available?() do
  for name <- test_locales,
      {:ok, locale_id} <- [Localize.Locale.cldr_locale_id_from(name)],
      Localize.Locale.Provider.Cache.stale?(locale_id) do
    IO.puts("Regenerating #{locale_id} from the CLDR sources")
    Localize.Data.Locale.generate_and_save_locale(Atom.to_string(locale_id))
  end
end

Mix.Tasks.Localize.DownloadLocales.run(test_locales)

# The inflection tests need the data of every language they use, and
# runtime downloads are off in tests, so every supported language is
# fetched here rather than only the conformance suites' fixture locales:
# other tests reach beyond those (the list suite uses vi and id), and the
# twelve languages that adds come to under 600 KB. The ETFs come from the
# CDN; the upstream sources on GitHub only feed our own generation. A
# failed download makes the tests that need it fail with the reason.
Mix.Tasks.Localize.DownloadInflection.download_for(Localize.Inflection.Locale.supported())

# Integration tests (slow — spawn mix subprocesses, compile deps) are
# excluded by default. Run them with `mix test --include integration`.
#
# The `:nif_differential` unit-formatting property compares against the
# system ICU with a version-calibrated skew quarantine, so it is opt-in
# rather than a portable gate. Run it in a known-ICU environment with
# `mix test --include nif_differential`.
ExUnit.start(exclude: [:integration, :nif_differential])
