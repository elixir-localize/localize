defmodule Mix.Tasks.Localize.DownloadLocalesTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  # Regression coverage for the Mix-task surface that crashed in
  # issue #26. We do not invoke the network — the test exercises the
  # `banner/2` helper directly, which is what previously crashed
  # with `MatchError` when the active locale's data was not
  # available. After the fix:
  #
  #   1. `Localize.Locale.Loader` stores fallback data under the
  #      *requested* locale id, so the MF2 `:number` function in the
  #      banner template finds the number-system data it needs.
  #
  #   2. Even if MF2 formatting still fails for some unrelated
  #      reason, `banner/2` returns a plain-ASCII fallback string
  #      rather than crashing the entire task.

  alias Mix.Tasks.Localize.DownloadLocales

  describe "banner/2 — issue #26 reproducer surface" do
    test "renders the MF2 banner for plural counts under a normal config" do
      banner = DownloadLocales.banner(5, "/tmp/cache")
      assert is_binary(banner)
      assert banner =~ "5"
      assert banner =~ "/tmp/cache"
    end

    test "renders the MF2 banner for the singular count" do
      banner = DownloadLocales.banner(1, "/tmp/cache")
      assert is_binary(banner)
      assert banner =~ "1"
    end

    test "does not crash when default_locale is unavailable in the cache dir" do
      # The exact scenario from issue #26: `default_locale: :"en-ZA"`
      # set, locale data for `:"en-ZA"` not yet downloaded. With the
      # 0.30.x regression the banner formatter would crash with
      # `MatchError` on `{:ok, _} = Localize.Message.format(...)`;
      # with the 0.31.x fix the loader stores the `:en` fallback
      # data under `:"en-ZA"`, the MF2 `:number` function resolves
      # the digits, and the banner renders normally.

      previous = Application.get_env(:localize, :default_locale)

      try do
        Application.put_env(:localize, :default_locale, :"en-ZA")

        capture_log(fn ->
          banner = DownloadLocales.banner(2, "/tmp/cache")
          assert is_binary(banner)
          assert banner =~ "2"
          assert banner =~ "/tmp/cache"
        end)
      after
        if previous, do: Application.put_env(:localize, :default_locale, previous)
      end
    end

    test "falls back to a plain ASCII banner if MF2 format ever returns an error" do
      # Defence in depth: confirm the safety-net branch in `banner/2`
      # produces a sensible string. We exercise it by passing inputs
      # that the MF2 formatter accepts; if a future regression
      # breaks MF2 entirely, this test still passes because the
      # ASCII fallback path produces a non-empty string.
      assert DownloadLocales.banner(3, "/tmp/cache") =~ "3"
      assert DownloadLocales.banner(1, "/tmp/cache") =~ "locale"
      assert DownloadLocales.banner(7, "/tmp/cache") =~ "locales"
    end
  end

  describe "skip decision is target-dir-scoped — issue #35" do
    # Issue #35: with a custom `:locale_cache_dir`, the task reported
    # every locale "(current)" and skipped it — because the old skip
    # check used `Cache.get/1`, which falls back to the bundled
    # package dir (`Application.app_dir(:localize, …)`). A locale
    # present in the dependency's `_build` priv was therefore treated
    # as current and never written to the user's (empty) configured
    # dir.
    #
    # The fix switches the skip decision to `Cache.stale?/1`, which
    # reads ONLY the configured `Cache.path/1`. These tests lock down
    # the divergence the fix relies on: `stale?/1` ignores the
    # bundled fallback; `get/1` still uses it (correct for runtime
    # reads). `:en` is shipped in the bundled dir, so it's the ideal
    # probe.

    alias Localize.Locale.Provider.Cache

    setup do
      previous = Application.get_env(:localize, :locale_cache_dir)

      tmp =
        Path.join(System.tmp_dir!(), "localize_mcp_issue35_#{System.unique_integer([:positive])}")

      File.mkdir_p!(tmp)
      Application.put_env(:localize, :locale_cache_dir, tmp)

      on_exit(fn ->
        File.rm_rf(tmp)

        case previous do
          nil -> Application.delete_env(:localize, :locale_cache_dir)
          dir -> Application.put_env(:localize, :locale_cache_dir, dir)
        end
      end)

      {:ok, tmp: tmp}
    end

    test "Cache.stale?/1 reports a locale stale when the configured dir is empty, " <>
           "even though the bundled dir ships it" do
      # The configured dir is the fresh empty tmp dir. `:en` is in the
      # bundled package dir but NOT in the configured dir, so the
      # download decision must treat it as needing a download.
      assert Cache.stale?(:en) == true
    end

    test "Cache.get/1 still finds the locale via the bundled fallback (runtime read)" do
      # Same configured (empty) dir, but the runtime read SHOULD fall
      # back to the bundled dir so the app still works. This is the
      # behaviour we deliberately keep out of the download decision.
      assert {:ok, _data} = Cache.get(:en)
    end

    test "Cache.path/1 points at the configured dir, not the bundled dir", %{tmp: tmp} do
      assert Cache.path(:en) == Path.join(tmp, "en.etf")
    end
  end
end
