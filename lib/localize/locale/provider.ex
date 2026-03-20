defmodule Localize.Locale.Provider do
  @moduledoc """
  Defines the behaviour for locale data providers.

  A locale data provider is responsible for loading, storing, and
  retrieving CLDR locale data. Implementations may store data in
  any backing store such as `:persistent_term`, ETS, or the
  filesystem.

  In addition to the behaviour callbacks, this module provides
  helper functions for loading supplemental CLDR data files
  (likely subtags, aliases, validity data, etc.) from the
  `priv/cldr/` directory.

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

  # ── Supplemental data helpers ──────────────────────────────────

  defp cldr_dir do
    :localize
    |> :code.priv_dir()
    |> to_string()
    |> Path.join("cldr")
  end

  @doc """
  Returns the likely subtags data as a map.

  Each key is a string like `"en"` or `"und-Latn"` and each
  value is a map with `:language`, `:script`, and `:territory`
  keys.

  """
  @spec likely_subtags() :: %{String.t() => map()}
  def likely_subtags do
    load_data("likely_subtags.etf")
  end

  @doc """
  Returns the alias data as a map with keys `:language`,
  `:script`, `:region`, `:variant`, `:subdivision`, and `:zone`.

  """
  @spec aliases() :: map()
  def aliases do
    load_data("aliases.etf")
  end

  @doc """
  Returns the language matching data as a map with keys
  `:language_match`, `:match_variables`, and `:paradigm_locales`.

  """
  @spec language_matching() :: map()
  def language_matching do
    load_data("language_matching.etf")
  end

  @doc """
  Returns the list of all known locale identifier atoms.

  """
  @spec all_locale_ids() :: [atom()]
  def all_locale_ids do
    load_data("all_locale_names.etf")
  end

  @doc """
  Returns validity data for the given type.

  ### Arguments

  * `type` is one of `:languages`, `:scripts`, `:territories`,
    `:variants`, `:u`, or `:t`.

  ### Returns

  * A map of validity data for the given type.

  """
  @spec validity(atom()) :: map()
  def validity(:u), do: load_data("validity_u.etf")
  def validity(:t), do: load_data("validity_t.etf")
  def validity(:languages), do: load_data("validity_languages.etf")
  def validity(:scripts), do: load_data("validity_scripts.etf")
  def validity(:territories), do: load_data("validity_territories.etf")
  def validity(:variants), do: load_data("validity_variants.etf")
  def validity(:subdivisions), do: load_data("validity_subdivisions.etf")
  def validity(:units), do: load_data("validity_units.etf")

  @doc """
  Returns the parent locales data as a map.

  Each key is a locale identifier string (e.g., `"en-AU"`) and
  each value is the parent locale identifier string (e.g., `"en-001"`).
  These override the default subtag-stripping inheritance chain
  defined by CLDR supplemental data.

  """
  @spec parent_locales() :: %{String.t() => String.t()}
  def parent_locales do
    load_data("parent_locales.etf")
  end

  @doc """
  Returns the timezone data as a map.

  Each key is a BCP 47 timezone identifier string and each
  value is a map with `:preferred`, `:aliases`, and `:territory`
  keys.

  """
  @spec timezones() :: map()
  def timezones do
    load_data("timezones.etf")
  end

  @doc """
  Returns a mapping from Unicode script names to BCP 47
  script subtag atoms.

  """
  @spec unicode_script_to_subtag_mapping() :: map()
  def unicode_script_to_subtag_mapping do
    load_data("unicode_script_to_subtag_mapping.etf")
  end

  defp load_data(filename) do
    cldr_dir()
    |> Path.join(filename)
    |> File.read!()
    |> :erlang.binary_to_term()
  end
end
