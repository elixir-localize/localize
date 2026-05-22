defmodule Localize.Locale.GettextBackendSupportedLocalesTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Localize.Locale

  # A minimal Gettext-shaped backend. `Gettext.known_locales/1`
  # delegates to `backend.__gettext__(:known_locales)`, so any module
  # that exports `__gettext__/1` and returns a list from that call is
  # accepted as a backend by `Localize.Locale.expand_locale_list/2`.
  defmodule FakeBackend do
    # Mix of locales chosen to exercise both behaviours of the
    # downstream string-expansion path:
    #
    # * `de_AT` and `fr_CA` are *regional* locales that survive
    #   likely-subtag canonicalization as themselves.
    # * `pt_BR` is the likely-subtag *default* for Portuguese, so
    #   `best_match` collapses it to the minimal CLDR form `:pt` —
    #   matching the existing behaviour for raw string entries.
    def __gettext__(:known_locales), do: ["en", "de_AT", "fr_CA", "pt_BR"]
    def __gettext__(_), do: nil
  end

  defmodule EmptyBackend do
    def __gettext__(:known_locales), do: []
    def __gettext__(_), do: nil
  end

  describe "expand_locale_list/2 with a Gettext backend module" do
    test "expands the backend's known locales into CLDR locale IDs" do
      result = Locale.expand_locale_list([FakeBackend], :supported_locales)

      assert :en in result
      # POSIX underscores normalised; regional locale preserved.
      assert :"de-AT" in result
      assert :"fr-CA" in result
      # `pt_BR` is the likely-subtag default for `pt`, so the existing
      # string-expansion path collapses it to `:pt`. Documented here as
      # a regression guard against any future divergence between the
      # backend path and the raw-string path.
      assert :pt in result
    end

    test "deduplicates against directly-listed CLDR atoms" do
      result = Locale.expand_locale_list([:en, FakeBackend, :"de-AT"], :supported_locales)

      assert Enum.count(result, &(&1 == :en)) == 1
      assert Enum.count(result, &(&1 == :"de-AT")) == 1
    end

    test "an empty backend contributes nothing and logs nothing" do
      log =
        capture_log(fn ->
          assert [] = Locale.expand_locale_list([EmptyBackend], :supported_locales)
        end)

      refute log =~ "Ignoring"
    end

    test "a module that is not a Gettext backend logs and is dropped" do
      log =
        capture_log(fn ->
          # `String` is a well-known module that has nothing to do with
          # Gettext. The expansion path falls through to the
          # `warn_unknown_locale` branch.
          assert [] = Locale.expand_locale_list([String], :supported_locales)
        end)

      assert log =~ "Ignoring unknown locale String"
      assert log =~ "Gettext backend"
    end

    test "an undefined module logs and is dropped without raising" do
      # `Code.ensure_compiled/1` returns `{:error, :nofile}` for
      # modules that don't exist. The expansion must not propagate
      # that as a raise.
      log =
        capture_log(fn ->
          assert [] = Locale.expand_locale_list([NoSuchModule], :supported_locales)
        end)

      assert log =~ "Ignoring unknown locale NoSuchModule"
    end

    test "mixing a backend with coverage levels and explicit ids works" do
      result =
        Locale.expand_locale_list(
          [:basic, FakeBackend, :"fr-CA"],
          :supported_locales
        )

      assert :"fr-CA" in result
      assert :en in result
      assert :"de-AT" in result
      # `:basic` contributed many locales — exact count is data-driven,
      # we just sanity-check it's substantial.
      assert length(result) > 10
    end
  end
end
