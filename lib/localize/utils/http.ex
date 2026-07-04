defmodule Localize.Utils.Http do
  # Supports securely downloading HTTPS content.
  #
  # This module provides HTTP GET functionality using the built-in `:httpc`
  # client with certificate verification enabled by default. It follows
  # the [erlef security guidelines](https://erlef.github.io/security-wg/secure_coding_and_deployment_hardening/ssl)
  # for secure TLS connections.
  #
  # The primary public API consists of:
  #
  # * `get/2` - download content from a URL, returning the body on success.
  #
  # * `get_with_headers/2` - download content from a URL, returning both
  #   headers and body on success.
  #
  # * `certificate_locations/0` - return the list of possible certificate
  #   store locations.
  #
  @moduledoc false

  require Logger

  @localize_unsafe_https "LOCALIZE_UNSAFE_HTTPS"
  @default_timeout "120000"
  @default_connection_timeout "60000"

  # Maximum response body size accepted by `get/2` / `get_with_headers/2`.
  # The largest legitimate locale ETF on the CDN is well under 5 MB; the
  # default cap leaves generous headroom while preventing a malicious
  # or compromised CDN from feeding a multi-gigabyte body that would
  # OOM the BEAM. Override with `config :localize, :max_http_body_bytes,
  # n` or pass `:max_body_bytes` as a per-call option.
  @default_max_http_body_bytes 50 * 1024 * 1024

  # Persistent-term key used to suppress repeated warnings when peer
  # verification has been disabled via `LOCALIZE_UNSAFE_HTTPS`.
  @unsafe_https_warned_key {__MODULE__, :unsafe_https_warned}

  # All Localize downloads run in a dedicated `:httpc` profile. Proxy
  # settings are per-profile *global* state in `:httpc`; using our own
  # profile means a configured proxy never leaks into (or from) the
  # host application's default profile, and the profile can be
  # restarted to clear a previously-set proxy.
  @httpc_profile :localize

  @doc """
  Securely download HTTPS content from a URL.

  This function uses the built-in `:httpc` client but enables certificate
  verification which is not enabled by `:httpc` by default.

  See also https://erlef.github.io/security-wg/secure_coding_and_deployment_hardening/ssl

  ### Arguments

  * `url` is a binary URL or a `{url, list_of_headers}` tuple. If
    provided the headers are a list of `{'header_name', 'header_value'}`
    tuples. Note that the name and value are both charlists, not
    strings.

  * `options` is a keyword list of options.

  ### Options

  * `:verify_peer` is a boolean value indicating if peer verification
    should be done for this request. The default is `true` in which case
    the default `:ssl` options follow the
    [erlef guidelines](https://erlef.github.io/security-wg/secure_coding_and_deployment_hardening/ssl).

  * `:timeout` is the number of milliseconds available for the request
    to complete. The default is #{inspect(@default_timeout)}. This option
    may also be set with the `LOCALIZE_HTTP_TIMEOUT` environment variable.

  * `:connection_timeout` is the number of milliseconds available for a
    connection to be established to the remote host. The default is
    #{inspect(@default_connection_timeout)}. This option may also be set
    with the `LOCALIZE_HTTP_CONNECTION_TIMEOUT` environment variable.

  ### Returns

  * `{:ok, body}` if the return is successful.

  * `{:not_modified, headers}` if the request would result in returning
    the same results as one matching an etag.

  * `{:error, error}` if the download is unsuccessful. An error will
    also be logged in these cases.

  ### Unsafe HTTPS

  If the environment variable `LOCALIZE_UNSAFE_HTTPS` is set to anything
  other than `"FALSE"`, `"false"`, `"nil"` or `"NIL"` then no peer
  verification of certificates is performed. Setting this variable is
  not recommended but may be required where peer verification fails for
  unidentified reasons.

  ### Certificate stores

  In order to keep dependencies to a minimum, `get/2` attempts to locate
  an already installed certificate store. It will try to locate a store
  in the following order which is intended to satisfy most host systems.
  The certificate store is expected to be a path name on the host system.

  ```elixir
  # A certificate store configured by the developer
  Application.get_env(:localize, :cacertfile)

  # Populated if hex package `CAStore` is configured
  CAStore.file_path()

  # Populated if hex package `certifi` is configured
  :certifi.cacertfile()

  # Debian/Ubuntu/Gentoo etc.
  "/etc/ssl/certs/ca-certificates.crt"

  # Fedora/RHEL 6
  "/etc/pki/tls/certs/ca-bundle.crt"

  # OpenSUSE
  "/etc/ssl/ca-bundle.pem"

  # OpenELEC
  "/etc/pki/tls/cacert.pem"

  # CentOS/RHEL 7
  "/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem"

  # OpenSSL on MacOS
  "/usr/local/etc/openssl/cert.pem"

  # MacOS & Alpine Linux
  "/etc/ssl/cert.pem"
  ```

  """
  @spec get(String.t() | {String.t(), list()}, options :: keyword()) ::
          {:ok, binary()} | {:not_modified, any()} | {:error, any()}

  def get(url, options \\ [])

  def get(url, options) when is_binary(url) and is_list(options) do
    case get_with_headers(url, options) do
      {:ok, _headers, body} -> {:ok, body}
      other -> other
    end
  end

  def get({url, headers}, options)
      when is_binary(url) and is_list(headers) and is_list(options) do
    case get_with_headers({url, headers}, options) do
      {:ok, _headers, body} -> {:ok, body}
      other -> other
    end
  end

  @doc """
  Securely download HTTPS content from a URL, returning headers and body.

  This function uses the built-in `:httpc` client but enables certificate
  verification which is not enabled by `:httpc` by default.

  See also https://erlef.github.io/security-wg/secure_coding_and_deployment_hardening/ssl

  ### Arguments

  * `url` is a binary URL or a `{url, list_of_headers}` tuple. If
    provided the headers are a list of `{'header_name', 'header_value'}`
    tuples. Note that the name and value are both charlists, not
    strings.

  * `options` is a keyword list of options.

  ### Options

  * `:verify_peer` is a boolean value indicating if peer verification
    should be done for this request. The default is `true` in which case
    the default `:ssl` options follow the
    [erlef guidelines](https://erlef.github.io/security-wg/secure_coding_and_deployment_hardening/ssl).

  * `:timeout` is the number of milliseconds available for the request
    to complete. The default is #{inspect(@default_timeout)}. This option
    may also be set with the `LOCALIZE_HTTP_TIMEOUT` environment variable.

  * `:connection_timeout` is the number of milliseconds available for a
    connection to be established to the remote host. The default is
    #{inspect(@default_connection_timeout)}. This option may also be set
    with the `LOCALIZE_HTTP_CONNECTION_TIMEOUT` environment variable.

  * `:https_proxy` is the URL of an HTTPS proxy to be used. The
    default is `nil`.

  ### Returns

  * `{:ok, headers, body}` if the return is successful.

  * `{:not_modified, headers}` if the request would result in returning
    the same results as one matching an etag.

  * `{:error, error}` if the download is unsuccessful. An error will
    also be logged in these cases.

  ### HTTPS Proxy

  `Localize.Utils.Http.get_with_headers/2` will look for a proxy URL in
  the following locations in the order presented:

  * `options[:https_proxy]`

  * Localize compile-time configuration under the
    key `:localize[:https_proxy]`.

  * The environment variable `HTTPS_PROXY`.

  * The environment variable `https_proxy`.

  """
  @spec get_with_headers(String.t() | {String.t(), list()}, options :: keyword()) ::
          {:ok, list(), binary()} | {:not_modified, any()} | {:error, any()}

  def get_with_headers(request, options \\ [])

  def get_with_headers(url, options) when is_binary(url) do
    get_with_headers({url, []}, options)
  end

  # One branch per :httpc response/error shape, each with distinct
  # logging and error tagging.
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  def get_with_headers({url, headers}, options)
      when is_binary(url) and is_list(headers) and is_list(options) do
    hostname = String.to_charlist(URI.parse(url).host)
    url = String.to_charlist(url)
    http_options = http_options(hostname, options)
    ip_family = :inet6fb4

    case proxy_configuration(https_proxy(options)) do
      {:invalid, invalid_proxy} ->
        Logger.warning(
          "https_proxy was set to an invalid value. Found #{inspect(invalid_proxy)}."
        )

        :ok = configure_proxy(:no_proxy, ip_family)

      configuration ->
        :ok = configure_proxy(configuration, ip_family)
    end

    case :httpc.request(
           :get,
           {url, headers},
           http_options,
           [body_format: :binary],
           @httpc_profile
         ) do
      {:ok, {{_version, 200, _}, headers, body}} ->
        case enforce_body_cap(body, options, url) do
          :ok -> {:ok, headers, body}
          {:error, _} = error -> error
        end

      {:ok, {{_version, 304, _}, headers, _body}} ->
        {:not_modified, headers}

      {_, {{_version, code, message}, _headers, _body}} ->
        Logger.error(
          "Failed to download #{url}. " <>
            "HTTP Error: (#{code}) #{inspect(message)}"
        )

        {:error, code}

      {:error,
       {:failed_connect, [{:to_address, {host, _port}}, {:inet6, _, _}, {_, _, :timeout}]}} ->
        Logger.error(
          "Timeout connecting to #{inspect(host)} to download #{inspect(url)}. " <>
            "Connection time exceeded #{http_options[:connect_timeout]}ms."
        )

        {:error, :connection_timeout}

      {:error,
       {:failed_connect, [{:to_address, {host, _port}}, {:inet6, _, _}, {_, _, :nxdomain}]}} ->
        Logger.error("Failed to resolve host #{inspect(host)} to download #{inspect(url)}")

        {:error, :nxdomain}

      {:error, :timeout} ->
        Logger.error(
          "Timeout downloading from #{inspect(url)}. " <>
            "Request exceeded #{http_options[:timeout]}ms."
        )

        {:error, :timeout}

      {:error, other} ->
        Logger.error("Failed to download #{inspect(url)}. Error #{inspect(other)}")

        {:error, other}
    end
  end

  @static_certificate_locations [
    # Debian/Ubuntu/Gentoo etc.
    "/etc/ssl/certs/ca-certificates.crt",

    # Fedora/RHEL 6
    "/etc/pki/tls/certs/ca-bundle.crt",

    # OpenSUSE
    "/etc/ssl/ca-bundle.pem",

    # OpenELEC
    "/etc/pki/tls/cacert.pem",

    # CentOS/RHEL 7
    "/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem",

    # OpenSSL on MacOS
    "/usr/local/etc/openssl/cert.pem",

    # MacOS & Alpine Linux
    "/etc/ssl/cert.pem"
  ]

  @doc """
  Return the dynamically discovered certificate file locations.

  These include application configuration and optional hex packages
  such as `CAStore` and `certifi`.

  ### Returns

  * A list of file path strings for discovered certificate locations.

  """
  @spec dynamic_certificate_locations() :: [String.t()]
  def dynamic_certificate_locations do
    [
      # Configured cacertfile
      Application.get_env(:localize, :cacertfile),

      # Populated if hex package CAStore is configured. CAStore is an
      # optional dep; a direct call warns when the package is absent.
      # credo:disable-for-next-line Credo.Check.Refactor.Apply
      if(Code.ensure_loaded?(CAStore), do: apply(CAStore, :file_path, [])),

      # Populated if hex package certifi is configured. :certifi is an
      # optional dep; a direct call warns when the package is absent.
      if(Code.ensure_loaded?(:certifi),
        # credo:disable-for-next-line Credo.Check.Refactor.Apply
        do: apply(:certifi, :cacertfile, []) |> List.to_string()
      )
    ]
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Return all possible locations of a certificate file.

  Returns dynamically discovered locations followed by well-known
  static locations on common operating systems.

  ### Returns

  * A list of file path strings for all candidate certificate locations.

  """
  @spec certificate_locations() :: [String.t()]
  def certificate_locations do
    dynamic_certificate_locations() ++ @static_certificate_locations
  end

  @doc false
  @spec certificate_store() :: String.t() | no_return()
  def certificate_store do
    certificate_locations()
    |> Enum.find(&File.exists?/1)
    |> raise_if_no_cacertfile!()
  end

  defp raise_if_no_cacertfile!(nil) do
    raise Localize.NoCertificateStoreError.exception(searched: certificate_locations())
  end

  defp raise_if_no_cacertfile!(file) do
    file
  end

  @ca_trust_key {__MODULE__, :ca_trust_option}

  @doc """
  Resolve the trust source to hand to `:ssl` for peer verification.

  Returns an SSL option pair — either `{:cacerts, list}` carrying
  DER-encoded certs from the platform trust store, or
  `{:cacertfile, path}` pointing at a PEM bundle on disk. The result
  is resolved once and cached in `:persistent_term`.

  Precedence:

  * an explicit `config :localize, cacertfile: path`,

  * `:public_key.cacerts_get/0`,

  * the `CAStore` hex package, if installed,

  * the `:certifi` hex package, if installed,

  * a well-known Unix file path that exists on disk.

  Raises `Localize.NoCertificateStoreError` if none of these yield a
  usable trust source.

  """
  @spec ca_trust_option() ::
          {:cacerts, [:public_key.combined_cert()]}
          | {:cacertfile, String.t()}
          | no_return()
  def ca_trust_option do
    case :persistent_term.get(@ca_trust_key, :__not_resolved__) do
      :__not_resolved__ ->
        option = resolve_ca_trust_option()
        :persistent_term.put(@ca_trust_key, option)
        option

      option ->
        option
    end
  end

  @doc false
  @spec resolve_ca_trust_option() ::
          {:cacerts, [:public_key.combined_cert()]}
          | {:cacertfile, String.t()}
          | no_return()
  def resolve_ca_trust_option do
    with :continue <- configured_cacertfile(),
         :continue <- otp_cacerts(),
         :continue <- castore_cacertfile(),
         :continue <- certifi_cacertfile(),
         :continue <- static_cacertfile() do
      raise Localize.NoCertificateStoreError.exception(searched: certificate_locations())
    end
  end

  defp configured_cacertfile do
    case Application.get_env(:localize, :cacertfile) do
      nil -> :continue
      file when is_binary(file) -> {:cacertfile, file}
    end
  end

  # `:public_key.cacerts_get/0` returns the platform-native trust list
  # (Windows store on Windows, system keychain on macOS, and a
  # well-known PEM bundle on Linux). It raises `:enoent` rather than
  # returning an empty list when no source has been loaded; treat both
  # cases as "fall through".
  defp otp_cacerts do
    case :public_key.cacerts_get() do
      [_ | _] = cacerts -> {:cacerts, cacerts}
      [] -> :continue
    end
  rescue
    _ -> :continue
  catch
    _, _ -> :continue
  end

  defp castore_cacertfile do
    if Code.ensure_loaded?(CAStore) do
      # CAStore is an optional dep; a direct call warns when absent.
      # credo:disable-for-next-line Credo.Check.Refactor.Apply
      {:cacertfile, apply(CAStore, :file_path, [])}
    else
      :continue
    end
  end

  defp certifi_cacertfile do
    if Code.ensure_loaded?(:certifi) do
      # :certifi is an optional dep; a direct call warns when absent.
      # credo:disable-for-next-line Credo.Check.Refactor.Apply
      {:cacertfile, apply(:certifi, :cacertfile, []) |> List.to_string()}
    else
      :continue
    end
  end

  defp static_cacertfile do
    case Enum.find(@static_certificate_locations, &File.exists?/1) do
      nil -> :continue
      file -> {:cacertfile, file}
    end
  end

  defp http_options(hostname, options) do
    default_timeout =
      "LOCALIZE_HTTP_TIMEOUT"
      |> System.get_env(@default_timeout)
      |> String.to_integer()

    default_connection_timeout =
      "LOCALIZE_HTTP_CONNECTION_TIMEOUT"
      |> System.get_env(@default_connection_timeout)
      |> String.to_integer()

    verify_peer? = Keyword.get(options, :verify_peer, true)
    ssl_options = https_ssl_options(hostname, verify_peer?)
    timeout = Keyword.get(options, :timeout, default_timeout)
    connection_timeout = Keyword.get(options, :connection_timeout, default_connection_timeout)

    # autoredirect is disabled because every URL this module fetches is a
    # fully-known, versioned CDN location. A redirect response can only
    # send the download to a host we did not choose, so it is always
    # refused rather than followed.
    [
      timeout: timeout,
      connect_timeout: connection_timeout,
      ssl: ssl_options,
      autoredirect: false
    ]
  end

  defp https_ssl_options(hostname, verify_peer?) do
    if secure_ssl?() and verify_peer? do
      [
        ca_trust_option(),
        verify: :verify_peer,
        depth: 4,
        ciphers: preferred_ciphers(),
        versions: protocol_versions(),
        eccs: preferred_eccs(),
        reuse_sessions: true,
        server_name_indication: hostname,
        secure_renegotiate: true,
        customize_hostname_check: [
          match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
        ]
      ]
    else
      warn_unsafe_https_once()

      [
        verify: :verify_none,
        server_name_indication: hostname,
        secure_renegotiate: true,
        reuse_sessions: true,
        versions: protocol_versions(),
        ciphers: preferred_ciphers()
      ]
    end
  end

  # Emit a single Logger.warning per BEAM lifetime when peer
  # verification has been disabled. The first call records itself in
  # `:persistent_term` so subsequent calls are silent — without the
  # one-shot the warning would spam the log on every download.
  # Operators see the policy downgrade in their logs and can choose
  # to investigate, while the volume stays manageable.
  defp warn_unsafe_https_once do
    case :persistent_term.get(@unsafe_https_warned_key, :__not_warned__) do
      :__not_warned__ ->
        Logger.warning(
          "Localize.Utils.Http: peer certificate verification is DISABLED " <>
            "(LOCALIZE_UNSAFE_HTTPS is set). HTTPS connections are vulnerable " <>
            "to man-in-the-middle attacks. This setting is intended for " <>
            "development behind corporate proxies with self-signed certificates; " <>
            "remove it in production."
        )

        :persistent_term.put(@unsafe_https_warned_key, true)

      _ ->
        :ok
    end
  end

  # Enforce a per-call upper bound on response body size. The default
  # is 50 MB (configurable via `:max_http_body_bytes` app env or
  # per-call `:max_body_bytes` option). Without this cap a malicious
  # or compromised CDN could feed an arbitrarily-large response and
  # OOM the BEAM — `:httpc` reads the entire body into memory.
  defp enforce_body_cap(body, options, url) when is_binary(body) do
    cap = Keyword.get(options, :max_body_bytes, max_http_body_bytes())

    if byte_size(body) > cap do
      Logger.error(
        "Refusing oversized HTTP response from #{url}: " <>
          "#{byte_size(body)} bytes exceeds the cap of #{cap} bytes."
      )

      {:error, :response_too_large}
    else
      :ok
    end
  end

  @doc false
  @spec max_http_body_bytes() :: pos_integer()
  def max_http_body_bytes do
    Application.get_env(:localize, :max_http_body_bytes, @default_max_http_body_bytes)
  end

  defp preferred_ciphers do
    preferred_ciphers = [
      # Cipher suites (TLS 1.3)
      %{cipher: :aes_128_gcm, key_exchange: :any, mac: :aead, prf: :sha256},
      %{cipher: :aes_256_gcm, key_exchange: :any, mac: :aead, prf: :sha384},
      %{cipher: :chacha20_poly1305, key_exchange: :any, mac: :aead, prf: :sha256},
      # Cipher suites (TLS 1.2)
      %{cipher: :aes_128_gcm, key_exchange: :ecdhe_ecdsa, mac: :aead, prf: :sha256},
      %{cipher: :aes_128_gcm, key_exchange: :ecdhe_rsa, mac: :aead, prf: :sha256},
      %{cipher: :aes_256_gcm, key_exchange: :ecdh_ecdsa, mac: :aead, prf: :sha384},
      %{cipher: :aes_256_gcm, key_exchange: :ecdh_rsa, mac: :aead, prf: :sha384},
      %{cipher: :chacha20_poly1305, key_exchange: :ecdhe_ecdsa, mac: :aead, prf: :sha256},
      %{cipher: :chacha20_poly1305, key_exchange: :ecdhe_rsa, mac: :aead, prf: :sha256},
      %{cipher: :aes_128_gcm, key_exchange: :dhe_rsa, mac: :aead, prf: :sha256},
      %{cipher: :aes_256_gcm, key_exchange: :dhe_rsa, mac: :aead, prf: :sha384}
    ]

    :ssl.filter_cipher_suites(preferred_ciphers, [])
  end

  defp protocol_versions do
    [:"tlsv1.2", :"tlsv1.3"]
  end

  defp preferred_eccs do
    preferred_eccs = [:secp256r1, :secp384r1]
    :ssl.eccs() -- (:ssl.eccs() -- preferred_eccs)
  end

  @doc false
  @spec secure_ssl?(String.t() | nil) :: boolean()
  def secure_ssl?(unsafe_https \\ System.get_env(@localize_unsafe_https)) do
    case unsafe_https do
      nil -> true
      "" -> true
      v when v in ~w(FALSE false nil NIL) -> true
      _ -> false
    end
  end

  defp https_proxy(options) do
    options[:https_proxy] ||
      Application.get_env(:localize, :https_proxy) ||
      System.get_env("HTTPS_PROXY") ||
      System.get_env("https_proxy")
  end

  @doc false
  # Parse a proxy URL (or its absence) into a proxy configuration.
  # Pure function — the seam used by tests to verify proxy resolution
  # without any network traffic.
  @spec proxy_configuration(String.t() | nil) ::
          {:proxy, {charlist(), pos_integer()}} | :no_proxy | {:invalid, String.t()}
  def proxy_configuration(nil) do
    :no_proxy
  end

  def proxy_configuration(proxy) when is_binary(proxy) do
    case URI.parse(proxy) do
      %{host: host, port: port} when is_binary(host) and host != "" and is_integer(port) ->
        {:proxy, {String.to_charlist(host), port}}

      _other ->
        {:invalid, proxy}
    end
  end

  @doc false
  # Apply a proxy configuration to an `:httpc` profile. The proxy is
  # set (or cleared) explicitly on *every* call so a proxy configured
  # for one download can never leak into a later proxy-less download
  # in the same BEAM.
  #
  # `:httpc.set_options/2` rejects the `{:undefined, []}` "no proxy"
  # default, so a previously-set proxy cannot be unset in place; the
  # profile is owned by Localize, so it is restarted instead, which
  # restores the default (proxy-less) options.
  @spec configure_proxy(
          {:proxy, {charlist(), pos_integer()}} | :no_proxy,
          atom(),
          atom()
        ) :: :ok
  def configure_proxy(configuration, ip_family, profile \\ @httpc_profile)

  def configure_proxy({:proxy, {host, port}}, ip_family, profile) do
    :ok = ensure_httpc_profile(profile)
    :ok = :httpc.set_options([https_proxy: {{host, port}, []}, ipfamily: ip_family], profile)
  end

  def configure_proxy(:no_proxy, ip_family, profile) do
    :ok = ensure_httpc_profile(profile)

    case :httpc.get_options([:https_proxy], profile) do
      {:ok, [https_proxy: {:undefined, _no_proxy_list}]} ->
        :ok

      _proxy_currently_set ->
        _ = :inets.stop(:httpc, profile)
        :ok = ensure_httpc_profile(profile)
    end

    :ok = :httpc.set_options([ipfamily: ip_family], profile)
  end

  defp ensure_httpc_profile(profile) do
    case :inets.start(:httpc, profile: profile) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end
  end
end
