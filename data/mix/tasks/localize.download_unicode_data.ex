defmodule Mix.Tasks.Localize.DownloadUnicodeData do
  @shortdoc "Downloads Unicode Character Database files for collation"

  @moduledoc """
  Downloads the `DerivedCombiningClass` and `DerivedGeneralCategory` files
  from the Unicode Character Database into `priv/unicode/`.

  These generate the compact ETF lookup tables the collation system uses for
  combining class and decimal digit checks.

  The Unicode version is not configured here. It is read from the
  `# VERSION: ... UCD=x.y.z` header of `priv/cldr/FractionalUCA.txt`, so the
  property files always match the CLDR release the UCA table came from. Run
  `mix localize.copy_sources` first if that file is not present.

  `mix localize.copy_sources` calls this too, so the files are refreshed as
  part of a normal CLDR update; run it directly to force a check.

  ## Usage

      mix localize.download_unicode_data

  """

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.config")
    {:ok, _started} = Application.ensure_all_started(:localize)

    case Localize.Data.UnicodeData.ensure_ucd_files() do
      {:ok, :current} ->
        :ok

      {:ok, :downloaded} ->
        Mix.shell().info(
          "Done. Run `mix localize.generate_supplemental` to regenerate the ETF files."
        )

      {:error, reason} ->
        Mix.raise(to_string(reason))
    end
  end
end
