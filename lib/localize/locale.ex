defmodule Localize.Locale do
  @moduledoc """
  Locale utility functions for resolution, validation, and
  per-locale data access.

  ## Locale data

  Per-locale CLDR data (number formats, calendar patterns,
  territory names, etc.) is loaded on demand via a configurable
  data provider and cached in `:persistent_term`. The default
  provider is `Localize.Locale.Provider.PersistentTerm`.

  * `load/2` — loads raw locale data from the provider.

  * `get/2` — retrieves a specific data key for a locale.

  ## Locale resolution

  * `parent/1` — returns the CLDR parent locale (e.g.,
    `:"en-AU"` → `:en`, `:en` → `:und`).

  * `cldr_locale_id_from/1` — resolves a language tag, atom, or string
    to its canonical CLDR locale identifier atom, returning an error
    for inputs that are not valid CLDR locales.

  * `gettext_locale_id/2` — finds the best matching locale among
    a Gettext backend's known locales.

  """

  alias Localize.LanguageTag
  alias Localize.Locale.Provider
  alias Localize.SupplementalData

  @typedoc "A BCP 47 language subtag as an atom."
  @type language :: atom() | nil

  @typedoc "A BCP 47 script subtag as an atom."
  @type script :: atom() | nil

  @typedoc "A BCP 47 region/territory subtag as an atom."
  @type territory :: atom() | nil

  @typedoc "A locale identifier as an atom."
  @type locale_id :: atom()

  # ── Display names ────────────────────────────────────────────

  @doc """
  Returns the localized display name for a locale identifier.

  Formats a locale identifier or language tag into a
  human-readable display name using the CLDR locale display
  name algorithm (e.g., `"en-AU"` → `"English (Australia)"`).

  ### Arguments

  * `locale` is a locale identifier string, atom, or a
    `t:Localize.LanguageTag.t/0`.

  * `options` is a keyword list of options.

  ### Options

  * `:locale` is the locale to use for formatting. The default
    is `Localize.get_locale()`.

  * `:prefer` is `:standard` or `:short`. The default is
    `:standard`.

  ### Returns

  * `{:ok, name}` where `name` is the localized display name.

  * `{:error, exception}` if the locale cannot be resolved.

  ### Examples

      iex> Localize.Locale.display_name("en-AU")
      {:ok, "English (Australia)"}

      iex> Localize.Locale.display_name("zh-Hant")
      {:ok, "Chinese (Traditional)"}

  """
  @spec display_name(LanguageTag.t() | String.t() | atom(), Keyword.t()) ::
          {:ok, String.t()} | {:error, Exception.t()}
  defdelegate display_name(locale, options \\ []), to: Localize.Locale.LocaleDisplay

  @doc """
  Same as `display_name/2` but raises on error.

  ### Arguments

  * `locale` is a locale identifier string, atom, or a
    `t:Localize.LanguageTag.t/0`.

  * `options` is a keyword list of options.

  ### Options

  * See `display_name/2` for the supported options.

  ### Returns

  * The localized display name as a string.

  * Raises an exception if the locale cannot be resolved.

  ### Examples

      iex> Localize.Locale.display_name!("en-AU")
      "English (Australia)"

  """
  @spec display_name!(LanguageTag.t() | String.t() | atom(), Keyword.t()) :: String.t()
  defdelegate display_name!(locale, options \\ []), to: Localize.Locale.LocaleDisplay

  # ── Locale inheritance ────────────────────────────────────────

  @doc """
  Return the parent locale of the given language tag.

  Implements the CLDR locale ID inheritance algorithm (bundle
  inheritance) from
  [Unicode TR35](https://www.unicode.org/reports/tr35/tr35.html#Locale_Inheritance).
  The parent locale is determined by first checking the CLDR
  `parentLocales` supplemental data for an explicit override,
  then falling back to progressive subtag removal.

  Extensions (`-u-` and `-t-`) are transferred from the child
  to the parent so that calendar, numbering system, and other
  preferences are preserved across the inheritance chain.

  ### Arguments

  * `locale` is a `%Localize.LanguageTag{}` struct or a BCP 47
    locale identifier string.

  ### Returns

  * `{:ok, parent_tag}` where `parent_tag` is a
    `%Localize.LanguageTag{}` struct representing the parent locale.

  * `{:error, Localize.NoParentError.exception(locale: locale)}` if the locale
    is the root locale (`und`) which has no parent.

  ### Examples

      iex> {:ok, parent} = Localize.Locale.parent("en-AU")
      iex> parent.language
      :en
      iex> parent.territory
      :"001"

      iex> {:ok, parent} = Localize.Locale.parent("en")
      iex> parent.language
      :und

  """
  @spec parent(LanguageTag.t() | String.t()) ::
          {:ok, LanguageTag.t()} | {:error, Exception.t()}
  def parent(
        %LanguageTag{language: :und, script: nil, territory: nil, language_variants: []} = _tag
      ) do
    {:error, Localize.NoParentError.exception(locale: "und")}
  end

  def parent(%LanguageTag{} = tag) do
    parent_tag =
      case lookup_parent_locale(tag) do
        nil ->
          find_parent(tag)

        parent_id ->
          {:ok, parsed} = LanguageTag.parse(parent_id)
          {:ok, canonical} = LanguageTag.canonicalize(parsed)
          canonical
      end

    parent_tag = transfer_extensions(parent_tag, tag)
    {:ok, parent_tag}
  end

  def parent(locale_id) when is_binary(locale_id) do
    with {:ok, parsed} <- LanguageTag.parse(locale_id),
         {:ok, canonical} <- LanguageTag.canonicalize(parsed) do
      parent(canonical)
    end
  end

  @doc """
  Return the parent locale of the given language tag, or raise.

  Same as `parent/1` but returns the parent `t:Localize.LanguageTag.t/0`
  directly on success or raises the error exception on failure.

  ### Arguments

  * `locale` is a `%Localize.LanguageTag{}` struct or a BCP 47
    locale identifier string.

  ### Returns

  * A `%Localize.LanguageTag{}` representing the parent locale.

  ### Examples

      iex> parent = Localize.Locale.parent!("en-AU")
      iex> parent.language
      :en

  """
  @spec parent!(LanguageTag.t() | String.t()) :: LanguageTag.t() | no_return()
  def parent!(locale) do
    case parent(locale) do
      {:ok, tag} -> tag
      {:error, exception} -> raise exception
    end
  end

  # Look up a parent locale in the parent_locales map.
  # The map uses minimal keys (e.g., "en-AU" not "en-Latn-AU"),
  # so we also try without the script since maximized tags include
  # the likely script which is usually omitted in the map keys.
  # We only check forms with the SAME specificity — we don't
  # drop territory or variants here (that's find_parent's job).
  defp lookup_parent_locale(%LanguageTag{} = tag) do
    full_key =
      locale_id_from(tag.language, tag.script, tag.territory, tag.language_variants)

    parent_locales = SupplementalData.parent_locales()

    case Map.get(parent_locales, full_key) do
      nil ->
        # Try without script (handles maximized tags like en-Latn-AU → en-AU)
        no_script_key =
          locale_id_from(tag.language, nil, tag.territory, tag.language_variants)

        Map.get(parent_locales, no_script_key)

      result ->
        result
    end
  end

  # Progressively strip subtags to find the parent.
  # Order: drop variants → drop territory → drop script → und (root).
  defp find_parent(%LanguageTag{language_variants: [_ | _]} = tag) do
    %{tag | language_variants: [], canonical_locale_id: nil}
  end

  defp find_parent(%LanguageTag{territory: territory} = tag) when not is_nil(territory) do
    %{tag | territory: nil, canonical_locale_id: nil}
  end

  defp find_parent(%LanguageTag{script: script} = tag) when not is_nil(script) do
    %{tag | script: nil, canonical_locale_id: nil}
  end

  defp find_parent(%LanguageTag{} = _tag) do
    {:ok, parsed} = LanguageTag.parse("und")
    {:ok, canonical} = LanguageTag.canonicalize(parsed)
    canonical
  end

  # Transfer extensions from child to parent so that preferences like
  # calendar, numbering system, etc. are preserved.
  defp transfer_extensions(%LanguageTag{} = parent, %LanguageTag{} = child) do
    updated = %{
      parent
      | locale: child.locale,
        transform: child.transform,
        canonical_locale_id: nil
    }

    canonical_id = LanguageTag.to_string(updated)
    %{updated | canonical_locale_id: canonical_id}
  end

  # ── Utility functions ─────────────────────────────────────────

  @doc """
  Convert a POSIX locale identifier to a BCP 47 locale identifier
  by replacing underscores with hyphens.

  ### Arguments

  * `locale_id` is a string locale identifier, potentially
    in POSIX format using underscores.

  ### Returns

  * A string with underscores replaced by hyphens.

  ### Examples

      iex> Localize.Locale.locale_id_from_posix("en_US")
      "en-US"

      iex> Localize.Locale.locale_id_from_posix("zh_Hant_TW")
      "zh-Hant-TW"

      iex> Localize.Locale.locale_id_from_posix("en")
      "en"

  """
  @spec locale_id_from_posix(String.t()) :: String.t()
  def locale_id_from_posix(locale_id) when is_binary(locale_id) do
    String.replace(locale_id, "_", "-")
  end

  @doc """
  Build a locale identifier string from its component parts.

  Assembles a BCP 47 locale identifier from language, script,
  territory, and variant subtags, omitting nil components.

  ### Arguments

  * `language` is a language subtag (string or atom).

  * `script` is an optional script subtag (string, atom, or nil).

  * `territory` is an optional territory subtag (string, atom, or nil).

  * `variants` is a list of variant subtag strings.

  ### Returns

  * A BCP 47 locale identifier string.

  ### Examples

      iex> Localize.Locale.locale_id_from(:en, nil, :US, [])
      "en-US"

      iex> Localize.Locale.locale_id_from(:zh, :Hant, :TW, [])
      "zh-Hant-TW"

      iex> Localize.Locale.locale_id_from(:en, nil, nil, [])
      "en"

  """
  @spec locale_id_from(language(), script(), territory(), [String.t()]) :: String.t()
  def locale_id_from(language, script, territory, variants) do
    [to_string(language)]
    |> maybe_append(script)
    |> maybe_append(territory)
    |> append_variants(variants)
    |> Enum.join("-")
  end

  defp maybe_append(parts, nil), do: parts
  defp maybe_append(parts, value), do: parts ++ [to_string(value)]

  defp append_variants(parts, []), do: parts
  defp append_variants(parts, variants), do: parts ++ Enum.map(variants, &to_string/1)

  # ── Provider API ───────────────────────────────────────────────

  @doc """
  Returns the default locale data provider module.

  ### Returns

  * The module implementing `Localize.Locale.Provider`.

  ### Examples

      iex> Localize.Locale.default_provider()
      Localize.Locale.Provider.PersistentTerm

  """
  @spec default_provider() :: module()
  def default_provider do
    Application.get_env(:localize, :locale_provider, Localize.Locale.Provider.PersistentTerm)
  end

  @doc """
  Loads locale data for the given locale.

  Delegates to the configured provider module to find and retrieve
  locale data.

  ### Arguments

  * `locale` is a locale identifier atom or a `t:Localize.LanguageTag.t/0`.

  * `options` is a keyword list of options. The default is `[]`.

  ### Options

  * `:provider` is the module implementing `Localize.Locale.Provider`
    to use. The default is `default_provider/0`.

  ### Returns

  * `{:ok, locale_data}` where `locale_data` is a map of the locale's
    CLDR data.

  * `{:error, Localize.UnknownLocaleError.t()}` if the locale is not
    recognized.

  ### Examples

      iex> {:ok, locale_data} = Localize.Locale.load(:en)
      iex> is_map(locale_data)
      true

  """
  @spec load(Provider.locale(), Keyword.t()) ::
          {:ok, map()} | {:error, Exception.t()}
  def load(locale, options \\ []) do
    {provider, _options} = Keyword.pop(options, :provider, default_provider())
    provider.load(locale)
  end

  @doc """
  Stores locale data in the provider's backing store.

  Delegates to the configured provider module to persist locale data.

  ### Arguments

  * `locale_id` is a locale identifier atom.

  * `locale_data` is a map of locale data to store.

  * `options` is a keyword list of options. The default is `[]`.

  ### Options

  * `:provider` is the module implementing `Localize.Locale.Provider`
    to use. The default is `default_provider/0`.

  ### Returns

  * `:ok` on success.

  * `{:error, reason}` on failure.

  ### Examples

      iex> {:ok, locale_data} = Localize.Locale.load(:en)
      iex> Localize.Locale.store(:en, locale_data)
      :ok

  """
  @spec store(locale_id(), map(), Keyword.t()) ::
          :ok | {:error, term()}
  def store(locale_id, locale_data, options \\ []) do
    {provider, _options} = Keyword.pop(options, :provider, default_provider())
    provider.store(locale_id, locale_data)
  end

  @doc """
  Loads and stores locale data if it has not already been loaded.

  This is a convenience function that checks whether the locale
  data is already available and, if not, delegates to the configured
  provider to load and store it. Subsequent calls for the same
  locale are no-ops.

  ### Arguments

  * `locale` is a locale identifier atom or a `t:Localize.LanguageTag.t/0`.

  * `options` is a keyword list of options. The default is `[]`.

  ### Options

  * `:provider` is the module implementing `Localize.Locale.Provider`
    to use. The default is `default_provider/0`.

  ### Returns

  * `:ok` if the locale data is already loaded or was successfully
    loaded and stored.

  * `{:error, Localize.UnknownLocaleError.t()}` if the locale data
    could not be loaded.

  ### Examples

      iex> Localize.Locale.load_and_store(:en)
      :ok

  """
  @spec load_and_store(Provider.locale(), Keyword.t()) ::
          :ok | {:error, Exception.t()}
  def load_and_store(locale, options \\ []) do
    Localize.Locale.Loader.load_and_store(locale, options)
  end

  @doc """
  Returns whether locale data has been loaded and is available.

  Delegates to the configured provider module to check availability.

  ### Arguments

  * `locale` is a locale identifier atom or a `t:Localize.LanguageTag.t/0`.

  * `options` is a keyword list of options. The default is `[]`.

  ### Options

  * `:provider` is the module implementing `Localize.Locale.Provider`
    to use. The default is `default_provider/0`.

  ### Returns

  * `true` if the locale data has been loaded and stored.

  * `false` otherwise.

  ### Examples

      iex> Localize.Locale.load_and_store(:en)
      :ok
      iex> Localize.Locale.loaded?(:en)
      true

  """
  @spec loaded?(Provider.locale(), Keyword.t()) :: boolean()
  def loaded?(locale, options \\ []) do
    {provider, _options} = Keyword.pop(options, :provider, default_provider())
    provider.loaded?(locale)
  end

  @doc """
  Retrieves a value from locale data by following a list of access keys.

  Delegates to the configured provider module to navigate the locale
  data map.

  ### Arguments

  * `locale` is a locale identifier atom or a `t:Localize.LanguageTag.t/0`.

  * `keys` is a list of keys to traverse in the locale data map.

  * `options` is a keyword list of options. The default is `[]`.

  ### Options

  * `:provider` is the module implementing `Localize.Locale.Provider`
    to use. The default is `default_provider/0`.

  * `:fallback` is a boolean. When `true`, if the requested key path
    is not found in the given locale, parent locales are searched
    according to the CLDR locale inheritance chain. The default is
    `false`.

  * `:fallback_to_default` controls a final-step fallback after any
    `:fallback` parent walk. Accepts:

    * `false` (the default) — disabled.

    * `true` — use the application default locale
      (`Localize.default_locale/0`).

    * an atom, string, or `t:Localize.LanguageTag.t/0` — use that
      specific locale. The value is resolved through
      `Localize.validate_locale/1`; an invalid value returns
      `{:error, exception}` immediately.

    Composes with `:fallback` — set both to walk parents and then
    try the chosen locale.

  ### Returns

  * `{:ok, value}` if the key path resolves to a value.

  * `{:error, reason}` if the key path cannot be resolved.

  ### Examples

      iex> {:ok, names} = Localize.Locale.get(:en, [:locale_display_names])
      iex> is_map(names)
      true

      iex> Localize.Locale.get(:en, [:delimiters, :quotation_start, :default])
      {:ok, "“"}

  """
  @spec get(Provider.locale(), list(), Keyword.t()) ::
          {:ok, term()} | {:error, term()}
  def get(locale, keys, options \\ []) do
    {provider, options} = Keyword.pop(options, :provider, default_provider())
    {fallback?, options} = Keyword.pop(options, :fallback, false)
    {fallback_to_default, options} = Keyword.pop(options, :fallback_to_default, false)

    with {:ok, default_fallback_id} <- resolve_default_fallback(fallback_to_default),
         :ok <- load_and_store(locale, provider: provider) do
      case provider.get(locale, keys, options) do
        # Hot path: a successful lookup returns directly, paying no
        # cost for the fallback dispatch.
        {:ok, _} = ok ->
          ok

        {:error, _} = error ->
          try_fallbacks(error, locale, keys, provider, options, fallback?, default_fallback_id)
      end
    end
  end

  @doc """
  Retrieves a value from locale data, raising on error.

  Same as `get/3` but returns the value directly on success or raises
  the error exception on failure.

  ### Arguments

  * `locale` is a locale identifier atom or a `t:Localize.LanguageTag.t/0`.

  * `keys` is a list of keys to traverse in the locale data map.

  * `options` is a keyword list of options. See `get/3` for supported
    options.

  ### Options

  * See `get/3` for the supported options.

  ### Returns

  * The value at the requested key path.

  ### Examples

      iex> Localize.Locale.get!(:en, [:delimiters, :quotation_start, :default])
      "“"

  """
  @spec get!(Provider.locale(), list(), Keyword.t()) :: term() | no_return()
  def get!(locale, keys, options \\ []) do
    case get(locale, keys, options) do
      {:ok, value} ->
        value

      {:error, %_{} = exception} ->
        raise exception

      {:error, other} ->
        raise ArgumentError, inspect(other)
    end
  end

  # Dispatch table for the `:fallback` and `:fallback_to_default`
  # option combinations. The clause heads encode the policy so the
  # bodies stay one or two lines each; the hot success path in `get/3`
  # never reaches this function.

  # Parent-chain walk requested. Walk, then maybe try the default
  # locale if the walk also misses.
  defp try_fallbacks(
         {:error, %Localize.ItemNotFoundError{}},
         locale,
         keys,
         provider,
         options,
         true,
         default_fallback_id
       ) do
    locale
    |> fallback_through_parents(keys, provider, options)
    |> maybe_fallback_to_default(locale, default_fallback_id, keys, provider, options)
  end

  # No parent walk, but `:fallback_to_default` is set — try the
  # default locale directly.
  defp try_fallbacks(
         {:error, %Localize.ItemNotFoundError{}},
         locale,
         keys,
         provider,
         options,
         false,
         default_fallback_id
       )
       when not is_nil(default_fallback_id) do
    try_default_locale(locale, default_fallback_id, keys, provider, options)
  end

  # Either a non-`ItemNotFoundError` (load failure, etc.) or
  # `ItemNotFoundError` with no fallback options enabled — propagate
  # the error unchanged.
  defp try_fallbacks({:error, _} = error, _locale, _keys, _provider, _options, _fb, _df_id),
    do: error

  # Final step after a parent-chain walk: only try the default locale
  # when the walk produced a not-found AND a default-fallback id is
  # set. Any other walk outcome (success, load error) propagates.
  defp maybe_fallback_to_default(
         {:error, %Localize.ItemNotFoundError{}},
         locale,
         default_fallback_id,
         keys,
         provider,
         options
       )
       when not is_nil(default_fallback_id) do
    try_default_locale(locale, default_fallback_id, keys, provider, options)
  end

  defp maybe_fallback_to_default(result, _locale, _df_id, _keys, _provider, _options),
    do: result

  # Resolve the `:fallback_to_default` option to a locale id atom (or
  # nil when the option is disabled). Strings and atoms are run through
  # `Localize.validate_locale/1`, which performs no provider key-path
  # lookups, so this cannot recurse back into `get/3`.
  @spec resolve_default_fallback(boolean() | atom() | String.t() | Localize.LanguageTag.t()) ::
          {:ok, atom() | nil} | {:error, Exception.t()}
  defp resolve_default_fallback(false), do: {:ok, nil}
  defp resolve_default_fallback(true), do: cldr_locale_id_from(Localize.default_locale())

  defp resolve_default_fallback(locale) do
    with {:ok, tag} <- Localize.validate_locale(locale) do
      cldr_locale_id_from(tag)
    end
  end

  # Try the resolved fallback locale as a final step. Returns an
  # ItemNotFoundError referencing the *original* locale so callers see a
  # consistent error identity regardless of which locale was actually
  # visited last. Load errors against the fallback locale propagate.
  @spec try_default_locale(Provider.locale(), atom(), list(), module(), Keyword.t()) ::
          {:ok, term()} | {:error, term()}
  defp try_default_locale(original_locale, fallback_id, keys, provider, options) do
    with {:ok, original_id} <- cldr_locale_id_from(original_locale) do
      if fallback_id == original_id do
        {:error, Localize.ItemNotFoundError.exception(locale: original_id, keys: keys)}
      else
        get_from_default_locale(fallback_id, original_id, keys, provider, options)
      end
    end
  end

  # Load the fallback locale and read `keys` from it, rewriting any
  # not-found error to reference the originally requested locale.
  @spec get_from_default_locale(atom(), atom(), list(), module(), Keyword.t()) ::
          {:ok, term()} | {:error, term()}
  defp get_from_default_locale(fallback_id, original_id, keys, provider, options) do
    with :ok <- load_and_store(fallback_id, provider: provider) do
      default_locale_result(provider.get(fallback_id, keys, options), original_id, keys)
    end
  end

  defp default_locale_result({:ok, _} = ok, _original_id, _keys), do: ok

  defp default_locale_result({:error, %Localize.ItemNotFoundError{}}, original_id, keys) do
    {:error, Localize.ItemNotFoundError.exception(locale: original_id, keys: keys)}
  end

  defp default_locale_result({:error, _} = error, _original_id, _keys), do: error

  # Walk the CLDR parent locale chain looking for `keys`. Each parent
  # is loaded through the same provider before being read. The
  # not-found error returned at the end of the chain references the
  # originally requested locale, not the deepest parent walked.
  #
  # Cycle protection is belt-and-braces: `parent/1` terminates at
  # `und` with `{:error, NoParentError}` so a normal walk always
  # ends, but the visited set guards against any future inheritance
  # graph that could close into a loop.
  @spec fallback_through_parents(Provider.locale(), list(), module(), Keyword.t()) ::
          {:ok, term()} | {:error, term()}
  defp fallback_through_parents(original_locale, keys, provider, options) do
    with {:ok, original_id} <- cldr_locale_id_from(original_locale) do
      walk_parents(original_id, original_id, keys, provider, options, [original_id])
    end
  end

  # `visited` is a small list (the depth of the CLDR locale
  # inheritance graph is typically 2–4) used to guard against any
  # future inheritance cycle. We use a list rather than a `MapSet`
  # so the type flows cleanly through the recursion under Elixir
  # 1.20's stricter opacity checks.
  @spec walk_parents(atom(), atom(), list(), module(), Keyword.t(), [atom(), ...]) ::
          {:ok, term()} | {:error, term()}
  defp walk_parents(original_id, current_id, keys, provider, options, visited) do
    case next_parent(current_id, visited) do
      {:ok, parent_id} ->
        case load_and_store(parent_id, provider: provider) do
          :ok ->
            get_or_next_parent(original_id, parent_id, keys, provider, options, visited)

          {:error, _} = error ->
            error
        end

      :no_parent ->
        {:error, Localize.ItemNotFoundError.exception(locale: original_id, keys: keys)}
    end
  end

  defp get_or_next_parent(original_id, parent_id, keys, provider, options, visited) do
    case provider.get(parent_id, keys, options) do
      {:ok, _} = ok ->
        ok

      {:error, %Localize.ItemNotFoundError{}} ->
        walk_parents(
          original_id,
          parent_id,
          keys,
          provider,
          options,
          [parent_id | visited]
        )

      {:error, _} = error ->
        error
    end
  end

  @spec next_parent(atom(), [atom(), ...]) :: {:ok, atom()} | :no_parent
  defp next_parent(locale_id, visited) do
    with {:ok, parent_tag} <- parent(to_string(locale_id)),
         {:ok, parent_id} <- cldr_locale_id_from(parent_tag) do
      if parent_id in visited do
        :no_parent
      else
        {:ok, parent_id}
      end
    else
      _ -> :no_parent
    end
  end

  # ── CLDR Locale ID resolution ────────────────────────────────────────

  @doc """
  Resolves any locale input to its canonical CLDR locale id atom.

  A `locale_id` is by definition a valid CLDR locale, so any input
  that cannot be resolved via `Localize.validate_locale/1` is
  returned as an error rather than coerced to a fresh atom. This
  is the boundary that bounds atom-table growth from untrusted
  locale inputs.

  Pre-validated `t:Localize.LanguageTag.t/0` structs — those whose
  `:cldr_locale_id` is already populated — take a fast path that
  skips re-validation. Everything else routes through
  `Localize.validate_locale/1`.

  ### Arguments

  * `locale` is a locale identifier atom, string, or
    `t:Localize.LanguageTag.t/0`.

  ### Returns

  * `{:ok, locale_id}` where `locale_id` is the canonical CLDR
    locale id atom.

  * `{:error, exception}` if the locale cannot be validated.

  ### Examples

      iex> Localize.Locale.cldr_locale_id_from(:en)
      {:ok, :en}

      iex> Localize.Locale.cldr_locale_id_from("en-AU")
      {:ok, :"en-AU"}

      iex> {:ok, parsed} = Localize.LanguageTag.parse("fr")
      iex> Localize.Locale.cldr_locale_id_from(parsed)
      {:ok, :fr}

  """
  @spec cldr_locale_id_from(LanguageTag.t() | atom() | String.t() | term()) ::
          {:ok, atom()} | {:error, Exception.t()}
  def cldr_locale_id_from(%LanguageTag{cldr_locale_id: locale_id})
      when not is_nil(locale_id) do
    {:ok, locale_id}
  end

  # A root tag (`und` with no script/territory/variants) maps to `:und`
  # unconditionally. Running it through likely-subtag resolution via
  # `validate_locale/1` would maximize it back to e.g. `en-Latn-US` or,
  # if the tag carries `-u-` extensions copied from a child during
  # parent-chain walking, to whichever locale the extensions bias it
  # toward — creating a cycle where the parent chain never terminates.
  def cldr_locale_id_from(%LanguageTag{
        language: :und,
        script: nil,
        territory: nil,
        language_variants: []
      }) do
    {:ok, :und}
  end

  # Same reasoning for the bare `:und` atom (the CLDR root locale id).
  # Don't run it through `validate_locale/1` which would maximize it.
  def cldr_locale_id_from(:und), do: {:ok, :und}

  def cldr_locale_id_from(input) do
    case Localize.validate_locale(input) do
      {:ok, %LanguageTag{cldr_locale_id: resolved}} when not is_nil(resolved) ->
        {:ok, resolved}

      {:ok, %LanguageTag{}} ->
        {:error, Localize.InvalidLocaleError.exception(locale_id: inspect(input))}

      {:error, _} = error ->
        error
    end
  end

  # ── Gettext integration ────────────────────────────────────────

  @doc """
  Returns the best-matching Gettext locale for a given locale
  identifier.

  Compares the given locale against the locales known to a Gettext
  backend using `Localize.LanguageTag.best_match/3`. This allows
  a CLDR locale like `:"en-AU"` to match a Gettext locale like
  `"en"` when no exact match exists.

  ### Arguments

  * `locale` is a locale identifier atom, string, or a
    `t:Localize.LanguageTag.t/0`.

  * `gettext_backend` is a module that uses `Gettext` (e.g.,
    `MyApp.Gettext`). It must respond to
    `Gettext.known_locales/1`.

  ### Returns

  * `{:ok, gettext_locale}` where `gettext_locale` is a string
    from the Gettext backend's known locales.

  * `{:error, exception}` if no match is found among the
    backend's known locales.

  ### Examples

      iex> Localize.Locale.gettext_locale_id(:en, Localize.Gettext)
      {:error,
       %Localize.UnknownLocaleError{
         locale_id: "en"
       }}

  """
  @spec gettext_locale_id(LanguageTag.t() | atom() | String.t(), module()) ::
          {:ok, String.t()} | {:error, Exception.t()}
  def gettext_locale_id(locale, gettext_backend) when is_atom(gettext_backend) do
    known = Gettext.known_locales(gettext_backend)

    locale_string =
      case locale do
        %LanguageTag{} -> LanguageTag.to_string(locale)
        atom when is_atom(atom) -> Atom.to_string(atom)
        binary when is_binary(binary) -> binary
      end

    case LanguageTag.best_match(locale_string, known) do
      {:ok, matched_locale, _score} ->
        {:ok, matched_locale}

      {:error, _} ->
        {:error, Localize.UnknownLocaleError.exception(locale_id: locale_string)}
    end
  end

  @doc """
  Expands a list of locale identifiers into a list of known CLDR
  locale ID atoms.

  Each entry can be:

  * A **CLDR locale ID atom** like `:en`, `:"fr-CA"`.

  * A **coverage-level keyword** — `:basic`, `:moderate`, or
    `:modern` — that expands to all locales at or above that
    level.

  * A **Gettext backend module** (a module that has called
    `use Gettext.Backend` or `use Gettext, otp_app: ...`) which
    expands to the backend's `Gettext.known_locales/1`. Each
    returned string is re-expanded as a locale ID, so POSIX-style
    names like `"pt_BR"` resolve to `:"pt-BR"`.

  * A **string locale ID** like `"en"`, `"pt_BR"`, or
    `"zh_Hans"`. POSIX underscores are normalised to hyphens, then
    the string is matched against the CLDR set via likely-subtag
    resolution.

  * A **wildcard string** like `"en-*"` that expands to all
    matching CLDR locales.

  Invalid entries log a warning and are skipped.

  ### Arguments

  * `entries` is a list of atoms (locale IDs, coverage keywords,
    or Gettext backend modules) and/or strings (locale IDs or
    wildcards).

  * `context` is an atom or string used in warning messages to
    identify where the entry came from (e.g. `:supported_locales`).

  ### Returns

  * A deduplicated list of locale ID atoms.

  ### Examples

      iex> Localize.Locale.expand_locale_list([:en, :"fr-CA"])
      [:en, :"fr-CA"]

      iex> Localize.Locale.expand_locale_list(["en_AU"])
      [:"en-AU"]

  """
  @coverage_levels [:basic, :moderate, :modern]

  @spec expand_locale_list([atom() | String.t()], atom() | String.t()) :: [atom()]
  def expand_locale_list(entries, context \\ :locales) when is_list(entries) do
    all_ids = Localize.SupplementalData.all_locale_ids()
    all_strings = MapSet.new(all_ids, &Atom.to_string/1)

    entries
    |> Enum.flat_map(fn entry -> expand_locale_entry(entry, all_ids, all_strings, context) end)
    |> Enum.uniq()
  end

  # Coverage-level keywords expand to all locales at or above that level.
  defp expand_locale_entry(level, _all_ids, _all_strings, _context)
       when level in @coverage_levels do
    Localize.all_locale_ids(level)
  end

  defp expand_locale_entry(entry, all_ids, all_strings, context) when is_atom(entry) do
    cond do
      entry in all_ids ->
        [entry]

      gettext_backend?(entry) ->
        entry
        |> Gettext.known_locales()
        |> Enum.flat_map(&expand_locale_entry(&1, all_ids, all_strings, context))

      true ->
        require Logger

        Logger.warning(
          "Ignoring unknown locale #{inspect(entry)} in #{inspect(context)} " <>
            "configuration. Not a known CLDR locale, coverage-level keyword, " <>
            "or Gettext backend module.",
          domain: [:localize]
        )

        []
    end
  end

  defp expand_locale_entry(entry, all_ids, _all_strings, context) when is_binary(entry) do
    # Normalize POSIX-style locale IDs (e.g. "pt_BR" → "pt-BR")
    # so that Gettext locale names work directly.
    normalized = String.replace(entry, "_", "-")

    if String.ends_with?(normalized, "*") do
      prefix = String.trim_trailing(normalized, "*")

      Enum.filter(all_ids, fn id ->
        id |> Atom.to_string() |> String.starts_with?(prefix)
      end)
    else
      # Use best_match with threshold 0: only accepts exact
      # matches (score 0) after likely-subtag resolution. This
      # maps Gettext locale names like "pt_BR" → :pt and
      # "zh_Hans" → :zh, while rejecting junk strings like
      # "not_a_locale" that have no score-0 match.
      case Localize.LanguageTag.best_match(normalized, all_ids, 0) do
        {:ok, cldr_id, 0} ->
          [cldr_id]

        _no_match ->
          warn_unknown_locale(entry, context)
          []
      end
    end
  end

  defp warn_unknown_locale(entry, context) do
    require Logger

    Logger.warning(
      "Ignoring unknown locale #{inspect(entry)} in #{inspect(context)} configuration. " <>
        "Could not be resolved to a known CLDR locale.",
      domain: [:localize]
    )
  end

  # `Code.ensure_compiled/1` (not `Code.ensure_loaded/1`) so this is
  # safe to call from either compile-time contexts (where the host
  # app's `MyApp.Gettext` may not yet exist as a BEAM file) or runtime
  # contexts (where the module exists but may not yet be loaded).
  # Returns `false` for unavailable modules so an unresolvable backend
  # entry falls through to the existing `warn_unknown_locale` path.
  defp gettext_backend?(module) when is_atom(module) do
    case Code.ensure_compiled(module) do
      {:module, _} -> function_exported?(module, :__gettext__, 1)
      {:error, _} -> false
    end
  end
end
