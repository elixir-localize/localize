defmodule Localize.Utils.Http do
  @moduledoc """
  Supports securely downloading HTTPS content.

  This module provides HTTP GET functionality using the built-in `:httpc`
  client with certificate verification enabled by default. It follows
  the [erlef security guidelines](https://erlef.github.io/security-wg/secure_coding_and_deployment_hardening/ssl)
  for secure TLS connections.

  The primary public API consists of:

  * `get/2` - download content from a URL, returning the body on success.

  * `get_with_headers/2` - download content from a URL, returning both
    headers and body on success.

  * `certificate_locations/0` - return the list of possible certificate
    store locations.

  """

  require Logger

  @localize_unsafe_https "LOCALIZE_UNSAFE_HTTPS"
  @default_timeout "120000"
  @default_connection_timeout "60000"

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

  def get_with_headers({url, headers}, options)
      when is_binary(url) and is_list(headers) and is_list(options) do
    hostname = String.to_charlist(URI.parse(url).host)
    url = String.to_charlist(url)
    http_options = http_options(hostname, options)
    https_proxy = https_proxy(options)
    ip_family = :inet6fb4

    if https_proxy do
      case URI.parse(https_proxy) do
        %{host: host, port: port} when is_binary(host) and is_integer(port) ->
          :ok =
            :httpc.set_options(
              https_proxy: {{String.to_charlist(host), port}, []},
              ipfamily: ip_family
            )

        _other ->
          Logger.warning(
            "https_proxy was set to an invalid value. Found #{inspect(https_proxy)}."
          )
      end
    else
      :ok = :httpc.set_options(ipfamily: ip_family)
    end

    case :httpc.request(:get, {url, headers}, http_options, body_format: :binary) do
      {:ok, {{_version, 200, _}, headers, body}} ->
        {:ok, headers, body}

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

      # Populated if hex package CAStore is configured
      if(Code.ensure_loaded?(CAStore), do: apply(CAStore, :file_path, [])),

      # Populated if hex package certifi is configured
      if(Code.ensure_loaded?(:certifi),
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
    raise RuntimeError, """
    No certificate trust store was found.
    Tried looking for: #{inspect(certificate_locations())}

    A certificate trust store is required in
    order to download data for your configuration.

    Since Localize could not detect a system
    installed certificate trust store one of the
    following actions may be taken:

    1. Install the hex package `castore`. It will
       be automatically detected after recompilation.

    2. Install the hex package `certifi`. It will
       be automatically detected after recompilation.

    3. Specify the location of a certificate trust store
       by configuring it in `config.exs` or `runtime.exs`:

       config :localize,
         cacertfile: "/path/to/cacertfile",
         ...

    """
  end

  defp raise_if_no_cacertfile!(file) do
    file
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

    [timeout: timeout, connect_timeout: connection_timeout, ssl: ssl_options]
  end

  defp https_ssl_options(hostname, verify_peer?) do
    if secure_ssl?() and verify_peer? do
      [
        verify: :verify_peer,
        cacertfile: certificate_store(),
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
      "FALSE" -> true
      "false" -> true
      "nil" -> true
      "NIL" -> true
      _other -> false
    end
  end

  defp https_proxy(options) do
    options[:https_proxy] ||
      Application.get_env(:localize, :https_proxy) ||
      System.get_env("HTTPS_PROXY") ||
      System.get_env("https_proxy")
  end
end
