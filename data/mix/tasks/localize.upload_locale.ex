defmodule Mix.Tasks.Localize.UploadLocale do
  @shortdoc "Generates a locale and uploads it to Cloudflare R2"

  @moduledoc """
  Generates a single locale ETF file and uploads it to Cloudflare R2.

  ## Usage

      mix localize.upload_locale --version 48 en
      mix localize.upload_locale --version 48 en fr de

  ## Options

  * `--version` (required) — the CLDR version string used as the
    path prefix in R2. The uploaded object key will be
    `<version>/<locale>.etf`.

  * `--bucket` — the R2 bucket name. Defaults to the
    `R2_BUCKET` environment variable.

  ## Environment variables

  * `R2_ACCOUNT_ID` — Cloudflare account ID for the
    `elixir-localize` account.

  * `R2_ACCESS_KEY_ID` — R2 API token access key.

  * `R2_SECRET_ACCESS_KEY` — R2 API token secret key.

  * `R2_BUCKET` — R2 bucket name (can be overridden with `--bucket`).

  """

  use Mix.Task

  @r2_endpoint "https://{account_id}.r2.cloudflarestorage.com"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, locale_args} =
      OptionParser.parse!(args, strict: [version: :string, bucket: :string])

    version = opts[:version] || Mix.raise("--version is required")

    bucket =
      opts[:bucket] || System.get_env("R2_BUCKET") || Mix.raise("--bucket or R2_BUCKET required")

    if locale_args == [] do
      Mix.raise("At least one locale argument is required")
    end

    config = r2_config()

    output_dir = Localize.Data.locales_output_dir()
    File.mkdir_p!(output_dir)

    Enum.each(locale_args, fn locale ->
      Mix.shell().info("Generating #{locale}...")
      Localize.Data.Locale.generate_and_save_locale(locale)

      etf_path = Path.join(output_dir, "#{locale}.etf")
      object_key = "#{version}/#{locale}.etf"

      Mix.shell().info("Uploading #{object_key} to R2 bucket #{bucket}...")
      upload_to_r2(etf_path, bucket, object_key, config)
    end)

    Mix.shell().info("Done. Uploaded #{length(locale_args)} locales.")
  end

  defp r2_config do
    account_id = System.get_env("R2_ACCOUNT_ID") || Mix.raise("R2_ACCOUNT_ID not set")
    access_key = System.get_env("R2_ACCESS_KEY_ID") || Mix.raise("R2_ACCESS_KEY_ID not set")

    secret_key =
      System.get_env("R2_SECRET_ACCESS_KEY") || Mix.raise("R2_SECRET_ACCESS_KEY not set")

    endpoint = String.replace(@r2_endpoint, "{account_id}", account_id)

    %{
      endpoint: endpoint,
      access_key: access_key,
      secret_key: secret_key
    }
  end

  defp upload_to_r2(file_path, bucket, object_key, config) do
    body = File.read!(file_path)
    url = "#{config.endpoint}/#{bucket}/#{object_key}"

    headers = sign_request("PUT", bucket, object_key, body, config)

    case :httpc.request(
           :put,
           {String.to_charlist(url), headers, ~c"application/octet-stream", body},
           [ssl: ssl_options()],
           []
         ) do
      {:ok, {{_http, status, _reason}, _headers, _body}} when status in 200..299 ->
        Mix.shell().info("  Uploaded #{object_key} (#{byte_size(body)} bytes)")

      {:ok, {{_http, status, reason}, _headers, resp_body}} ->
        Mix.raise("R2 upload failed: HTTP #{status} #{reason}\n#{resp_body}")

      {:error, reason} ->
        Mix.raise("R2 upload failed: #{inspect(reason)}")
    end
  end

  defp sign_request(method, bucket, object_key, body, config) do
    now = DateTime.utc_now()
    date_stamp = Calendar.strftime(now, "%Y%m%d")
    amz_date = Calendar.strftime(now, "%Y%m%dT%H%M%SZ")
    region = "auto"
    service = "s3"

    host =
      config.endpoint
      |> URI.parse()
      |> Map.get(:host)

    content_hash = hex_sha256(body)

    canonical_uri = "/#{bucket}/#{object_key}"

    canonical_headers =
      "host:#{host}\nx-amz-content-sha256:#{content_hash}\nx-amz-date:#{amz_date}\n"

    signed_headers = "host;x-amz-content-sha256;x-amz-date"

    canonical_request =
      Enum.join(
        [
          String.upcase(method),
          canonical_uri,
          "",
          canonical_headers,
          signed_headers,
          content_hash
        ],
        "\n"
      )

    credential_scope = "#{date_stamp}/#{region}/#{service}/aws4_request"

    string_to_sign =
      Enum.join(
        [
          "AWS4-HMAC-SHA256",
          amz_date,
          credential_scope,
          hex_sha256(canonical_request)
        ],
        "\n"
      )

    signing_key =
      ("AWS4" <> config.secret_key)
      |> hmac_sha256(date_stamp)
      |> hmac_sha256(region)
      |> hmac_sha256(service)
      |> hmac_sha256("aws4_request")

    signature = hmac_sha256(signing_key, string_to_sign) |> Base.encode16(case: :lower)

    authorization =
      "AWS4-HMAC-SHA256 Credential=#{config.access_key}/#{credential_scope}, " <>
        "SignedHeaders=#{signed_headers}, Signature=#{signature}"

    [
      {~c"Authorization", String.to_charlist(authorization)},
      {~c"x-amz-date", String.to_charlist(amz_date)},
      {~c"x-amz-content-sha256", String.to_charlist(content_hash)}
    ]
  end

  defp hex_sha256(data) do
    :crypto.hash(:sha256, data) |> Base.encode16(case: :lower)
  end

  defp hmac_sha256(key, data) do
    :crypto.mac(:hmac, :sha256, key, data)
  end

  defp ssl_options do
    [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      customize_hostname_check: [
        match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
      ]
    ]
  end
end
