defmodule Localize.Data.R2 do
  @moduledoc false

  # Reads and writes objects in Cloudflare R2, the store behind the locale
  # CDN, through its S3 API, signing each request with AWS Signature
  # Version 4. Object keys are restricted to characters that need no
  # escaping in a URL or in the signature's canonical request.

  @key_pattern ~r/^[A-Za-z0-9._\/-]+$/

  @doc """
  Returns the R2 connection read from the environment.

  ### Returns

  * `{:ok, config}` from `R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID` and
    `R2_SECRET_ACCESS_KEY`.

  * `{:error, message}` naming the variables that are not set.

  """
  @spec config() :: {:ok, map()} | {:error, String.t()}
  def config do
    variables = ["R2_ACCOUNT_ID", "R2_ACCESS_KEY_ID", "R2_SECRET_ACCESS_KEY"]

    case Enum.reject(variables, &System.get_env/1) do
      [] ->
        {:ok,
         %{
           endpoint: "https://#{System.get_env("R2_ACCOUNT_ID")}.r2.cloudflarestorage.com",
           access_key: System.get_env("R2_ACCESS_KEY_ID"),
           secret_key: System.get_env("R2_SECRET_ACCESS_KEY")
         }}

      missing ->
        {:error, "R2 credentials are not set: #{Enum.join(missing, ", ")}"}
    end
  end

  @doc """
  Writes an object.

  ### Arguments

  * `config` is the connection from `config/0`.

  * `bucket` is the bucket name.

  * `key` is the object key.

  * `body` is the object's content.

  ### Returns

  * `:ok` when R2 stored it.

  * `{:error, message}` otherwise.

  """
  @spec put(map(), String.t(), String.t(), binary()) :: :ok | {:error, String.t()}
  def put(config, bucket, key, body) do
    with :ok <- check_key(key) do
      url = String.to_charlist("#{config.endpoint}/#{bucket}/#{key}")

      request = fn ->
        headers = sign("PUT", bucket, key, body, config)

        :httpc.request(
          :put,
          {url, headers, ~c"application/octet-stream", body},
          http_options(),
          []
        )
      end

      case retrying(request) do
        {:ok, {{_http, status, _reason}, _headers, _body}} when status in 200..299 ->
          :ok

        {:ok, {{_http, status, reason}, _headers, response}} ->
          {:error, "PUT #{key}: HTTP #{status} #{reason} #{response}"}

        {:error, reason} ->
          {:error, "PUT #{key}: #{inspect(reason)}"}
      end
    end
  end

  @doc """
  Reads an object.

  ### Arguments

  * `config` is the connection from `config/0`.

  * `bucket` is the bucket name.

  * `key` is the object key.

  ### Returns

  * `{:ok, body}` with the object's content.

  * `{:error, :not_found}` when there is no such object.

  * `{:error, message}` otherwise.

  """
  @spec get(map(), String.t(), String.t()) :: {:ok, binary()} | {:error, :not_found | String.t()}
  def get(config, bucket, key) do
    with :ok <- check_key(key) do
      url = String.to_charlist("#{config.endpoint}/#{bucket}/#{key}")

      request = fn ->
        headers = sign("GET", bucket, key, "", config)
        :httpc.request(:get, {url, headers}, http_options(), body_format: :binary)
      end

      case retrying(request) do
        {:ok, {{_http, 200, _reason}, _headers, body}} ->
          {:ok, body}

        {:ok, {{_http, 404, _reason}, _headers, _body}} ->
          {:error, :not_found}

        {:ok, {{_http, status, reason}, _headers, response}} ->
          {:error, "GET #{key}: HTTP #{status} #{reason} #{response}"}

        {:error, reason} ->
          {:error, "GET #{key}: #{inspect(reason)}"}
      end
    end
  end

  @doc """
  Returns an object's ETag, which for an object written in a single
  request, as `put/4` writes it, is the MD5 digest of its content.

  ### Arguments

  * `config` is the connection from `config/0`.

  * `bucket` is the bucket name.

  * `key` is the object key.

  ### Returns

  * `{:ok, etag}` with the ETag in lower-case hex, without quotes.

  * `{:error, :not_found}` when there is no such object.

  * `{:error, message}` otherwise.

  """
  @spec etag(map(), String.t(), String.t()) ::
          {:ok, String.t()} | {:error, :not_found | String.t()}
  def etag(config, bucket, key) do
    with :ok <- check_key(key) do
      url = String.to_charlist("#{config.endpoint}/#{bucket}/#{key}")

      request = fn ->
        headers = sign("HEAD", bucket, key, "", config)
        :httpc.request(:head, {url, headers}, http_options(), [])
      end

      case retrying(request) do
        {:ok, {{_http, 200, _reason}, headers, _body}} ->
          etag_header(headers, key)

        {:ok, {{_http, 404, _reason}, _headers, _body}} ->
          {:error, :not_found}

        {:ok, {{_http, status, reason}, _headers, _body}} ->
          {:error, "HEAD #{key}: HTTP #{status} #{reason}"}

        {:error, reason} ->
          {:error, "HEAD #{key}: #{inspect(reason)}"}
      end
    end
  end

  # `:httpc` gives header names in lower case.
  defp etag_header(headers, key) do
    case List.keyfind(headers, ~c"etag", 0) do
      {_name, etag} -> {:ok, etag |> List.to_string() |> String.trim("\"") |> String.downcase()}
      nil -> {:error, "HEAD #{key}: no ETag"}
    end
  end

  # R2, like S3, answers some requests with a transient error and asks for
  # them to be tried again ("500 InternalError … Please try again"), and a
  # connection can drop mid-request. Those are retried with exponential
  # backoff and jitter, each attempt signed afresh; anything else is final.
  @attempts 6
  @retryable_statuses [429, 500, 502, 503, 504]

  defp retrying(request, attempt \\ 1) do
    result = request.()

    if attempt < @attempts and retryable?(result) do
      Process.sleep(500 * Integer.pow(2, attempt - 1) + :rand.uniform(500))
      retrying(request, attempt + 1)
    else
      result
    end
  end

  defp retryable?({:ok, {{_http, status, _reason}, _headers, _body}}),
    do: status in @retryable_statuses

  defp retryable?({:error, _reason}), do: true

  defp check_key(key) do
    if Regex.match?(@key_pattern, key),
      do: :ok,
      else: {:error, "Unsupported R2 object key #{inspect(key)}"}
  end

  defp sign(method, bucket, key, body, config) do
    now = DateTime.utc_now()
    date_stamp = Calendar.strftime(now, "%Y%m%d")
    amz_date = Calendar.strftime(now, "%Y%m%dT%H%M%SZ")
    region = "auto"
    service = "s3"
    host = URI.parse(config.endpoint).host
    content_hash = hex_sha256(body)

    canonical_headers =
      "host:#{host}\nx-amz-content-sha256:#{content_hash}\nx-amz-date:#{amz_date}\n"

    signed_headers = "host;x-amz-content-sha256;x-amz-date"

    canonical_request =
      Enum.join(
        [method, "/#{bucket}/#{key}", "", canonical_headers, signed_headers, content_hash],
        "\n"
      )

    credential_scope = "#{date_stamp}/#{region}/#{service}/aws4_request"

    string_to_sign =
      Enum.join(
        ["AWS4-HMAC-SHA256", amz_date, credential_scope, hex_sha256(canonical_request)],
        "\n"
      )

    signature =
      ("AWS4" <> config.secret_key)
      |> hmac_sha256(date_stamp)
      |> hmac_sha256(region)
      |> hmac_sha256(service)
      |> hmac_sha256("aws4_request")
      |> hmac_sha256(string_to_sign)
      |> Base.encode16(case: :lower)

    authorization =
      "AWS4-HMAC-SHA256 Credential=#{config.access_key}/#{credential_scope}, " <>
        "SignedHeaders=#{signed_headers}, Signature=#{signature}"

    [
      {~c"Authorization", String.to_charlist(authorization)},
      {~c"x-amz-date", String.to_charlist(amz_date)},
      {~c"x-amz-content-sha256", String.to_charlist(content_hash)}
    ]
  end

  @doc false
  def http_options do
    [
      timeout: 120_000,
      ssl: [
        verify: :verify_peer,
        cacerts: :public_key.cacerts_get(),
        customize_hostname_check: [
          match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
        ]
      ]
    ]
  end

  defp hex_sha256(data), do: :crypto.hash(:sha256, data) |> Base.encode16(case: :lower)

  defp hmac_sha256(key, data), do: :crypto.mac(:hmac, :sha256, key, data)
end
