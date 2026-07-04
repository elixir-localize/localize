defmodule Localize.Locale.ProviderPureTest do
  # These tests mutate application environment keys that the
  # provider reads (:locale_cache_dir, :otp_app,
  # :allow_runtime_locale_download) and the locale hash manifest
  # seam, so they must not run concurrently with other tests.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Localize.Locale.Provider

  defmodule DownloadingProvider do
    @moduledoc false
    def allow_download?, do: true
  end

  defmodule SilentProvider do
    @moduledoc false
  end

  defp restore_env(key, original) do
    if original == :unset do
      Application.delete_env(:localize, key)
    else
      Application.put_env(:localize, key, original)
    end
  end

  defp put_env_restoring(key, value) do
    original =
      case Application.fetch_env(:localize, key) do
        {:ok, existing} -> existing
        :error -> :unset
      end

    Application.put_env(:localize, key, value)
    on_exit(fn -> restore_env(key, original) end)
    :ok
  end

  defp delete_env_restoring(key) do
    original =
      case Application.fetch_env(:localize, key) do
        {:ok, existing} -> existing
        :error -> :unset
      end

    Application.delete_env(:localize, key)
    on_exit(fn -> restore_env(key, original) end)
    :ok
  end

  describe "URL and file name construction" do
    test "base_url/0 is the canonical CDN address" do
      assert Provider.base_url() == "https://elixir-localize.com/locales"
    end

    test "locale_file_name/1 appends the etf extension" do
      assert Provider.locale_file_name(:en) == "en.etf"
      assert Provider.locale_file_name(:"en-GB") == "en-GB.etf"
    end

    test "version_segment/0 is the Localize version with a v prefix" do
      assert Provider.version_segment() == "v" <> Version.to_string(Localize.version())
    end

    test "locale_url/1 composes base URL, version segment and file name" do
      assert Provider.locale_url(:fr) ==
               Provider.base_url() <> "/" <> Provider.version_segment() <> "/fr.etf"
    end
  end

  describe "allow_download?/1" do
    test "delegates to the provider when it exports allow_download?/0" do
      assert Provider.allow_download?(DownloadingProvider) == true
    end

    test "falls back to the application environment otherwise" do
      delete_env_restoring(:allow_runtime_locale_download)
      assert Provider.allow_download?(SilentProvider) == false

      Application.put_env(:localize, :allow_runtime_locale_download, true)
      assert Provider.allow_download?(SilentProvider) == true
    end
  end

  describe "locale_cache_dir/0" do
    test "an absolute configured path is used literally" do
      put_env_restoring(:locale_cache_dir, "/tmp/localize-provider-test")
      assert Provider.locale_cache_dir() == "/tmp/localize-provider-test"
    end

    test "a relative path without :otp_app raises LocaleCacheDirError" do
      put_env_restoring(:locale_cache_dir, "priv/custom/locales")
      delete_env_restoring(:otp_app)

      assert_raise Localize.LocaleCacheDirError, fn ->
        Provider.locale_cache_dir()
      end
    end

    test "a relative path with :otp_app resolves under that application" do
      put_env_restoring(:locale_cache_dir, "priv/custom/locales")
      put_env_restoring(:otp_app, :localize)

      assert Provider.locale_cache_dir() ==
               Application.app_dir(:localize, "priv/custom/locales")
    end

    test "a non-binary configured value raises LocaleCacheDirError" do
      put_env_restoring(:locale_cache_dir, {:bad, :form})

      assert_raise Localize.LocaleCacheDirError, fn ->
        Provider.locale_cache_dir()
      end
    end

    test "an invalid :otp_app raises LocaleCacheDirError" do
      delete_env_restoring(:locale_cache_dir)
      put_env_restoring(:otp_app, "not_an_atom")

      assert_raise Localize.LocaleCacheDirError, fn ->
        Provider.locale_cache_dir()
      end
    end

    test "defaults to the bundled priv directory when unconfigured" do
      delete_env_restoring(:locale_cache_dir)
      delete_env_restoring(:otp_app)

      assert Provider.locale_cache_dir() == Provider.default_locale_cache_dir()
      assert Provider.validate_locale_cache_dir!() == :ok
    end

    test "default_locale_cache_dir/0 ends with localize/locales" do
      assert String.ends_with?(Provider.default_locale_cache_dir(), "localize/locales")
    end
  end

  describe "verify_locale_integrity/3" do
    setup do
      original_hashes = Provider.locale_hashes()

      on_exit(fn ->
        Provider.put_locale_hashes(original_hashes)
      end)

      :ok
    end

    test "accepts a body whose hash matches the manifest" do
      body = "fake locale body"
      Provider.put_locale_hashes(%{zz: :crypto.hash(:sha256, body)})

      assert Provider.verify_locale_integrity(:zz, "https://example.invalid/zz.etf", body) ==
               {:ok, body}
    end

    test "rejects a body whose hash does not match" do
      body = "fake locale body"
      Provider.put_locale_hashes(%{zz: :crypto.hash(:sha256, body)})

      assert {:error, %Localize.LocaleIntegrityError{reason: :hash_mismatch}} =
               Provider.verify_locale_integrity(:zz, "https://example.invalid/zz.etf", "tampered")
    end

    test "rejects a locale missing from the manifest" do
      Provider.put_locale_hashes(%{zz: :crypto.hash(:sha256, "body")})

      assert {:error, %Localize.LocaleIntegrityError{reason: :no_manifest_entry}} =
               Provider.verify_locale_integrity(:yy, "https://example.invalid/yy.etf", "body")
    end

    test "skips verification with a warning when there is no manifest" do
      # Clear the one-shot warning latch so the warning is observable
      # regardless of test ordering, then re-prime the manifest seam.
      Provider.reset_locale_hashes()
      Provider.put_locale_hashes(:no_manifest)

      {result, log} =
        with_log(fn ->
          Provider.verify_locale_integrity(:zz, "https://example.invalid/zz.etf", "body")
        end)

      assert result == {:ok, "body"}
      assert log =~ "No locale hash manifest"
    end
  end
end
