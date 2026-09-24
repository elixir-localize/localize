defmodule Localize.Utils.HttpTest do
  @moduledoc """
  Covers HTTP utility helpers that can be tested without opening network
  connections.

  These tests do not exercise the Erlang httpc transport or external
  certificate stores.
  """

  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  doctest Localize.Utils.Http

  describe "secure_ssl?/1" do
    test "keeps verification enabled when unsafe HTTPS is unset" do
      assert Localize.Utils.Http.secure_ssl?(nil)
    end

    test "treats an empty string as unset (verification stays on)" do
      assert Localize.Utils.Http.secure_ssl?("")
    end

    test "keeps verification enabled for explicit false-ish tokens" do
      for value <- ~w(FALSE false nil NIL) do
        assert Localize.Utils.Http.secure_ssl?(value),
               "expected secure_ssl?(#{inspect(value)}) to be true"
      end
    end

    test "disables verification when set to a truthy value" do
      refute Localize.Utils.Http.secure_ssl?("true")
      refute Localize.Utils.Http.secure_ssl?("1")
      refute Localize.Utils.Http.secure_ssl?("yes")
    end
  end

  describe "max_http_body_bytes/0" do
    test "returns the default cap (50 MB) when unconfigured" do
      original = Application.get_env(:localize, :max_http_body_bytes)
      Application.delete_env(:localize, :max_http_body_bytes)

      try do
        assert Localize.Utils.Http.max_http_body_bytes() == 50 * 1024 * 1024
      after
        if original do
          Application.put_env(:localize, :max_http_body_bytes, original)
        else
          Application.delete_env(:localize, :max_http_body_bytes)
        end
      end
    end

    test "honours an app-env override" do
      original = Application.get_env(:localize, :max_http_body_bytes)
      Application.put_env(:localize, :max_http_body_bytes, 1_024)

      try do
        assert Localize.Utils.Http.max_http_body_bytes() == 1_024
      after
        if original do
          Application.put_env(:localize, :max_http_body_bytes, original)
        else
          Application.delete_env(:localize, :max_http_body_bytes)
        end
      end
    end
  end

  describe "certificate_locations/0" do
    test "ends with the well-known static locations" do
      locations = Localize.Utils.Http.certificate_locations()

      assert "/etc/ssl/cert.pem" in locations
      assert "/etc/ssl/certs/ca-certificates.crt" in locations
    end

    test "includes a configured :cacertfile ahead of the static locations" do
      original = Application.get_env(:localize, :cacertfile)
      Application.put_env(:localize, :cacertfile, "/tmp/localize-http-test.pem")

      try do
        assert List.first(Localize.Utils.Http.dynamic_certificate_locations()) ==
                 "/tmp/localize-http-test.pem"

        assert List.first(Localize.Utils.Http.certificate_locations()) ==
                 "/tmp/localize-http-test.pem"
      after
        if original do
          Application.put_env(:localize, :cacertfile, original)
        else
          Application.delete_env(:localize, :cacertfile)
        end
      end
    end
  end

  describe "certificate_store/0" do
    @tag :tmp_dir
    test "returns the first candidate file that exists", %{tmp_dir: tmp_dir} do
      certificate_file = Path.join(tmp_dir, "fake-store.pem")
      File.write!(certificate_file, "not really a certificate")

      original = Application.get_env(:localize, :cacertfile)
      Application.put_env(:localize, :cacertfile, certificate_file)

      try do
        assert Localize.Utils.Http.certificate_store() == certificate_file
      after
        if original do
          Application.put_env(:localize, :cacertfile, original)
        else
          Application.delete_env(:localize, :cacertfile)
        end
      end
    end
  end

  # These requests target a local port on which nothing listens, so
  # the connection is refused immediately without any external
  # network traffic. They exercise the request-building and error
  # normalization paths in `get_with_headers/2`.
  describe "get/2 and get_with_headers/2 error normalization" do
    test "a refused local connection returns a failed_connect error and logs" do
      {result, log} =
        with_log(fn ->
          Localize.Utils.Http.get("https://127.0.0.1:9/nothing.etf",
            connection_timeout: 2_000,
            timeout: 3_000,
            retries: 0
          )
        end)

      assert {:error, {:failed_connect, _details}} = result
      assert log =~ "Failed to download"
    end

    test "the {url, headers} tuple form takes charlist headers" do
      {result, _log} =
        with_log(fn ->
          Localize.Utils.Http.get_with_headers(
            {"https://127.0.0.1:9/nothing.etf", [{~c"accept", ~c"*/*"}]},
            connection_timeout: 2_000,
            timeout: 3_000,
            retries: 0
          )
        end)

      assert {:error, {:failed_connect, _details}} = result
    end

    test "an invalid https_proxy option logs a warning and continues" do
      {result, log} =
        with_log(fn ->
          Localize.Utils.Http.get_with_headers({"https://127.0.0.1:9/x", []},
            https_proxy: "not a url",
            connection_timeout: 2_000,
            timeout: 3_000,
            retries: 0
          )
        end)

      assert {:error, _reason} = result
      assert log =~ "https_proxy was set to an invalid value"
    end
  end

  # A local server answers with scripted responses, so these exercise the
  # transport end to end without leaving the machine.
  describe "retries" do
    alias Localize.Test.ScriptedHttpServer, as: Server

    @quick [retry_delay: 0, ip_family: :inet]

    test "a server error is retried and the body that follows returned" do
      server = Server.start([{500, [], ""}, {200, [], "locale data"}])

      {result, log} = with_log(fn -> Localize.Utils.Http.get(server.url, @quick) end)

      assert result == {:ok, "locale data"}
      assert length(Server.requests(server)) == 2
      assert log =~ "HTTP Error: (500)"
      assert log =~ "Retrying in"
    end

    test "every status worth retrying is retried" do
      for status <- [408, 429, 500, 502, 503, 504] do
        server = Server.start([{status, [], ""}, {200, [], "ok"}])

        {result, _log} = with_log(fn -> Localize.Utils.Http.get(server.url, @quick) end)

        assert result == {:ok, "ok"}, "#{status} was not retried"
      end
    end

    # A 404 means the object is absent for this version; asking again
    # only delays the error.
    test "a 404 fails at once" do
      server = Server.start([{404, [], ""}, {200, [], "never served"}])

      {result, log} = with_log(fn -> Localize.Utils.Http.get(server.url, @quick) end)

      assert result == {:error, 404}
      assert length(Server.requests(server)) == 1
      refute log =~ "Retrying"
    end

    test "the last failure is returned once the retries run out" do
      server = Server.start(List.duplicate({503, [], ""}, 4))

      {result, log} =
        with_log(fn -> Localize.Utils.Http.get(server.url, [retries: 2] ++ @quick) end)

      assert result == {:error, 503}
      assert length(Server.requests(server)) == 3
      assert log =~ "attempt 3 of 3"
    end

    test "retries: 0 makes a single attempt" do
      server = Server.start([{500, [], ""}, {200, [], "never served"}])

      {result, _log} =
        with_log(fn -> Localize.Utils.Http.get(server.url, [retries: 0] ++ @quick) end)

      assert result == {:error, 500}
      assert length(Server.requests(server)) == 1
    end

    test "a conditional request stays conditional when retried" do
      server = Server.start([{503, [], ""}, {304, [{"etag", ~s("abc")}], ""}])
      request = {server.url, [{~c"if-none-match", ~c"\"abc\""}]}

      {result, _log} = with_log(fn -> Localize.Utils.Http.get_with_headers(request, @quick) end)

      assert {:not_modified, _headers} = result
      requests = Server.requests(server)
      assert length(requests) == 2
      assert Enum.all?(requests, &(&1 =~ ~r/if-none-match: "abc"/i))
    end

    test "a not-modified answer is not retried" do
      server = Server.start([{304, [], ""}])

      assert {:not_modified, _headers} = Localize.Utils.Http.get(server.url, @quick)
      assert length(Server.requests(server)) == 1
    end

    test "an oversized body fails at once" do
      server = Server.start([{200, [], String.duplicate("x", 100)}, {200, [], "x"}])

      {result, log} =
        with_log(fn -> Localize.Utils.Http.get(server.url, [max_body_bytes: 10] ++ @quick) end)

      assert result == {:error, :response_too_large}
      assert length(Server.requests(server)) == 1
      assert log =~ "Refusing oversized HTTP response"
    end

    test "an unknown IP family falls back to IPv6 first and says so" do
      server = Server.start([{200, [], "ok"}])

      {result, log} =
        with_log(fn -> Localize.Utils.Http.get(server.url, ip_family: :ipx, retry_delay: 0) end)

      assert result == {:ok, "ok"}
      assert log =~ "ip_family must be one of"
    end
  end

  describe "proxy_configuration/1" do
    test "returns :no_proxy when no proxy is configured" do
      assert Localize.Utils.Http.proxy_configuration(nil) == :no_proxy
    end

    test "parses a valid proxy URL into a host/port pair" do
      assert Localize.Utils.Http.proxy_configuration("http://proxy.example.com:8080") ==
               {:proxy, {~c"proxy.example.com", 8080}}
    end

    test "uses the scheme default port when none is given" do
      assert Localize.Utils.Http.proxy_configuration("http://proxy.example.com") ==
               {:proxy, {~c"proxy.example.com", 80}}
    end

    test "tags an unparseable proxy URL as invalid" do
      assert Localize.Utils.Http.proxy_configuration("not a url") ==
               {:invalid, "not a url"}
    end
  end

  describe "configure_proxy/3" do
    # Regression: a https_proxy resolved for one download used to be
    # set as global `:httpc` state and was never cleared, so it leaked
    # into every later proxy-less download in the same BEAM. The proxy
    # must now be cleared whenever no proxy is configured. A dedicated
    # scratch profile keeps this test free of network calls and
    # isolated from concurrent tests.
    test "a proxy set by one call does not leak into a later proxy-less call" do
      profile = :localize_http_test_proxy_leak

      try do
        :ok =
          Localize.Utils.Http.configure_proxy(
            {:proxy, {~c"proxy.example.com", 8080}},
            :inet6fb4,
            profile
          )

        assert {:ok, [https_proxy: {{~c"proxy.example.com", 8080}, []}]} =
                 :httpc.get_options([:https_proxy], profile)

        :ok = Localize.Utils.Http.configure_proxy(:no_proxy, :inet6fb4, profile)

        assert {:ok, [https_proxy: {:undefined, []}]} =
                 :httpc.get_options([:https_proxy], profile)
      after
        _ = :inets.stop(:httpc, profile)
      end
    end

    test "configuring no proxy on a fresh profile leaves the default" do
      profile = :localize_http_test_no_proxy

      try do
        :ok = Localize.Utils.Http.configure_proxy(:no_proxy, :inet6fb4, profile)

        assert {:ok, [https_proxy: {:undefined, []}]} =
                 :httpc.get_options([:https_proxy], profile)
      after
        _ = :inets.stop(:httpc, profile)
      end
    end
  end

  # `resolve_ca_trust_option/0` is the uncached resolver behind
  # `ca_trust_option/0`. Tests target the resolver so each variant
  # can be exercised without persistent_term cache interference.
  #
  # Regression: issue #30 — Windows users hit
  # `Localize.NoCertificateStoreError` because the resolver only
  # searched Unix file paths. The OTP `cacerts_get` branch closes
  # that gap.
  describe "resolve_ca_trust_option/0" do
    test "honours an explicit :cacertfile app config" do
      original = Application.get_env(:localize, :cacertfile)
      Application.put_env(:localize, :cacertfile, "/tmp/localize-fake.pem")

      try do
        assert {:cacertfile, "/tmp/localize-fake.pem"} =
                 Localize.Utils.Http.resolve_ca_trust_option()
      after
        if original do
          Application.put_env(:localize, :cacertfile, original)
        else
          Application.delete_env(:localize, :cacertfile)
        end
      end
    end

    test "falls through to OTP cacerts_get when no override is configured" do
      original = Application.get_env(:localize, :cacertfile)
      Application.delete_env(:localize, :cacertfile)

      try do
        # The CI environment we run on has either an OS trust store
        # (macOS/Windows) or a populated Unix path. Either way, we
        # must get a usable option pair back — never raise.
        assert {tag, value} = Localize.Utils.Http.resolve_ca_trust_option()
        assert tag in [:cacerts, :cacertfile]

        case tag do
          :cacerts -> assert is_list(value) and value != []
          :cacertfile -> assert is_binary(value)
        end
      after
        if original do
          Application.put_env(:localize, :cacertfile, original)
        else
          Application.delete_env(:localize, :cacertfile)
        end
      end
    end
  end
end
