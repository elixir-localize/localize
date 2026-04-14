defmodule Mix.Tasks.Localize.DownloadIsoCurrencies do
  @shortdoc "Downloads ISO 4217 currency codes from the SIX Group"

  @moduledoc """
  Downloads the current ISO 4217 currency code list from the
  official SIX Group (Swiss Financial Market Infrastructure) source.

  The downloaded XML file is saved to
  `priv/cldr/external_sources/iso_currencies.xml`.

  ## Usage

      mix localize.download_iso_currencies

  ## Source

  The data is fetched from the SIX Group's ISO currency list
  (list-one.xml), which is the authoritative source for ISO 4217
  currency codes, names, and minor unit (decimal digit) counts.

  """

  use Mix.Task

  @url "https://www.six-group.com/dam/download/financial-information/data-center/iso-currrency/lists/list-one.xml"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.config")
    {:ok, _started} = Application.ensure_all_started(:localize)
    :ssl.start()
    :inets.start()

    output_dir = Localize.Data.external_sources_dir()
    File.mkdir_p!(output_dir)
    output_path = Path.join(output_dir, "iso_currencies.xml")

    Mix.shell().info("Downloading ISO 4217 currency codes...")

    case download(@url) do
      {:ok, body} ->
        File.write!(output_path, body)
        Mix.shell().info("Saved to #{output_path} (#{byte_size(body)} bytes)")

      {:error, reason} ->
        Mix.raise("Download failed: #{inspect(reason)}")
    end
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
