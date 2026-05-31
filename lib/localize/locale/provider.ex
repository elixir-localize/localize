defmodule Localize.Locale.Provider do
  @moduledoc """
  Defines the behaviour for locale data providers.

  A locale data provider is responsible for loading, storing, and
  retrieving CLDR locale data. Implementations may store data in
  any backing store such as `:persistent_term`, ETS, or the
  filesystem.

  ## Callbacks

  Implementing modules must define four callbacks:

  * `load/1` — finds and retrieves locale data for a given locale.

  * `store/2` — persists locale data to the provider's backing store.

  * `loaded?/1` — checks whether a locale's data has been loaded
    and is available for use.

  * `get/3` — retrieves a specific value from locale data by
    following a list of access keys, with optional fallback to
    parent locales.

  """

  @typedoc "A locale identifier as an atom."
  @type locale_id :: atom()

  @typedoc "A locale reference: either a locale identifier atom or a language tag struct."
  @type locale :: locale_id() | Localize.LanguageTag.t()

  # ── Behaviour callbacks ────────────────────────────────────────

  @doc """
  Loads locale data for the given locale.

  Finds the locale data for the given locale identifier or
  language tag, retrieves it from the data source, and returns
  the data as a map.

  ### Arguments

  * `locale` is a locale identifier atom or a `t:Localize.LanguageTag.t/0`.

  ### Returns

  * `{:ok, locale_data}` where `locale_data` is a map of the locale's
    CLDR data.

  * `{:error, Localize.UnknownLocaleError.t()}` if the locale is not
    recognized.

  """
  @callback load(locale()) ::
              {:ok, map()} | {:error, Exception.t()}

  @doc """
  Stores locale data in the provider's backing store.

  ### Arguments

  * `locale` is a locale identifier atom.

  * `locale_data` is a map of locale data to store.

  ### Returns

  * `:ok` on success.

  * `{:error, reason}` on failure.

  """
  @callback store(locale_id(), map()) ::
              :ok | {:error, term()}

  @doc """
  Returns whether locale data has been loaded and is available.

  ### Arguments

  * `locale` is a locale identifier atom or a `t:Localize.LanguageTag.t/0`.

  ### Returns

  * `true` if the locale data has been loaded and stored.

  * `false` otherwise.

  """
  @callback loaded?(locale()) :: boolean()

  @doc """
  Retrieves a value from locale data by following a list of access keys.

  Navigates the locale data map using the provided list of keys,
  returning the value found at the end of the key path.

  ### Arguments

  * `locale` is a locale identifier atom or a `t:Localize.LanguageTag.t/0`.

  * `keys` is a list of keys to traverse in the locale data map.

  * `options` is a keyword list of options. The default is `[]`.

  ### Options

  * `:fallback` is a boolean. When `true`, if the requested key path
    is not found in the given locale, the provider will attempt to
    find it in parent locales according to the CLDR locale inheritance
    chain. The default is `false`.

  ### Returns

  * `{:ok, value}` if the key path resolves to a value.

  * `{:error, reason}` if the key path cannot be resolved.

  """
  @callback get(locale(), list(), Keyword.t()) ::
              {:ok, term()} | {:error, term()}

  @doc """
  Returns whether this provider is permitted to download locale
  data from a remote source at runtime.

  Providers that never download (e.g. a database-backed provider)
  should return `false`. Providers that always have data locally
  available can simply not implement this callback — the default
  implementation reads `Application.get_env(:localize,
  :allow_runtime_locale_download, false)`.

  """
  @callback allow_download?() :: boolean()

  @optional_callbacks [allow_download?: 0]

  @doc """
  Returns whether runtime locale downloads are permitted for the
  given provider module.

  If the provider module implements the optional `allow_download?/0`
  callback, that implementation is called. Otherwise falls back to
  the `:allow_runtime_locale_download` application environment key
  (default `false`).

  ### Arguments

  * `provider_module` is a module that implements the
    `Localize.Locale.Provider` behaviour. The default is the
    currently configured provider.

  ### Returns

  * `true` if runtime downloads are permitted.

  * `false` otherwise.

  """
  @spec allow_download?(module()) :: boolean()
  def allow_download?(provider_module \\ configured_provider()) do
    if function_exported?(provider_module, :allow_download?, 0) do
      provider_module.allow_download?()
    else
      Application.get_env(:localize, :allow_runtime_locale_download, false)
    end
  end

  defp configured_provider do
    Application.get_env(:localize, :locale_provider, Localize.Locale.Provider.PersistentTerm)
  end

  @doc """
  Loads locale data with fallback through the CLDR parent chain.

  Attempts to load the requested locale via `provider.load/1`. If the
  load fails, walks up the CLDR locale inheritance chain (e.g.
  `en-AU` → `en` → `und`) trying each parent in turn. If the entire
  chain is exhausted without success, falls back to `:en` which is
  guaranteed to be present.

  Returns `{:ok, locale_data, resolved_locale_id}` so the caller
  knows which locale was actually loaded.

  ### Arguments

  * `provider` is the module implementing `Localize.Locale.Provider`.

  * `locale` is a locale identifier atom or a `t:Localize.LanguageTag.t/0`.

  ### Returns

  * `{:ok, locale_data, resolved_locale_id}` on success.

  * `{:error, exception}` if even the `:en` fallback fails (should not
    happen in normal operation).

  """
  @spec load_with_fallback(module(), locale()) ::
          {:ok, map(), locale_id()} | {:error, Exception.t()}
  def load_with_fallback(provider, locale) do
    with {:ok, locale_id} <- Localize.Locale.cldr_locale_id_from(locale) do
      case provider.load(locale) do
        {:ok, locale_data} ->
          {:ok, locale_data, locale_id}

        {:error, _exception} ->
          require Logger

          Logger.debug(
            "Requested locale #{inspect(locale_id)} is not available. Trying parent locales.",
            domain: [:localize]
          )

          walk_parent_chain(provider, locale_id, locale_id, [locale_id])
      end
    end
  end

  defp walk_parent_chain(provider, locale_id, original_locale_id, visited) do
    require Logger

    with {:ok, parent_tag} <- Localize.Locale.parent(to_string(locale_id)),
         {:ok, parent_id} <- Localize.Locale.cldr_locale_id_from(parent_tag) do
      # Cycle guard. `Localize.Locale.parent/1` returns `und` for
      # bare languages like `ja`, and `cldr_locale_id_from/1` used to run
      # that tag through `validate_locale/1`/likely-subtag resolution,
      # which maximized `und` back to a concrete locale id (e.g.
      # `:en`, `:aa`, or the originally-requested locale depending on
      # the environment). The upstream fix in `cldr_locale_id_from/1` maps
      # bare `und` directly to `:und`, but this guard remains as
      # defence-in-depth so any future resolver quirk cannot loop the
      # provider.
      cond do
        parent_id == locale_id ->
          Logger.debug(
            "Parent of #{inspect(locale_id)} resolved back to itself — stopping parent-chain walk.",
            domain: [:localize]
          )

          fallback_to_en(provider, original_locale_id)

        parent_id in visited ->
          Logger.debug(
            "Parent chain for #{inspect(original_locale_id)} revisited #{inspect(parent_id)} — stopping walk to avoid infinite recursion.",
            domain: [:localize]
          )

          fallback_to_en(provider, original_locale_id)

        true ->
          Logger.debug(
            "Attempting to load locale #{inspect(parent_id)} (parent locale of #{inspect(locale_id)}).",
            domain: [:localize]
          )

          case provider.load(parent_id) do
            {:ok, locale_data} ->
              Logger.debug(
                "Loaded and using locale #{inspect(parent_id)} (parent locale of #{inspect(locale_id)}) since #{inspect(original_locale_id)} is not available.",
                domain: [:localize]
              )

              {:ok, locale_data, parent_id}

            {:error, _} ->
              allow_download =
                Application.get_env(:localize, :allow_runtime_locale_download, false)

              Logger.debug(
                "Unable to load locale #{inspect(parent_id)} and :allow_runtime_locale_download is set to #{inspect(allow_download)}.",
                domain: [:localize]
              )

              walk_parent_chain(
                provider,
                parent_id,
                original_locale_id,
                [parent_id | visited]
              )
          end
      end
    else
      {:error, _} ->
        # Reached root (und) with no success — fall back to :en
        fallback_to_en(provider, original_locale_id)
    end
  end

  defp fallback_to_en(provider, original_locale_id) do
    require Logger

    Logger.debug(
      "Parent chain exhausted at #{inspect(original_locale_id)}, falling back to global default :en.",
      domain: [:localize]
    )

    case provider.load(:en) do
      {:ok, locale_data} ->
        Logger.debug(
          "Loaded and using locale :en (global default) since #{inspect(original_locale_id)} is not available.",
          domain: [:localize]
        )

        {:ok, locale_data, :en}

      {:error, _} = error ->
        error
    end
  end

  # Resolve a locale_id atom to its canonical CLDR form via
  # validate_locale. Non-canonical identifiers like :"pt-BR" (which
  # CLDR maps to :pt) are replaced with the canonical form. If
  # resolution fails, the original is returned unchanged — let the
  # caller surface the error via the normal not-found path.
  defp resolve_canonical_locale_id(locale_id) do
    case Localize.validate_locale(locale_id) do
      {:ok, %{cldr_locale_id: canonical}} when not is_nil(canonical) -> canonical
      _ -> locale_id
    end
  end

  @doc """
  Returns the directory in which downloaded locale data is cached.

  ## Configuration summary

  There are three supported configurations:

  1. **`:otp_app` only** (recommended) — caches in
     `Application.app_dir(<otp_app>, "priv/localize/locales")`.

         config :localize, otp_app: :my_app

  2. **`:otp_app` + relative `:locale_cache_dir`** — caches in
     `Application.app_dir(<otp_app>, <relative>)`. Use this when you
     want the app-resolved anchor but a non-default subpath.

         config :localize,
           otp_app: :my_app,
           locale_cache_dir: "priv/i18n/cache"

  3. **Absolute `:locale_cache_dir`** — used verbatim. `:otp_app`
     is ignored. Use for fully custom locations such as a shared
     mount or a fixed system path.

         config :localize, locale_cache_dir: "/var/lib/localize/locales"

  With neither key set, Localize falls back to
  `default_locale_cache_dir/0` (the bundled `:localize` package's
  `priv/localize/locales/`).

  ## Why `:otp_app` is recommended

  `Application.app_dir/2` is re-resolved on every read, so a single
  config value computes the correct path in every runtime phase:

  * Mix tasks land files in `_build/<env>/lib/<app>/priv/...`.

  * `mix test` reads from the same `_build` path.

  * Releases read from `/path/to/release/lib/<app>-X.Y.Z/priv/...`.

  No per-phase config duplication is required.

  ## Why a bare relative `:locale_cache_dir` is refused

  A relative `:locale_cache_dir` without `:otp_app` is **refused**
  and raises `Localize.LocaleCacheDirError` at app start (see
  `Localize.Supervisor`). A relative path with no anchor resolves
  against the BEAM's current working directory, which differs
  between mix tasks (project root), `mix test`, and a release
  (release root) — one value cannot be correct in all phases. Either
  pair the relative path with `:otp_app` (form 2 above) or use an
  absolute path (form 3).

  ### Returns

  * A string path to the locale cache directory.

  ### Examples

      iex> is_binary(Localize.Locale.Provider.locale_cache_dir())
      true

  """
  @spec locale_cache_dir() :: String.t()
  def locale_cache_dir do
    case Application.fetch_env(:localize, :locale_cache_dir) do
      {:ok, path} when is_binary(path) ->
        if absolute_path?(path) do
          # Form 3: absolute literal. `:otp_app` is ignored.
          path
        else
          # Relative `:locale_cache_dir`. Only valid when paired with
          # `:otp_app` — that supplies the anchor (form 2). Without an
          # anchor, refuse it (form 2 prerequisite missing).
          case configured_otp_app() do
            {:ok, otp_app} ->
              Application.app_dir(otp_app, path)

            :error ->
              raise Localize.LocaleCacheDirError,
                reason: :relative_path,
                value: path
          end
        end

      {:ok, other} ->
        raise Localize.LocaleCacheDirError,
          reason: :invalid_form,
          value: other

      :error ->
        # No explicit cache dir — fall back to :otp_app-derived path
        # at the conventional subpath, or the bundled :localize default
        # if no :otp_app is set.
        case configured_otp_app() do
          {:ok, otp_app} -> Application.app_dir(otp_app, "priv/localize/locales")
          :error -> default_locale_cache_dir()
        end
    end
  end

  # Reads `:otp_app` from the application environment. Returns
  # `{:ok, atom}` when set to a non-nil atom, `:error` when the key is
  # absent, or raises `Localize.LocaleCacheDirError` with reason
  # `:invalid_otp_app` when set to anything else. Used by both the
  # form-1 fallback (no `:locale_cache_dir`) and the form-2 anchor
  # (relative `:locale_cache_dir`).
  defp configured_otp_app do
    case Application.fetch_env(:localize, :otp_app) do
      {:ok, otp_app} when is_atom(otp_app) and not is_nil(otp_app) ->
        {:ok, otp_app}

      {:ok, other} ->
        raise Localize.LocaleCacheDirError,
          reason: :invalid_otp_app,
          value: other

      :error ->
        :error
    end
  end

  # `Path.type/1` returns `:absolute` for paths beginning with `/`
  # (POSIX) or a drive letter (Windows). `:relative` covers everything
  # else, including `"./foo"` and `"~/foo"` (Localize does not expand
  # `~` — that's a shell convention, not a path one).
  defp absolute_path?(path), do: Path.type(path) == :absolute

  @doc """
  Validates the `:locale_cache_dir` / `:otp_app` configuration and
  raises if it is malformed. Called once from
  `Localize.Supervisor.start_link/1` at app start so misconfiguration
  surfaces immediately rather than at the first locale lookup.

  Returns `:ok` for any valid configuration (including both keys
  unset).

  """
  @spec validate_locale_cache_dir!() :: :ok
  def validate_locale_cache_dir! do
    _ = locale_cache_dir()
    :ok
  end

  @doc """
  Returns the default directory in which downloaded locale data is cached.

  The default directory is located under the `:localize` application's
  `priv` directory at `localize/locales`.

  ### Returns

  * A string path to the default locale cache directory.

  ### Examples

      iex> String.ends_with?(Localize.Locale.Provider.default_locale_cache_dir(), "localize/locales")
      true

  """
  @spec default_locale_cache_dir() :: String.t()
  def default_locale_cache_dir do
    Application.app_dir(:localize, "priv/localize/locales")
  end

  @doc """
  Returns the base URL from which locale data files are downloaded.

  ### Returns

  * A string URL.

  ### Examples

      iex> Localize.Locale.Provider.base_url()
      "https://elixir-localize.com/locales"

  """
  @spec base_url() :: String.t()
  def base_url do
    "https://elixir-localize.com/locales"
  end

  @doc """
  Returns the file name for a locale's cached data file.

  ### Arguments

  * `locale_id` is a locale identifier atom.

  ### Returns

  * A string file name of the form `"{locale_id}.etf"`.

  ### Examples

      iex> Localize.Locale.Provider.locale_file_name(:en)
      "en.etf"

  """
  @spec locale_file_name(locale_id()) :: String.t()
  def locale_file_name(locale_id) when is_atom(locale_id) do
    "#{locale_id}.etf"
  end

  @doc """
  Returns the download URL for a given locale.

  The URL is versioned by the current `Localize.version/0` so
  that each Localize release downloads from its own path.

  ### Arguments

  * `locale_id` is a locale identifier atom.

  ### Returns

  * A string URL from which the locale's data file can be downloaded.

  ### Examples

      iex> url = Localize.Locale.Provider.locale_url(:en)
      iex> String.starts_with?(url, "https://elixir-localize.com/locales/")
      true
      iex> String.ends_with?(url, "/en.etf")
      true

  """
  @spec locale_url(locale_id()) :: String.t()
  def locale_url(locale_id) when is_atom(locale_id) do
    base_url() <> "/" <> version_segment() <> "/" <> locale_file_name(locale_id)
  end

  @doc """
  Returns the version segment used in cache paths and download URLs.

  ### Returns

  * A string of the form `"v{major}.{minor}.{patch}"` matching
    `Localize.version/0` with a `v` prefix.

  """
  @spec version_segment() :: String.t()
  def version_segment do
    "v" <> Version.to_string(Localize.version())
  end

  @doc """
  Downloads locale data for the given locale from `locale_url/1`.

  Uses Erlang's built-in `:httpc` to fetch the file. The downloaded
  content is returned as a binary and is not written to disk or
  decoded by this function.

  ### Arguments

  * `locale_id` is a locale identifier atom.

  ### Returns

  * `{:ok, binary}` with the raw downloaded file contents on success.

  * `{:error, exception}` if the locale could not be downloaded.

  """
  @spec download_locale(locale_id()) ::
          {:ok, binary()} | {:error, Exception.t()}
  def download_locale(locale_id) when is_atom(locale_id) do
    # Resolve to the canonical CLDR locale ID before constructing the
    # download URL. Non-canonical forms like :"pt-BR" (which CLDR maps
    # to :pt) would otherwise produce 404s because the CDN only hosts
    # files named after canonical locale IDs.
    locale_id = resolve_canonical_locale_id(locale_id)
    url = locale_url(locale_id)

    case Localize.Utils.Http.get(url) do
      {:ok, body} when is_binary(body) ->
        {:ok, body}

      {:not_modified, _headers} ->
        {:error,
         Localize.LocaleDownloadError.exception(
           locale_id: locale_id,
           url: url,
           reason: :not_modified
         )}

      {:error, reason} ->
        {:error,
         Localize.LocaleDownloadError.exception(
           locale_id: locale_id,
           url: url,
           cause: reason
         )}
    end
  end
end
