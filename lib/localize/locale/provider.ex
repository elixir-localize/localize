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
end
