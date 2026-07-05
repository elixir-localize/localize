defmodule Mix.Tasks.Localize.UpdateCldr do
  @shortdoc "Runs the CLDR update pipeline: copy sources, regenerate data, verify"

  @moduledoc """
  Orchestrates phases 1–3 of the CLDR Update Guide
  (`CLDR_UPDATE_INTEGRATION.md`): copies the CLDR sources into the
  project, regenerates the supplemental and locale ETF data, and runs
  the verification gates between steps.

  The upstream checkouts must already be refreshed before running this
  task: check out the release tag in `CLDR_REPO` and regenerate
  `CLDR_PRODUCTION_DATA` with `scripts/ldml2json_v2`. The task
  verifies both and reports the source CLDR version before it starts.

  Each pipeline step and gate runs in a fresh VM (`mix` subprocess) so
  regenerated data is never read through a stale in-VM cache.

  This task stops at the end of phase 3. The conformance review
  (phase 4) and the release sequence — version bump, tag-triggered CDN
  upload, `mix localize.generate_locale_hashes --from-cdn` — are
  deliberately manual; the task prints them as next steps.

  ## Usage

      mix localize.update_cldr

  Runs the full pipeline: preflight, copy sources, generate
  supplemental data (gate: compile), generate all locales (gate:
  full test suite).

      mix localize.update_cldr --check

  Preflight only: verifies the source directories, reports the source
  and current CLDR versions, and prints the plan without changing
  anything.

      mix localize.update_cldr --locales en,fr,de

  Trial run against a locale subset.

  ## Options

  * `--check` — preflight and plan only; make no changes.

  * `--locales` — comma-separated locale subset to generate instead
    of all locales.

  * `--skip-locales` — stop after supplemental generation.

  * `--skip-tests` — skip the full-suite test gate (the compile gate
    always runs).

  ## Configuration

  * `CLDR_PRODUCTION_DATA` — path to the CLDR production data
    directory (default: `../cldr_production_data`).

  * `CLDR_REPO` — path to the Unicode CLDR repository checkout
    (default: `../cldr_repo`).

  """

  use Mix.Task

  @version_file "priv/localize/version"

  @impl Mix.Task
  def run(args) do
    {options, _rest} =
      OptionParser.parse!(args,
        strict: [check: :boolean, locales: :string, skip_locales: :boolean, skip_tests: :boolean]
      )

    preflight(options)

    if options[:check] do
      Mix.shell().info("\n--check: preflight only, nothing was changed.")
    else
      execute(options)
    end
  end

  # ── Preflight ────────────────────────────────────────────────

  defp preflight(options) do
    production_data = cldr_source_dir()
    cldr_repo = cldr_repo_dir()

    verify_directory!(production_data, "CLDR_PRODUCTION_DATA", "scripts/ldml2json_v2")
    verify_directory!(cldr_repo, "CLDR_REPO", "git clone github.com/unicode-org/cldr")

    source_version = source_cldr_version(production_data)
    current_version = current_cldr_version()

    Mix.shell().info("CLDR production data: #{production_data}")
    Mix.shell().info("CLDR repository:      #{cldr_repo}")
    Mix.shell().info("Source CLDR version:  #{source_version || "NOT DETECTABLE"}")
    Mix.shell().info("Current data version: #{current_version || "none"}")

    if is_nil(source_version) do
      Mix.raise("""
      Could not read the CLDR version from
      #{aliases_json_path(production_data)}.
      Is CLDR_PRODUCTION_DATA a cldr-json layout produced by scripts/ldml2json_v2?
      """)
    end

    if source_version == current_version do
      Mix.shell().info("""

      Note: source and current CLDR versions match (#{source_version}).
      This run will regenerate the same release — expected for pipeline
      changes within a CLDR version (remember `mix localize.bump_patch_version`),
      unexpected if you meant to upgrade CLDR itself.
      """)
    end

    Mix.shell().info("\nPlan:")
    Mix.shell().info("  1. mix localize.copy_sources")
    Mix.shell().info("  2. mix localize.generate_supplemental")
    Mix.shell().info("  3. gate: mix compile --warnings-as-errors")

    unless options[:skip_locales] do
      Mix.shell().info("  4. mix localize.generate_locales #{options[:locales] || "(all)"}")
    end

    unless options[:skip_tests] do
      Mix.shell().info("  5. gate: mix test (MIX_ENV=test)")
    end
  end

  defp verify_directory!(path, name, how_to_create) do
    unless File.dir?(path) do
      Mix.raise("""
      #{name} not found at #{path}.
      Create it first (#{how_to_create}) or point #{name} at it.
      """)
    end
  end

  # ── Execution ────────────────────────────────────────────────

  defp execute(options) do
    step("Copying CLDR sources", ["localize.copy_sources"])
    step("Generating supplemental data", ["localize.generate_supplemental"])

    gate(
      "Compile (picks up @external_resource recompiles)",
      ["compile", "--warnings-as-errors"],
      """
      Compilation failed after supplemental regeneration. A CLDR
      data-shape change usually means a normalizer in data/normalize/
      needs updating — fix the normalizer, never the generated file.
      See CLDR_UPDATE_INTEGRATION.md phase 2.
      """
    )

    unless options[:skip_locales] do
      locale_args = locale_arguments(options[:locales])
      step("Generating locale data", ["localize.generate_locales" | locale_args])
    end

    unless options[:skip_tests] do
      gate(
        "Full test suite",
        ["test"],
        """
        Tests failed against the regenerated data. Expected-output
        changes from the new CLDR data belong in the changelog and the
        tests; crashes usually mean a data-shape change reached the
        runtime. See CLDR_UPDATE_INTEGRATION.md phases 3-4.
        """,
        [{"MIX_ENV", "test"}]
      )
    end

    print_next_steps()
  end

  defp locale_arguments(nil), do: []
  defp locale_arguments(csv), do: String.split(csv, ",", trim: true)

  defp step(label, mix_args) do
    case run_mix(label, mix_args, []) do
      :ok ->
        :ok

      :error ->
        Mix.raise("#{label} failed. Fix the error above and re-run; the task is idempotent.")
    end
  end

  defp gate(label, mix_args, failure_guidance, env \\ []) do
    case run_mix("Gate: " <> label, mix_args, env) do
      :ok -> :ok
      :error -> Mix.raise("Gate failed — #{label}.\n\n#{failure_guidance}")
    end
  end

  defp run_mix(label, mix_args, env) do
    Mix.shell().info("\n==> #{label}: mix #{Enum.join(mix_args, " ")}")

    {_output, status} =
      System.cmd("mix", mix_args,
        into: IO.stream(:stdio, :line),
        env: env,
        stderr_to_stdout: true
      )

    if status == 0, do: :ok, else: :error
  end

  defp print_next_steps do
    Mix.shell().info("""

    Pipeline complete. Remaining phases (CLDR_UPDATE_INTEGRATION.md):

      * Phase 4 — conformance review against the TR35 changes and the
        new common/testData fixtures; run the full six-gate stack.
      * Phase 5 — bump the version and changelog, commit, tag. The tag
        push uploads locales to the CDN; AFTER the upload completes run

            mix localize.generate_locale_hashes --from-cdn

        and commit the manifest, then publish.
      * If this was a pipeline change within the same CLDR version,
        run `mix localize.bump_patch_version` before phase 5.
    """)
  end

  # ── Source and version helpers ───────────────────────────────

  defp cldr_source_dir do
    System.get_env("CLDR_PRODUCTION_DATA") ||
      Path.join([File.cwd!(), "..", "cldr_production_data"]) |> Path.expand()
  end

  defp cldr_repo_dir do
    System.get_env("CLDR_REPO") ||
      Path.join([File.cwd!(), "..", "cldr_repo"]) |> Path.expand()
  end

  defp aliases_json_path(production_data) do
    Path.join([production_data, "cldr-core", "supplemental", "aliases.json"])
  end

  defp source_cldr_version(production_data) do
    path = aliases_json_path(production_data)

    with {:ok, binary} <- File.read(path),
         decoded when is_map(decoded) <- :json.decode(binary) do
      get_in(decoded, ["supplemental", "version", "_cldrVersion"])
    else
      _no_version -> nil
    end
  end

  defp current_cldr_version do
    case File.read(Path.join(File.cwd!(), @version_file)) do
      {:ok, content} -> String.trim(content)
      {:error, _} -> nil
    end
  end
end
