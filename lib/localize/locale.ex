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

  * `to_locale_id/1` — coerces a language tag, atom, or string
    to a canonical locale identifier atom.

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

  ### Examples

      iex> Localize.Locale.display_name!("en-AU")
      "English (Australia)"

  """
  @spec display_name!(LanguageTag.t() | String.t() | atom(), Keyword.t()) :: String.t()
  defdelegate display_name!(locale, options \\ []), to: Localize.Locale.LocaleDisplay

  # ── Locale inheritance ────────────────────────────────────────

  @parent_locales SupplementalData.parent_locales()

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

  # Look up a parent locale in the parent_locales map.
  # The map uses minimal keys (e.g., "en-AU" not "en-Latn-AU"),
  # so we also try without the script since maximized tags include
  # the likely script which is usually omitted in the map keys.
  # We only check forms with the SAME specificity — we don't
  # drop territory or variants here (that's find_parent's job).
  defp lookup_parent_locale(%LanguageTag{} = tag) do
    full_key =
      locale_id_from(tag.language, tag.script, tag.territory, tag.language_variants)

    case Map.get(@parent_locales, full_key) do
      nil ->
        # Try without script (handles maximized tags like en-Latn-AU → en-AU)
        no_script_key =
          locale_id_from(tag.language, nil, tag.territory, tag.language_variants)

        Map.get(@parent_locales, no_script_key)

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

  ### Returns

  * `{:ok, value}` if the key path resolves to a value.

  * `{:error, reason}` if the key path cannot be resolved.

  """
  @spec get(Provider.locale(), list(), Keyword.t()) ::
          {:ok, term()} | {:error, term()}
  def get(locale, keys, options \\ []) do
    {provider, options} = Keyword.pop(options, :provider, default_provider())
    {fallback?, options} = Keyword.pop(options, :fallback, false)

    with :ok <- load_and_store(locale, provider: provider) do
      case provider.get(locale, keys, options) do
        {:ok, _} = ok ->
          ok

        {:error, %Localize.ItemNotFoundError{}} when fallback? ->
          fallback_through_parents(locale, keys, provider, options)

        {:error, _} = error ->
          error
      end
    end
  end

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
    original_id = to_locale_id(original_locale)
    walk_parents(original_id, original_id, keys, provider, options, [original_id])
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

          {:error, _} = error ->
            error
        end

      :no_parent ->
        {:error, Localize.ItemNotFoundError.exception(locale: original_id, keys: keys)}
    end
  end

  @spec next_parent(atom(), [atom(), ...]) :: {:ok, atom()} | :no_parent
  defp next_parent(locale_id, visited) do
    case parent(to_string(locale_id)) do
      {:ok, parent_tag} ->
        parent_id = to_locale_id(parent_tag)

        if parent_id in visited do
          :no_parent
        else
          {:ok, parent_id}
        end

      {:error, _} ->
        :no_parent
    end
  end

  # ── Locale ID coercion ────────────────────────────────────────

  @doc """
  Coerces a locale identifier to an atom.

  Accepts a `t:Localize.LanguageTag.t/0`, an atom, or a binary
  string and returns the corresponding locale identifier atom.

  When given a `Localize.LanguageTag` with a populated
  `:cldr_locale_id`, that value is returned directly. When the
  `:cldr_locale_id` is `nil`, the tag is serialised to a string
  and converted to an atom.

  ### Arguments

  * `locale` is a `t:Localize.LanguageTag.t/0`, an atom, or
    a binary string.

  ### Returns

  * A locale identifier atom.

  ### Examples

      iex> Localize.Locale.to_locale_id(:en)
      :en

      iex> Localize.Locale.to_locale_id("en")
      :en

  """
  @spec to_locale_id(LanguageTag.t() | atom() | String.t()) :: atom()
  def to_locale_id(%LanguageTag{cldr_locale_id: locale_id})
      when not is_nil(locale_id) do
    locale_id
  end

  # A root tag (`und` with no script/territory/variants) maps to `:und`
  # unconditionally. Running it through likely-subtag resolution via
  # `validate_locale/1` would maximize it back to e.g. `en-Latn-US` or,
  # if the tag carries `-u-` extensions copied from a child during
  # parent-chain walking, to whichever locale the extensions bias it
  # toward — creating a cycle where the parent chain never terminates.
  def to_locale_id(%LanguageTag{
        language: :und,
        script: nil,
        territory: nil,
        language_variants: []
      }) do
    :und
  end

  def to_locale_id(%LanguageTag{} = tag) do
    # When cldr_locale_id is nil, resolve it via validate_locale
    # which populates the field through likely-subtag resolution.
    # This ensures download URLs and cache paths always use the
    # canonical CLDR locale identifier (e.g. :en, :"en-AU") rather
    # than the full tag string which may include extensions, script,
    # and other components that don't correspond to an ETF file name.
    case Localize.validate_locale(tag) do
      {:ok, %{cldr_locale_id: resolved}} when not is_nil(resolved) -> resolved
      _ -> tag |> LanguageTag.to_string() |> String.to_atom()
    end
  end

  def to_locale_id(locale_id) when is_atom(locale_id), do: locale_id
  def to_locale_id(locale_id) when is_binary(locale_id), do: String.to_atom(locale_id)
  def to_locale_id(locale_id), do: String.to_atom(inspect(locale_id))

  @doc """
  Resolves any locale input to its CLDR locale id, validating along
  the way.

  Accepts the same input shapes as `Localize.validate_locale/1` —
  atom, string, or `t:Localize.LanguageTag.t/0` — and returns the
  canonical CLDR locale id atom. A pre-validated language tag (whose
  `:cldr_locale_id` is already populated) takes a fast path that
  skips re-validation; raw parsed tags and other inputs go through
  `Localize.validate_locale/1`.

  Use this from formatter modules that need a CLDR locale id and
  want invalid input to propagate as `{:error, exception}` rather
  than coerce silently.

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

      iex> {:ok, parsed} = Localize.LanguageTag.parse("fr")
      iex> Localize.Locale.cldr_locale_id_from(parsed)
      {:ok, :fr}

      iex> Localize.Locale.cldr_locale_id_from("en-AU")
      {:ok, :"en-AU"}

  """
  @spec cldr_locale_id_from(LanguageTag.t() | atom() | String.t()) ::
          {:ok, atom()} | {:error, Exception.t()}
  def cldr_locale_id_from(%LanguageTag{cldr_locale_id: id}) when not is_nil(id) do
    {:ok, id}
  end

  def cldr_locale_id_from(locale) do
    with {:ok, %LanguageTag{cldr_locale_id: id}} <- Localize.validate_locale(locale) do
      {:ok, id}
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
  Expands a list of locale identifiers (atoms and wildcard strings)
  into a list of known CLDR locale ID atoms.

  Each entry is either an atom matching a known CLDR locale
  (e.g. `:en`, `:"fr-CA"`) or a string with a trailing `*`
  wildcard (e.g. `"en-*"`) that expands to all matching locales.

  Invalid entries log a warning and are skipped.

  ### Arguments

  * `entries` is a list of atoms and/or strings.

  * `context` is an atom or string used in warning messages to
    identify where the entry came from (e.g. `:supported_locales`).

  ### Returns

  * A deduplicated list of locale ID atoms.

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

  defp expand_locale_entry(entry, all_ids, _all_strings, context) when is_atom(entry) do
    if entry in all_ids do
      [entry]
    else
      require Logger

      Logger.warning(
        "Ignoring unknown locale #{inspect(entry)} in #{inspect(context)} configuration. " <>
          "Not found in known CLDR locales.",
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
end
