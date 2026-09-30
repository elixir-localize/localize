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

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.config")
    {:ok, _started} = Application.ensure_all_started(:localize)

    {opts, locale_args} =
      OptionParser.parse!(args, strict: [version: :string, bucket: :string])

    version = opts[:version] || Mix.raise("--version is required")

    bucket =
      opts[:bucket] || System.get_env("R2_BUCKET") || Mix.raise("--bucket or R2_BUCKET required")

    if locale_args == [] do
      Mix.raise("At least one locale argument is required")
    end

    config =
      case Localize.Data.R2.config() do
        {:ok, config} -> config
        {:error, message} -> Mix.raise(message)
      end

    output_dir = Localize.Data.locales_output_dir()
    File.mkdir_p!(output_dir)

    Enum.each(locale_args, fn locale ->
      Mix.shell().info("Generating #{locale}...")
      Localize.Data.Locale.generate_and_save_locale(locale)

      etf_path = Path.join(output_dir, "#{locale}.etf")
      object_key = "#{version}/#{locale}.etf"
      body = File.read!(etf_path)

      Mix.shell().info("Uploading #{object_key} to R2 bucket #{bucket}...")

      case Localize.Data.R2.put(config, bucket, object_key, body) do
        :ok -> Mix.shell().info("  Uploaded #{object_key} (#{byte_size(body)} bytes)")
        {:error, message} -> Mix.raise("R2 upload failed: #{message}")
      end
    end)

    Mix.shell().info("Done. Uploaded #{length(locale_args)} locales.")
  end
end
