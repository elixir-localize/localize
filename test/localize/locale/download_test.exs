defmodule Localize.Locale.Provider.DownloadTest do
  # Drives Localize.Locale.Provider.download_locale/1 end-to-end
  # against a local :httpd server: HTTP request → 200 body →
  # SHA-256 integrity gate → cache write → cache read-back.
  #
  # async: false because the tests swap the process-global hash
  # manifest via the persistent-term test seam and override the
  # :locale_base_url and :locale_cache_dir application environment.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Localize.Locale.Provider
  alias Localize.Locale.Provider.Cache

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    locale_data = %{version: Localize.version(), marker: "download-test"}
    body = :erlang.term_to_binary(locale_data)

    # Document root laid out the way locale_url/1 builds URLs:
    # {base_url}/{version_segment}/{locale_id}.etf with base_url
    # overridden to http://127.0.0.1:{port}/locales below.
    docroot = Path.join(tmp_dir, "docroot")
    served_dir = Path.join([docroot, "locales", Provider.version_segment()])
    File.mkdir_p!(served_dir)
    File.write!(Path.join(served_dir, "fr.etf"), body)
    File.write!(Path.join(served_dir, "de.etf"), "tampered bytes")
    File.write!(Path.join(served_dir, "it.etf"), body)

    server_root = Path.join(tmp_dir, "server_root")
    File.mkdir_p!(server_root)

    {:ok, ok_started} = Application.ensure_all_started(:inets)

    {:ok, httpd} =
      :inets.start(:httpd,
        port: 0,
        bind_address: ~c"127.0.0.1",
        server_name: ~c"localize_download_test",
        server_root: String.to_charlist(server_root),
        document_root: String.to_charlist(docroot),
        mime_type: ~c"application/octet-stream"
      )

    [port: port] = :httpd.info(httpd, [:port])

    previous_base_url = Application.get_env(:localize, :locale_base_url)
    previous_cache_dir = Application.get_env(:localize, :locale_cache_dir)

    Application.put_env(:localize, :locale_base_url, "http://127.0.0.1:#{port}/locales")
    Application.put_env(:localize, :locale_cache_dir, Path.join(tmp_dir, "cache"))

    # :de's manifest entry is the hash of the good body while the
    # server responds with tampered bytes; :it has no entry at all.
    Provider.put_locale_hashes(%{
      fr: :crypto.hash(:sha256, body),
      de: :crypto.hash(:sha256, body)
    })

    on_exit(fn ->
      :inets.stop(:httpd, httpd)
      Enum.each(ok_started, &Application.stop/1)
      Provider.reset_locale_hashes()
      restore_env(:locale_base_url, previous_base_url)
      restore_env(:locale_cache_dir, previous_cache_dir)
    end)

    {:ok, body: body, locale_data: locale_data}
  end

  defp restore_env(key, nil), do: Application.delete_env(:localize, key)
  defp restore_env(key, value), do: Application.put_env(:localize, key, value)

  describe "download_locale/1 happy path" do
    test "downloads, verifies, and returns the exact served bytes", %{
      body: body,
      locale_data: locale_data
    } do
      assert {:ok, ^body} = Provider.download_locale(:fr)
      assert :erlang.binary_to_term(body) == locale_data
    end

    test "downloaded content survives the cache write and read-back", %{
      body: body,
      locale_data: locale_data
    } do
      assert {:ok, ^body} = Provider.download_locale(:fr)
      assert {:ok, file_path} = Cache.store(:fr, body)
      assert String.ends_with?(file_path, "fr.etf")
      assert {:ok, ^locale_data} = Cache.get(:fr)
    end
  end

  describe "download_locale/1 failure paths over a real transport" do
    test "a missing file on the server is a download error" do
      log =
        capture_log(fn ->
          assert {:error, %Localize.LocaleDownloadError{cause: 404}} =
                   Provider.download_locale(:es)
        end)

      assert log =~ "404"
    end

    test "tampered content fails the integrity gate and is not cached" do
      assert {:error, %Localize.LocaleIntegrityError{reason: :hash_mismatch}} =
               Provider.download_locale(:de)

      refute File.exists?(Cache.path(:de))
    end

    test "content without a manifest entry fails closed" do
      assert {:error, %Localize.LocaleIntegrityError{reason: :no_manifest_entry}} =
               Provider.download_locale(:it)
    end
  end

  # The CDN reports brief internal errors that a client is expected to
  # retry. A scripted server stands in for it, answering with a 503 on cue.
  describe "download_locale/1 when the CDN fails for a moment" do
    alias Localize.Test.ScriptedHttpServer

    setup do
      previous_delay = Application.get_env(:localize, :http_retry_delay)
      Application.put_env(:localize, :http_retry_delay, 0)
      on_exit(fn -> restore_env(:http_retry_delay, previous_delay) end)
    end

    test "a server error is retried and the locale arrives", %{body: body} do
      server = ScriptedHttpServer.start([{503, [], ""}, {200, [], body}])
      serve_locales_from(server)

      {result, log} = with_log(fn -> Provider.download_locale(:fr) end)

      assert result == {:ok, body}
      assert log =~ "Retrying"
    end

    # An outage stays a transport failure, so an operator can tell it
    # from a manifest that no longer matches the data.
    test "an outage that outlasts the retries is a download error" do
      server = ScriptedHttpServer.start(List.duplicate({503, [], ""}, 4))
      serve_locales_from(server)

      {result, _log} = with_log(fn -> Provider.download_locale(:fr) end)

      assert {:error, %Localize.LocaleDownloadError{reason: :http_error, http_status: 503}} =
               result

      assert length(ScriptedHttpServer.requests(server)) == 4
    end
  end

  # The outer setup restores `:locale_base_url` when the test ends.
  defp serve_locales_from(server) do
    Application.put_env(:localize, :locale_base_url, "http://127.0.0.1:#{server.port}/locales")
  end
end
