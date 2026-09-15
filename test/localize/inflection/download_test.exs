defmodule Localize.Inflection.DownloadTest do
  # On-demand download wiring in `Localize.Inflection.Locale.resolve/1`:
  # a supported locale whose artifact is not present locally is fetched
  # from the CDN when runtime downloads are permitted, and every failure
  # path degrades to an error tuple rather than raising.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Localize.Inflection.{Locale, Provider}

  @moduletag :capture_log

  setup do
    original = %{
      data_dir: Application.get_env(:localize, :inflection_data_dir),
      allow: Application.get_env(:localize, :allow_runtime_locale_download),
      base_url: Application.get_env(:localize, :inflection_base_url)
    }

    # Point the data directory at an empty location so no supported
    # locale resolves to a local artifact.
    tmp = Path.join(System.tmp_dir!(), "infl_dl_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    Application.put_env(:localize, :inflection_data_dir, tmp)

    on_exit(fn ->
      restore(:inflection_data_dir, original.data_dir)
      restore(:allow_runtime_locale_download, original.allow)
      restore(:inflection_base_url, original.base_url)
      File.rm_rf(tmp)
    end)

    :ok
  end

  defp restore(key, nil), do: Application.delete_env(:localize, key)
  defp restore(key, value), do: Application.put_env(:localize, key, value)

  test "downloads disabled: a supported locale with no local artifact is not-available" do
    Application.put_env(:localize, :allow_runtime_locale_download, false)

    assert {:error, %Localize.InflectionDataNotAvailableError{}} = Locale.resolve(:en)
  end

  test "downloads enabled: an unreachable CDN degrades to an error, never raises" do
    Application.put_env(:localize, :allow_runtime_locale_download, true)
    Application.put_env(:localize, :inflection_base_url, "http://127.0.0.1:1/inflection")

    assert {:error, %Localize.LocaleDownloadError{}} = Locale.resolve(:en)
  end

  test "an unsupported locale is a not-supported error regardless of download settings" do
    Application.put_env(:localize, :allow_runtime_locale_download, true)

    assert {:error, %Localize.InflectionNotSupportedError{}} = Locale.resolve(:"xx-YZ")
  end

  test "the upstream pin is a full commit hash that prefixes the data version" do
    sha = Provider.upstream_sha()

    assert sha =~ ~r/\A[0-9a-f]{40}\z/
    assert String.starts_with?(Provider.data_version(), String.slice(sha, 0, 12))
  end

  # `Provider.download_file/1` end to end against a local :httpd server:
  # request, 200 body, then the SHA-256 gate against the manifest.
  describe "Provider.download_file/1" do
    setup do
      root = Path.join(System.tmp_dir!(), "infl_cdn_#{System.unique_integer([:positive])}")
      docroot = Path.join(root, "docroot")
      server_root = Path.join(root, "server_root")
      served = Path.join([docroot, "inflection", Provider.data_version()])
      File.mkdir_p!(served)
      File.mkdir_p!(server_root)

      body = "verified inflection bytes"
      File.write!(Path.join(served, "good.etf"), body)
      File.write!(Path.join(served, "tampered.etf"), "tampered bytes")
      File.write!(Path.join(served, "unlisted.etf"), body)

      {:ok, started} = Application.ensure_all_started(:inets)

      {:ok, httpd} =
        :inets.start(:httpd,
          port: 0,
          bind_address: ~c"127.0.0.1",
          server_name: ~c"localize_inflection_download_test",
          server_root: String.to_charlist(server_root),
          document_root: String.to_charlist(docroot),
          mime_type: ~c"application/octet-stream"
        )

      [port: port] = :httpd.info(httpd, [:port])
      Application.put_env(:localize, :inflection_base_url, "http://127.0.0.1:#{port}/inflection")

      # tampered.etf is listed with the hash of the good body, and
      # unlisted.etf has no entry at all.
      Provider.put_inflection_hashes(%{
        "good.etf" => :crypto.hash(:sha256, body),
        "tampered.etf" => :crypto.hash(:sha256, body)
      })

      on_exit(fn ->
        :inets.stop(:httpd, httpd)
        Enum.each(started, &Application.stop/1)
        Provider.reset_inflection_hashes()
        File.rm_rf(root)
      end)

      {:ok, body: body}
    end

    test "returns the served bytes when they match the manifest", %{body: body} do
      assert Provider.download_file("good.etf") == {:ok, body}
    end

    test "rejects bytes that do not match the manifest" do
      assert {:error, %Localize.LocaleIntegrityError{reason: :hash_mismatch}} =
               Provider.download_file("tampered.etf")
    end

    test "rejects a file the manifest does not list" do
      assert {:error, %Localize.LocaleIntegrityError{reason: :no_manifest_entry}} =
               Provider.download_file("unlisted.etf")
    end

    test "without a manifest the bytes are returned unverified with one warning", %{body: body} do
      Provider.reset_inflection_hashes()
      Provider.put_inflection_hashes(:no_manifest)

      log =
        capture_log(fn ->
          assert Provider.download_file("unlisted.etf") == {:ok, body}
          assert Provider.download_file("good.etf") == {:ok, body}
        end)

      assert log =~ "No inflection hash manifest found"
      assert length(String.split(log, "No inflection hash manifest found")) == 2
    end

    test "a file missing from the server is a download error" do
      assert {:error, %Localize.LocaleDownloadError{}} = Provider.download_file("absent.etf")
    end
  end
end
