defmodule Localize.Locale.Provider.PersistentTerm do
  @moduledoc """
  A locale data provider that stores locale data in `:persistent_term`.

  This provider loads CLDR locale data from `.etf` files in the
  `priv/localize/locales/` directory and caches it in `:persistent_term`
  for fast, concurrent access without copying.

  """

  @behaviour Localize.Locale.Provider

  alias Localize.Locale.Provider.Cache

  @env apply(Mix, :env, [])

  @doc """
  Loads locale data for the given locale.

  Locale data is resolved in the following order:

  1. If a fresh copy is present in the on-disk cache
     (see `Localize.Locale.Provider.Cache`), it is returned.

  2. In `:dev` and `:test` environments, the locale is generated
     from the CLDR source data via
     `Localize.Data.Locale.generate_and_transform/1`.

  3. Otherwise, the locale is downloaded via
     `Localize.Locale.Provider.download_locale/1`, written to the
     cache, decoded, and returned.

  ### Arguments

  * `locale` is a locale identifier atom or a `t:Localize.LanguageTag.t/0`.

  ### Returns

  * `{:ok, locale_data}` where `locale_data` is a map of the locale's
    CLDR data.

  * `{:error, exception}` if the locale data cannot be obtained.

  """
  @impl Localize.Locale.Provider
  @dialyzer {:nowarn_function, load: 1}
  def load(locale) do
    # `cldr_locale_id_from/1` validates and canonicalises non-CLDR forms
    # like `:"pt-BR"` (→ `:pt`), so the cache lookup and any
    # subsequent download/generation work directly on the canonical
    # id. `load_miss/2`'s second arg used to carry the raw input for
    # `to_string/1` reasons; with canonicalisation done upstream the
    # canonical id serves that role too.
    with {:ok, locale_id} <- cldr_locale_id_from(locale) do
      case Cache.get(locale_id) do
        {:ok, locale_data} -> {:ok, locale_data}
        {:error, _} -> load_miss(locale_id, locale_id)
      end
    end
  end

  if @env in [:dev, :test] do
    defp load_miss(_locale_id, locale) do
      locale_string = to_string(locale)
      locale_data = apply(Localize.Data.Locale, :generate_and_transform, [locale_string])
      {:ok, locale_data}
    end
  else
    defp load_miss(locale_id, _locale) do
      if Localize.Locale.Provider.allow_download?(__MODULE__) do
        case Localize.Locale.Provider.download_locale(locale_id) do
          {:ok, binary} ->
            _ = Cache.store(locale_id, binary)
            # Pass `[:safe]` to refuse atoms / funs / refs the BEAM
            # hasn't already interned. Downloaded ETF files are a
            # privileged trust source but a compromised CDN or MITM is
            # still possible; the safe flag closes that door.
            try do
              {:ok, :erlang.binary_to_term(binary, [:safe])}
            rescue
              ArgumentError ->
                {:error,
                 Localize.LocaleDownloadError.exception(
                   locale_id: locale_id,
                   url: Localize.Locale.Provider.locale_url(locale_id),
                   reason: "downloaded ETF failed safe decode"
                 )}
            end

          {:error, exception} ->
            {:error, exception}
        end
      else
        {:error,
         Localize.LocaleNotFoundInCacheError.exception(
           locale_id: locale_id,
           path: Cache.path(locale_id)
         )}
      end
    end
  end

  @doc """
  Stores locale data in `:persistent_term`.

  ### Arguments

  * `locale_id` is a locale identifier atom.

  * `locale_data` is a map of locale data to store.

  ### Returns

  * `:ok` on success.

  * `{:error, reason}` on failure.

  """
  @impl Localize.Locale.Provider
  def store(locale_id, locale_data) do
    locale_key = locale_key(locale_id)
    :ok = :persistent_term.put(locale_key, locale_data)
  end

  @doc """
  Returns whether locale data has been loaded into `:persistent_term`.

  ### Arguments

  * `locale` is a locale identifier atom or a `t:Localize.LanguageTag.t/0`.

  ### Returns

  * `true` if the locale data is stored in `:persistent_term`.

  * `false` otherwise.

  """
  @impl Localize.Locale.Provider
  def loaded?(locale) do
    case cldr_locale_id_from(locale) do
      {:ok, locale_id} -> !!:persistent_term.get(locale_key(locale_id), nil)
      {:error, _} -> false
    end
  end

  @doc """
  Retrieves a value from locale data stored in `:persistent_term`.

  Navigates the locale data map using the provided list of keys.
  When the `:fallback` option is `true` and the key path is not
  found, parent locales are searched according to the CLDR locale
  inheritance chain.

  ### Arguments

  * `locale` is a locale identifier atom or a `t:Localize.LanguageTag.t/0`.

  * `keys` is a list of keys to traverse in the locale data map.

  * `options` is a keyword list of options. The default is `[]`.

  ### Options

  * `:fallback` is a boolean. When `true`, parent locales are
    searched if the key path is not found in the requested locale.
    The default is `false`.

  ### Returns

  * `{:ok, value}` if the key path resolves to a value.

  * `{:error, reason}` if the key path cannot be resolved.

  """
  @impl Localize.Locale.Provider
  def get(locale, keys, _options \\ []) when is_list(keys) do
    with {:ok, locale_id} <- cldr_locale_id_from(locale) do
      case :persistent_term.get(locale_key(locale_id), :localize_locale_not_loaded) do
        :localize_locale_not_loaded ->
          {:error, Localize.ItemNotFoundError.exception(locale: locale_id, keys: keys)}

        locale_data ->
          case get_in(locale_data, keys) do
            nil -> {:error, Localize.ItemNotFoundError.exception(locale: locale_id, keys: keys)}
            item -> {:ok, item}
          end
      end
    end
  end

  # ── Helpers ──────────────────────────────────────────────────

  defp cldr_locale_id_from(locale) do
    Localize.Locale.cldr_locale_id_from(locale)
  end

  defp locale_key(locale_id) do
    {:localize, locale_id}
  end
end
