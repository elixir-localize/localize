defmodule Localize.Supervisor do
  @moduledoc """
  The `:localize` runtime supervisor.

  Owns the small set of processes the library needs at runtime — the
  data loader, the locale loader (which owns the locale-validation
  ETS table), the cache sweeper, the format cache, and the collation
  ICU table — and runs the one-time post-start work that interns
  every supplemental atom and resolves the configured
  `:supported_locales`.

  By default this supervisor is started automatically when the
  `:localize` OTP application boots, so callers do not need to start
  it themselves. Applications that prefer to manage Localize's
  lifecycle alongside their own processes can disable that auto-start
  and mount this supervisor as a child of their own tree instead.

  ## Manual supervision

  Mark the dependency as `runtime: false` in `mix.exs` so the OTP
  application is not auto-started:

      # mix.exs
      def deps do
        [
          {:localize, "~> 0.33", runtime: false}
        ]
      end

  Then add the supervisor to your application's tree:

      # lib/my_app/application.ex
      def start(_type, _args) do
        children = [
          MyApp.Repo,
          Localize.Supervisor,
          MyAppWeb.Endpoint
        ]

        Supervisor.start_link(children, strategy: :one_for_one)
      end

  Place `Localize.Supervisor` after any process that loads compile-time
  config Localize depends on (typically none) and before any process
  that calls Localize functions at startup (formatters, importers,
  background workers).

  See `guides/supervision.md` for a more detailed walk-through.

  """

  require Logger

  @doc """
  Starts the Localize supervisor.

  ### Arguments

  * `options` is a keyword list.

  ### Options

  * No options are currently honoured — the argument exists so
    callers can use the `{Localize.Supervisor, []}` child-spec
    shape without surprise.

  ### Returns

  * `{:ok, pid}` on success.

  * `{:error, reason}` if startup fails.

  """
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(options \\ []) when is_list(options) do
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

    case Supervisor.start_link(children, strategy: :one_for_one, name: __MODULE__) do
      {:ok, pid} ->
        after_start()
        {:ok, pid}

      {:error, _reason} = error ->
        error
    end
  end

  @doc """
  Default child spec.

  Lets callers add `Localize.Supervisor` (or `{Localize.Supervisor, []}`)
  directly to their own application's `children` list.

  ### Arguments

  * `options` is a keyword list passed through to `start_link/1`.

  ### Options

  * No options are currently honoured. See `start_link/1`.

  ### Returns

  * A `t:Supervisor.child_spec/0` map.

  ### Examples

      iex> Localize.Supervisor.child_spec([]).type
      :supervisor

  """
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(options \\ []) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [options]},
      type: :supervisor
    }
  end

  # One-time work that must happen exactly once when the Localize
  # runtime comes up, regardless of whether it was auto-started as
  # part of the `:localize` OTP application or mounted manually
  # under a consumer's supervision tree. Idempotent — running twice
  # is harmless.
  defp after_start do
    ensure_json_module!()
    validate_locale_cache_dir!()
    resolve_supported_locales()
    intern_supplemental_atoms()
    Localize.Number.Format.Compiler.precompile_regexes()
    :ok
  end

  # Localize decodes JSON with the OTP 27+ `:json` module. On OTP 26
  # the `json_polyfill` package provides it, but the dependency is
  # optional so OTP 27+ consumers carry no extra dependency. Failing
  # here with instructions beats a mystifying UndefinedFunctionError
  # on first JSON use deep inside a formatting call.
  defp ensure_json_module! do
    unless Code.ensure_loaded?(:json) do
      raise """
      The :json module is not available. Localize requires the OTP 27+ \
      :json module. On OTP 26, add the polyfill to your dependencies:

          {:json_polyfill, "~> 0.2 or ~> 1.0"}
      """
    end

    :ok
  end

  # Refuse `:locale_cache_dir` configurations that would silently
  # break in at least one runtime phase — chiefly relative path
  # strings, which resolve against the BEAM's current working
  # directory and therefore point at different filesystems in mix
  # tasks vs `mix test` vs a release. See
  # `Localize.LocaleCacheDirError` for the recommended form.
  defp validate_locale_cache_dir! do
    Localize.Locale.Provider.validate_locale_cache_dir!()
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
  # Locked down by `test/localize/atom_interning_test.exs`.
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
