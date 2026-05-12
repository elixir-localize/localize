defmodule Localize.Application do
  @moduledoc false

  use Application

  require Logger

  @impl true
  def start(_type \\ :normal, _args \\ []) do
    children = [
      Localize.DataLoader,
      # `Localize.Locale.Loader` owns the `:localize_locale_cache`
      # ETS table (created in its `init/1`); it must start before any
      # supervisor child that may need the table.
      Localize.Locale.Loader,
      Localize.Locale.CacheSweeper,
      Localize.FormatCache,
      Localize.Collation.Table
    ]

    options = [strategy: :one_for_one, name: Localize.Supervisor]

    case Supervisor.start_link(children, options) do
      {:ok, pid} ->
        resolve_supported_locales()
        intern_supplemental_atoms()
        {:ok, pid}

      error ->
        error
    end
  end

  # Force-load every bundled supplemental data set whose constituent
  # atoms are consumed via `Helpers.existing_atom/1` (i.e.,
  # `binary_to_existing_atom`) elsewhere in the library.
  #
  # The security-hardening pass in 0.30.0 switched a large number of
  # lookups — currency codes, territory codes, script codes,
  # language codes, subdivisions, unit names, number-system names,
  # calendar names, locale ids — to `existing_atom` so that
  # attacker-supplied binary input cannot grow the atom table. That
  # defence is correct, but it requires the legitimate atoms to
  # already exist when the lookup runs. Without this eager-load,
  # a valid input like `numberingSystem=arab` could resolve to `nil`
  # in a fresh BEAM (because no prior code had read the supplemental
  # ETF that interns `:arab`) and surface as a spurious
  # "unknown numbering system" error.
  #
  # Each accessor below reads a bundled `.etf` file via
  # `:erlang.binary_to_term/1`, which interns every atom that appears
  # in the term as a side-effect. After this function returns, every
  # known language / script / territory / variant / subdivision /
  # unit / number-system / calendar / currency / timezone / locale-id
  # atom is present in the atom table for the lifetime of the BEAM.
  #
  # The cost is a one-time read per dataset at app start. Locked
  # down by `test/localize/atom_interning_test.exs`.
  defp intern_supplemental_atoms do
    alias Localize.SupplementalData

    _ = SupplementalData.validity(:languages)
    _ = SupplementalData.validity(:scripts)
    _ = SupplementalData.validity(:territories)
    _ = SupplementalData.validity(:variants)
    _ = SupplementalData.validity(:subdivisions)
    _ = SupplementalData.validity(:units)
    _ = SupplementalData.currency_codes()
    _ = SupplementalData.calendars()
    _ = SupplementalData.timezones()
    _ = SupplementalData.territory_subdivisions()
    _ = SupplementalData.all_locale_ids()
    _ = Localize.Number.System.number_systems()
    :ok
  end

  # ── Supported locales ───────────────────────────────────────────

  defp resolve_supported_locales do
    maybe_warn_deprecated_preload()
    _ = Localize.supported_locales()
    :ok
  end

  defp maybe_warn_deprecated_preload do
    case Application.get_env(:localize, :preload_locales) do
      nil ->
        :ok

      _configured ->
        Logger.warning(
          "The :preload_locales configuration key is deprecated and ignored. " <>
            "Use :supported_locales to declare your locale set, and " <>
            "`mix localize.download_locales` to pre-populate the cache " <>
            "at build time. Locale data is loaded lazily into " <>
            ":persistent_term on first access.",
          domain: [:localize]
        )
    end
  end
end
