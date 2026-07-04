defmodule Mix.Tasks.Localize.GenerateLocaleHashes do
  @shortdoc "Generates the locale download-integrity hash manifest"

  @moduledoc """
  Generates `priv/localize/locale_hashes.etf`, the SHA-256 manifest
  used to verify locale files downloaded from the CDN.

  The manifest maps each locale identifier atom to the SHA-256 hash
  of its generated ETF file. `Localize.Locale.Provider.download_locale/1`
  verifies every download against it before the content is decoded or
  cached, so the hashes pin exactly the bytes this package release was
  generated from.

  Run this after `mix localize.generate_locales` (against the same
  output) and before publishing a release, so the manifest matches the
  data uploaded to the CDN.

  ## Usage

      mix localize.generate_locale_hashes

  ## Arguments

  * `--locales-dir PATH` — the directory containing the generated
    locale `.etf` files. Defaults to the configured locale cache
    directory (the same directory `mix localize.generate_locales`
    writes to).

  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.config")
    {:ok, _started} = Application.ensure_all_started(:localize)

    {options, _rest} = OptionParser.parse!(args, strict: [locales_dir: :string])

    locales_dir =
      Keyword.get(options, :locales_dir) || Localize.Data.locales_output_dir()

    Localize.Data.generate_locale_hashes(locales_dir)
  end
end
