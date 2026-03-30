defmodule Localize.Locale.Provider.PersistentTerm do
  @moduledoc """
  A locale data provider that stores locale data in `:persistent_term`.

  This provider loads CLDR locale data from `.etf` files in the
  `priv/localize/locales/` directory and caches it in `:persistent_term`
  for fast, concurrent access without copying.

  """

  @behaviour Localize.Locale.Provider

  @doc """
  Loads locale data for the given locale.

  Reads the locale's `.etf` file from `priv/localize/locales/`,
  decodes it, and stores the result in `:persistent_term`.

  ### Arguments

  * `locale` is a locale identifier atom or a `t:Localize.LanguageTag.t/0`.

  ### Returns

  * `{:ok, locale_data}` where `locale_data` is a map of the locale's
    CLDR data.

  * `{:error, Localize.UnknownLocaleError.t()}` if the locale data
    file cannot be found.

  """
  @env apply(Mix, :env, [])

  @impl Localize.Locale.Provider
  @dialyzer {:nowarn_function, load: 1}
  def load(locale) do
    locale_id = to_locale_id(locale)

    path =
      :localize
      |> :code.priv_dir()
      |> Path.join("localize/locales/#{locale_id}.etf")

    cond do
      File.exists?(path) ->
        locale_data =
          path
          |> File.read!()
          |> :erlang.binary_to_term()

        {:ok, locale_data}

      @env in [:test, :dev] ->
        locale_string = to_string(locale)
        locale_data = Localize.Data.Locale.generate_and_transform(locale_string)
        {:ok, locale_data}

      true ->
        {:error, Localize.UnknownLocaleError.exception(locale_id: locale_id)}
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
    locale_id = to_locale_id(locale)
    locale_key = locale_key(locale_id)
    !!:persistent_term.get(locale_key, nil)
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
    locale_id = to_locale_id(locale)
    locale_key = locale_key(locale_id)
    locale_data = :persistent_term.get(locale_key)

    if item = get_in(locale_data, keys) do
      {:ok, item}
    else
      {:error, Localize.ItemNotFoundError.exception(locale: locale_id, keys: keys)}
    end
  end

  # ── Helpers ──────────────────────────────────────────────────

  defp to_locale_id(locale) do
    Localize.Locale.to_locale_id(locale)
  end

  defp locale_key(locale_id) do
    {:localize, locale_id}
  end
end
