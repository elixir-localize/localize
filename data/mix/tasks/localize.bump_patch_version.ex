defmodule Mix.Tasks.Localize.BumpPatchVersion do
  @shortdoc "Bumps the Localize patch version for the current CLDR release"

  @moduledoc """
  Increments the Localize patch version stored in
  `priv/localize/localize_patch_version`.

  The patch version tracks Localize-side changes to the locale data
  generation pipeline (normalizers, struct transforms, etc.) within
  a single CLDR release. It is **not** bumped automatically by
  `mix localize.generate_locales` — generation can therefore run
  unattended in CI without producing phantom version bumps.

  Run this task explicitly when you have changed the data pipeline
  and want the next regeneration of locale ETF files to record a
  new version. Typical workflow:

      mix localize.bump_patch_version
      mix localize.generate_locales

  When the upstream CLDR release version changes (i.e. when
  `mix localize.copy_sources` writes a new value to
  `priv/localize/version`), the patch counter is automatically
  reset to `0`. The first `mix localize.bump_patch_version` after
  a CLDR upgrade therefore takes the patch from `0` to `1`.

  ## Storage format

  The patch file uses the format `"{cldr_version}:{patch}"` (for
  example `"48.2:3"`) so that an old patch file is unambiguously
  associated with its CLDR release.

  ## Output

  Prints the new patch version, for example:

      Patch version updated to 48.2:4

  """

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")
    _ = Localize.Data.bump_patch_version()
    :ok
  end
end
