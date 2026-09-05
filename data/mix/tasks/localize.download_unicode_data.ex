defmodule Mix.Tasks.Localize.DownloadUnicodeData do
  @shortdoc "Downloads Unicode Character Database files for collation"

  @moduledoc """
  Downloads the DerivedCombiningClass and DerivedGeneralCategory
  files from the Unicode Character Database.

  These files are used to generate compact ETF lookup tables for
  the collation system's combining class and decimal digit checks.

  ## Usage

      mix localize.download_unicode_data

  The files are saved to `priv/unicode/`.

  """

  use Mix.Task

  @unicode_version "18.0.0"
  @base_url "https://www.unicode.org/Public/#{@unicode_version}/ucd/extracted"

  @files [
    {"DerivedCombiningClass.txt", "combining_class.txt"},
    {"DerivedGeneralCategory.txt", "general_category.txt"}
  ]

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.config")
    {:ok, _started} = Application.ensure_all_started(:localize)
    :ssl.start()
    :inets.start()

    output_dir = Path.join([File.cwd!(), "priv", "unicode"])
    File.mkdir_p!(output_dir)

    for {source, dest} <- @files do
      url = "#{@base_url}/#{source}"
      output_path = Path.join(output_dir, dest)

      Mix.shell().info("Downloading #{source}...")

      case download(url) do
        {:ok, body} ->
          File.write!(output_path, body)
          Mix.shell().info("  Saved to #{output_path} (#{byte_size(body)} bytes)")

        {:error, reason} ->
          Mix.raise("Download failed for #{url}: #{inspect(reason)}")
      end
    end

    Mix.shell().info("Done. Run `mix localize.generate_supplemental` to regenerate ETF files.")
  end

  defp download(url) do
    url_charlist = String.to_charlist(url)

    case :httpc.request(:get, {url_charlist, []}, [ssl: ssl_options()], []) do
      {:ok, {{_http, status, _reason}, _headers, body}} when status in 200..299 ->
        {:ok, :erlang.list_to_binary(body)}

      {:ok, {{_http, status, reason}, _headers, _body}} ->
        {:error, "HTTP #{status} #{reason}"}

      {:error, reason} ->
        {:error, reason}
    end
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
