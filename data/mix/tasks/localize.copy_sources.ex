defmodule Mix.Tasks.Localize.CopySources do
  @shortdoc "Copies CLDR source files into the project for reproducible builds"

  @moduledoc """
  Copies raw CLDR source files into `priv/cldr/` so that the project
  contains all data needed for reproducible ETF generation.

  JSON files are copied from `CLDR_PRODUCTION`. XML files
  (supplemental and collation) are copied from `CLDR_REPO`.

  ## Usage

      mix localize.copy_sources

  Copies supplemental, collation, and locale source files.

      mix localize.copy_sources --supplemental

  Copies only supplemental and collation source files.

      mix localize.copy_sources --locales

  Copies only locale source files.

  ## Output

  * `priv/cldr/supplemental_data/` — supplemental JSON and XML files.

  * `priv/cldr/collation/` — collation XML files from CLDR_REPO.

  * `priv/cldr/locales/<locale>/` — per-locale JSON and XML files.

  * `priv/localize/version` — CLDR version string.

  ## Configuration

  * `CLDR_PRODUCTION` — path to the CLDR production data
    directory. Without it, the first of `../cldr_production_data`
    and `../../cldr/cldr_production_data` that exists is used.

  * `CLDR_REPO` — path to the Unicode CLDR repository checkout.
    Without it, the first of `../cldr_repo` and `../../cldr/cldr_repo`
    that exists is used.

  Either variable pointing at a directory that does not exist stops the
  task before it copies anything.

  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.config")
    {:ok, _started} = Application.ensure_all_started(:localize)

    {opts, _rest} =
      OptionParser.parse!(args, strict: [supplemental: :boolean, locales: :boolean])

    verify_source_dir!("CLDR_PRODUCTION", Localize.Data.cldr_source_dir())
    verify_source_dir!("CLDR_REPO", Localize.Data.cldr_repo_dir())

    do_supplemental = opts[:supplemental] || (!opts[:supplemental] && !opts[:locales])
    do_locales = opts[:locales] || (!opts[:supplemental] && !opts[:locales])

    if do_supplemental do
      Localize.Data.copy_supplemental_sources()
      Localize.Data.copy_collation_sources()
      Localize.Data.copy_validity_sources()
      Localize.Data.copy_bcp47_sources()
      Localize.Data.copy_script_metadata()
      Localize.Data.copy_uca_table()

      # Must follow copy_uca_table/0: the UCD version to fetch is read from
      # the FractionalUCA.txt header it just wrote.
      case Localize.Data.UnicodeData.ensure_ucd_files() do
        {:ok, _} -> :ok
        {:error, reason} -> Mix.raise(to_string(reason))
      end
    end

    if do_locales do
      Localize.Data.copy_locale_sources()
    end

    # Always copy test data
    Localize.Data.copy_test_data()
    Localize.Data.copy_rbnf_test_data()

    Localize.Data.write_version()
    Mix.shell().info("Done.")
  end

  # Copying reads thousands of files, so a wrong source directory
  # otherwise surfaces as a `File.CopyError` partway through, naming a
  # file rather than the setting that sent it there.
  defp verify_source_dir!(variable, path) do
    unless File.dir?(path) do
      Mix.raise("""
      #{variable} directory not found at #{path}

      Set #{variable} to the directory holding the CLDR sources, or place the
      checkouts where the defaults look for them: beside this project, or in
      a `cldr` directory beside it. For example:

          #{variable}=$HOME/Development/cldr/#{Path.basename(path)} mix localize.copy_sources

      `scripts/build_cldr_production_data` builds the production data.
      """)
    end
  end
end
