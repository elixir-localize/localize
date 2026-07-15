defmodule Localize.Territory do
  @moduledoc """
  Provides territory and subdivision localization functions
  built on the Unicode CLDR repository.

  Territory display names, subdivision names, and translation
  between locales are loaded on demand from the locale data
  provider. Territory metadata (GDP, population, currency,
  measurement system, language population) is loaded from
  supplemental data.

  ## Styles

  Territory display names come in three styles:

  * `:standard` — the full display name (default).

  * `:short` — a shorter form when available (e.g., "US"
    instead of "United States").

  * `:variant` — an alternative form when available (e.g.,
    "Congo (Republic)" instead of "Congo - Brazzaville").

  """

  alias Localize.LanguageTag
  alias Localize.SupplementalData

  @styles [:short, :standard, :variant]

  # ── Styles ──────────────────────────────────────────────────

  @doc """
  Returns the list of territory display name styles known to CLDR.

  ### Returns

  * `[:short, :standard, :variant]`.

  ### Examples

      iex> Localize.Territory.known_styles()
      [:short, :standard, :variant]

  """
  @spec known_styles() :: [:short | :standard | :variant, ...]
  def known_styles, do: @styles

  @doc """
  Returns the list of all territory code atoms known to CLDR.

  The list covers every territory in the CLDR supplemental data,
  including containment codes such as `:EU` and the world code
  `:"001"`. It is locale-independent.

  ### Returns

  * A list of territory code atoms.

  ### Examples

      iex> territories = Localize.Territory.known_territories()
      iex> :US in territories and :EU in territories
      true

  """
  @spec known_territories() :: [atom(), ...]
  def known_territories do
    Localize.SupplementalData.known_territories()
  end

  # ── Per-locale territory data ───────────────────────────────

  @doc """
  Returns a sorted list of territory codes that have localized
  names in a locale.

  ### Arguments

  * `options` is a keyword list of options.

  ### Options

  * `:locale` is a locale identifier. The default is
    `Localize.get_locale()`.

  ### Returns

  * `{:ok, codes}` where `codes` is a sorted list of territory
    code atoms.

  * `{:error, exception}` if the locale data cannot be loaded.

  ### Examples

      iex> {:ok, codes} = Localize.Territory.territories_for()
      iex> :US in codes
      true

  """
  @spec territories_for(Keyword.t()) ::
          {:ok, [atom()]} | {:error, Exception.t()}
  def territories_for(options \\ []) do
    with {:ok, territories} <- territory_names_for(options) do
      {:ok, territories |> Map.keys() |> Enum.sort()}
    end
  end

  @doc """
  Returns a map of territory codes to their localized names in a
  locale.

  ### Arguments

  * `options` is a keyword list of options.

  ### Options

  * `:locale` is a locale identifier. The default is
    `Localize.get_locale()`.

  ### Returns

  * `{:ok, territories_map}` where `territories_map` is a map of
    `%{territory_atom => %{standard: name, ...}}`.

  * `{:error, exception}` if the locale data cannot be loaded.

  ### Examples

      iex> {:ok, territories} = Localize.Territory.territory_names_for()
      iex> territories[:NZ].standard
      "New Zealand"

      iex> {:ok, territories} = Localize.Territory.territory_names_for(locale: :de)
      iex> territories[:AT]
      %{standard: "Österreich"}

  """
  @spec territory_names_for(Keyword.t()) ::
          {:ok, %{atom() => map()}} | {:error, Exception.t()}
  def territory_names_for(options \\ []) do
    locale = Keyword.get(options, :locale, Localize.get_locale())

    with {:ok, locale_id} <- Localize.Locale.cldr_locale_id_from(locale) do
      Localize.Locale.get(locale_id, [:territories])
    end
  end

  # ── Display names ───────────────────────────────────────────

  @doc """
  Returns the localized display name for a territory code.

  ### Arguments

  * `territory` is a territory code atom, string, or a
    `t:Localize.LanguageTag.t/0`.

  * `options` is a keyword list of options.

  ### Options

  * `:locale` is a locale identifier. The default is
    `Localize.get_locale()`.

  * `:style` is one of `:short`, `:standard`, or `:variant`.
    The default is `:standard`.

  ### Returns

  * `{:ok, name}` where `name` is the localized territory name.

  * `{:error, exception}` if the territory is unknown, the
    locale cannot be loaded, or the style is not available.

  ### Examples

      iex> Localize.Territory.display_name(:GB)
      {:ok, "United Kingdom"}

      iex> Localize.Territory.display_name(:GB, style: :short)
      {:ok, "UK"}

      iex> Localize.Territory.display_name(:GB, locale: :pt)
      {:ok, "Reino Unido"}

  """
  @spec display_name(
          atom() | String.t() | LanguageTag.t(),
          Keyword.t()
        ) :: {:ok, String.t()} | {:error, Exception.t()}
  def display_name(territory, options \\ []) do
    locale = Keyword.get(options, :locale, Localize.get_locale())
    style = Keyword.get(options, :style, :standard)

    with {:ok, territory_atom} <- resolve_territory(territory),
         {:ok, style_atom} <- validate_style(style),
         {:ok, locale_id} <- Localize.Locale.cldr_locale_id_from(locale) do
      case Localize.Locale.get(locale_id, [:territories]) do
        {:ok, territories} ->
          territory_name_for_style(territories, territory_atom, style_atom, style)

        {:error, _} = error ->
          error
      end
    end
  end

  defp territory_name_for_style(territories, territory_atom, style_atom, style) do
    case territories do
      %{^territory_atom => %{^style_atom => name}} ->
        {:ok, name}

      %{^territory_atom => _} ->
        {:error,
         Localize.UnknownStyleError.exception(
           style: style,
           territory: territory_atom
         )}

      _ ->
        {:error, Localize.UnknownTerritoryError.exception(territory: territory_atom)}
    end
  end

  @doc """
  Same as `display_name/2` but raises on error.

  ### Arguments

  * `territory` is a territory code atom, string, or a
    `t:Localize.LanguageTag.t/0`.

  * `options` is a keyword list of options.

  ### Options

  * See `display_name/2` for the supported options.

  ### Returns

  * The localized territory name.

  ### Raises

  * Raises an exception if the territory name cannot be returned.

  ### Examples

      iex> Localize.Territory.display_name!(:GB)
      "United Kingdom"

      iex> Localize.Territory.display_name!(:GB, style: :short)
      "UK"

  """
  @spec display_name!(atom() | String.t() | LanguageTag.t(), Keyword.t()) :: String.t()
  def display_name!(territory, options \\ []) do
    case display_name(territory, options) do
      {:ok, name} -> name
      {:error, exception} -> raise exception
    end
  end

  # ── Translation ─────────────────────────────────────────────

  @doc """
  Translates a territory display name from one locale to another.

  Looks up the territory code for the given name in `from_locale`,
  then returns its display name in `to_locale`.

  ### Arguments

  * `name` is a localized territory name string.

  * `from_locale` is the locale the name is in.

  * `options` is a keyword list of options.

  ### Options

  * `:to` is the target locale. The default is
    `Localize.get_locale()`.

  * `:style` is one of `:short`, `:standard`, or `:variant`.
    The default is `:standard`.

  ### Returns

  * `{:ok, translated_name}` on success.

  * `{:error, exception}` if the name cannot be found in the
    source locale or translated to the target locale.

  ### Examples

      iex> Localize.Territory.translate_territory("United Kingdom", :en, to: :pt)
      {:ok, "Reino Unido"}

      iex> Localize.Territory.translate_territory("Reino Unido", :pt, to: :en)
      {:ok, "United Kingdom"}

  """
  @spec translate_territory(String.t(), atom() | String.t() | LanguageTag.t(), Keyword.t()) ::
          {:ok, String.t()} | {:error, Exception.t()}
  def translate_territory(name, from_locale, options \\ []) do
    to_locale = Keyword.get(options, :to, Localize.get_locale())
    style = Keyword.get(options, :style, :standard)

    with {:ok, territory_code} <- to_territory_code(name, from_locale) do
      display_name(territory_code, locale: to_locale, style: style)
    end
  end

  @doc """
  Same as `translate_territory/3` but raises on error.

  ### Arguments

  * `name` is a localized territory name string.

  * `from_locale` is the locale identifier in which `name` is
    expressed.

  * `options` is a keyword list of options.

  ### Options

  * See `translate_territory/3` for the supported options.

  ### Returns

  * The translated territory name.

  ### Raises

  * Raises an exception if the name cannot be translated.

  ### Examples

      iex> Localize.Territory.translate_territory!("United Kingdom", :en, to: :pt)
      "Reino Unido"

  """
  @spec translate_territory!(String.t(), atom() | String.t() | LanguageTag.t(), Keyword.t()) ::
          String.t()
  def translate_territory!(name, from_locale, options \\ []) do
    case translate_territory(name, from_locale, options) do
      {:ok, result} -> result
      {:error, exception} -> raise exception
    end
  end

  # ── Reverse lookup ──────────────────────────────────────────

  @doc """
  Converts a localized territory name to a territory code.

  ### Arguments

  * `name` is a localized territory name string.

  * `locale` is the locale the name is in.

  ### Returns

  * `{:ok, territory_code}` on success.

  * `{:error, exception}` if no matching territory is found.

  ### Examples

      iex> Localize.Territory.to_territory_code("United Kingdom", :en)
      {:ok, :GB}

      iex> Localize.Territory.to_territory_code("Reino Unido", :pt)
      {:ok, :GB}

  """
  @spec to_territory_code(String.t(), atom() | String.t() | LanguageTag.t()) ::
          {:ok, atom()} | {:error, Exception.t()}
  def to_territory_code(name, locale) do
    with {:ok, locale_id} <- Localize.Locale.cldr_locale_id_from(locale),
         {:ok, territories} <- Localize.Locale.get(locale_id, [:territories]) do
      normalized = normalize_name(name)

      inverted =
        for {code, names} <- territories,
            display_name <- Map.values(names),
            into: %{},
            do: {normalize_name(display_name), code}

      case Map.get(inverted, normalized) do
        nil ->
          {:error, Localize.UnknownTerritoryError.exception(territory: name)}

        code ->
          {:ok, code}
      end
    end
  end

  @doc """
  Same as `to_territory_code/2` but raises on error.

  ### Arguments

  * `name` is a localized territory name string.

  * `locale` is the locale identifier in which `name` is
    expressed.

  ### Returns

  * The territory code atom.

  ### Raises

  * Raises an exception if the name cannot be resolved.

  ### Examples

      iex> Localize.Territory.to_territory_code!("United Kingdom", :en)
      :GB

  """
  @spec to_territory_code!(String.t(), atom() | String.t() | LanguageTag.t()) :: atom()
  def to_territory_code!(name, locale) do
    case to_territory_code(name, locale) do
      {:ok, code} -> code
      {:error, exception} -> raise exception
    end
  end

  # ── Territory relationships ─────────────────────────────────

  @doc """
  Returns the parent territories for a given territory.

  ### Arguments

  * `territory` is a territory code atom, string, or a
    `t:Localize.LanguageTag.t/0`.

  ### Returns

  * `{:ok, parents}` where `parents` is a sorted list of
    parent territory atoms.

  * `{:error, exception}` if the territory is unknown or has
    no parents.

  ### Examples

      iex> Localize.Territory.parent(:GB)
      {:ok, [:"154", :UN]}

      iex> Localize.Territory.parent(:FR)
      {:ok, [:"155", :EU, :EZ, :UN]}

  """
  @spec parent(atom() | String.t() | LanguageTag.t()) ::
          {:ok, [atom()]} | {:error, Exception.t()}
  def parent(%LanguageTag{territory: territory}), do: parent(territory)

  def parent(territory) do
    with {:ok, code} <- Localize.validate_territory(territory) do
      containers = SupplementalData.territory_containers()

      parents =
        for {container, children} <- containers,
            code in children,
            do: container

      case Enum.sort(parents) do
        [] ->
          {:error, Localize.NoParentTerritoryError.exception(territory: code)}

        sorted ->
          {:ok, sorted}
      end
    end
  end

  @doc """
  Same as `parent/1` but raises on error.

  ### Arguments

  * `territory` is a territory code atom, string, or a
    `t:Localize.LanguageTag.t/0`.

  ### Returns

  * A sorted list of parent territory atoms.

  ### Raises

  * Raises an exception if the territory is unknown.

  ### Examples

      iex> Localize.Territory.parent!(:GB)
      [:"154", :UN]

  """
  @spec parent!(atom() | String.t() | LanguageTag.t()) :: [atom(), ...]
  def parent!(territory) do
    case parent(territory) do
      {:ok, result} -> result
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Returns the child territories for a given territory.

  ### Arguments

  * `territory` is a territory code atom, string, or a
    `t:Localize.LanguageTag.t/0`.

  ### Returns

  * `{:ok, children}` where `children` is a list of child
    territory atoms.

  * `{:error, exception}` if the territory is unknown or has
    no children.

  ### Examples

      iex> {:ok, children} = Localize.Territory.children(:EU)
      iex> :FR in children
      true

  """
  @spec children(atom() | String.t() | LanguageTag.t()) ::
          {:ok, [atom()]} | {:error, Exception.t()}
  def children(%LanguageTag{territory: territory}), do: children(territory)

  def children(territory) do
    with {:ok, code} <- Localize.validate_territory(territory) do
      containers = SupplementalData.territory_containers()

      case Map.get(containers, code) do
        nil ->
          {:error, Localize.UnknownTerritoryError.exception(territory: territory)}

        child_list ->
          {:ok, child_list}
      end
    end
  end

  @doc """
  Same as `children/1` but raises on error.

  ### Arguments

  * `territory` is a territory code atom, string, or a
    `t:Localize.LanguageTag.t/0`.

  ### Returns

  * A list of child territory atoms.

  ### Raises

  * Raises an exception if the territory is unknown.

  ### Examples

      iex> children = Localize.Territory.children!(:EU)
      iex> :DE in children
      true

  """
  @spec children!(atom() | String.t() | LanguageTag.t()) :: [atom()]
  def children!(territory) do
    case children(territory) do
      {:ok, result} -> result
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Checks if a parent territory contains a child territory.

  ### Arguments

  * `parent_territory` is a territory code atom, a territory code
    string, or a `t:Localize.LanguageTag.t/0`.

  * `child_territory` is a territory code atom, a territory code
    string, or a `t:Localize.LanguageTag.t/0`.

  ### Returns

  * `true` if the parent contains the child.

  * `false` otherwise, including when either territory is invalid.

  ### Examples

      iex> Localize.Territory.contains?(:EU, :DK)
      true

      iex> Localize.Territory.contains?("EU", "DK")
      true

      iex> Localize.Territory.contains?(:DK, :EU)
      false

  """
  @spec contains?(
          atom() | String.t() | LanguageTag.t(),
          atom() | String.t() | LanguageTag.t()
        ) :: boolean()
  def contains?(%LanguageTag{territory: parent}, child), do: contains?(parent, child)
  def contains?(parent, %LanguageTag{territory: child}), do: contains?(parent, child)

  def contains?(parent, child) do
    with {:ok, parent} <- Localize.validate_territory(parent),
         {:ok, child} <- Localize.validate_territory(child) do
      containers = SupplementalData.territory_containers()

      case Map.get(containers, parent) do
        nil -> false
        children -> child in children
      end
    else
      _ -> false
    end
  end

  # ── Territory info ──────────────────────────────────────────

  @doc """
  Returns metadata for a territory including GDP, population,
  currency, measurement system, and language population data.

  ### Arguments

  * `territory` is a territory code atom, string, or a
    `t:Localize.LanguageTag.t/0`.

  ### Returns

  * `{:ok, info_map}` on success.

  * `{:error, exception}` if the territory is unknown or has
    no metadata available.

  ### Examples

      iex> {:ok, info} = Localize.Territory.info(:US)
      iex> info.gdp
      24660000000000

      iex> {:ok, info} = Localize.Territory.info(:US)
      iex> info.population
      341963000

  """
  @spec info(atom() | String.t() | LanguageTag.t()) ::
          {:ok, map()} | {:error, Exception.t()}
  def info(%LanguageTag{territory: territory}), do: info(territory)

  def info(territory) do
    with {:ok, code} <- Localize.validate_territory(territory) do
      territories = SupplementalData.territories()

      case Map.get(territories, code) do
        nil ->
          {:error, Localize.UnknownTerritoryError.exception(territory: territory)}

        info_map ->
          {:ok, info_map}
      end
    end
  end

  @doc """
  Same as `info/1` but raises on error.

  ### Arguments

  * `territory` is a territory code atom, string, or a
    `t:Localize.LanguageTag.t/0`.

  ### Returns

  * A map of territory information.

  ### Raises

  * Raises an exception if the territory is unknown.

  ### Examples

      iex> info = Localize.Territory.info!(:US)
      iex> info.literacy_percent
      99

  """
  @spec info!(atom() | String.t() | LanguageTag.t()) :: map()
  def info!(territory) do
    case info(territory) do
      {:ok, result} -> result
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Returns a map of territory codes to their Alpha-3, FIPS 10, and numeric
  code equivalents.

  ### Arguments

  * `options` is a keyword list of options.

  ### Options

  * `:iso_3166` (boolean) — when `true`, filters the result to only those
    territories that are part of ISO 3166-1 (i.e. have a numeric UN M.49
    code less than 900; codes 900–999 are reserved by ISO for
    user-assigned and exceptional codes such as `:XK` Kosovo). CLDR-only
    codes like `:IC`, `:EA`, and reservations like `:AC`, `:DG`, `:TA`
    are also excluded. Default `false` (full CLDR territory map).

  ### Returns

  * A map of `%{territory_atom => %{alpha3: string, ...}}`.

  ### Examples

      iex> codes = Localize.Territory.territory_codes()
      iex> Map.get(codes, :US)
      %{alpha3: "USA", numeric: "840"}

      iex> codes = Localize.Territory.territory_codes(iso_3166: true)
      iex> Map.has_key?(codes, :US)
      true
      iex> Map.has_key?(codes, :XK)
      false

  """
  @spec territory_codes(Keyword.t()) :: %{atom() => map()}
  def territory_codes(options \\ []) do
    codes = SupplementalData.territory_codes()

    if Keyword.get(options, :iso_3166, false) do
      :maps.filter(fn _code, info -> iso_3166?(info) end, codes)
    else
      codes
    end
  end

  defp iso_3166?(%{numeric: numeric}) when is_binary(numeric) do
    case Integer.parse(numeric) do
      {n, ""} -> n < 900
      _ -> false
    end
  end

  defp iso_3166?(_), do: false

  # ── Currency helpers ────────────────────────────────────────

  @doc """
  Returns the current (oldest active) currency code for a
  territory.

  ### Arguments

  * `territory` is a territory code atom, string, or a
    `t:Localize.LanguageTag.t/0`.

  ### Returns

  * `{:ok, currency_code}` on success.

  * `{:error, exception}` if the territory has no active
    currencies.

  ### Examples

      iex> Localize.Territory.to_currency_code(:US)
      {:ok, :USD}

      iex> Localize.Territory.to_currency_code(:GB)
      {:ok, :GBP}

  """
  @spec to_currency_code(atom() | String.t() | LanguageTag.t()) ::
          {:ok, atom()} | {:error, Exception.t()}
  def to_currency_code(%LanguageTag{territory: territory}), do: to_currency_code(territory)

  def to_currency_code(territory) do
    case to_currency_codes(territory) do
      {:ok, [code | _]} -> {:ok, code}
      {:ok, []} -> {:error, Localize.UnknownCurrencyError.exception(currency: territory)}
      {:error, _} = error -> error
    end
  end

  @doc """
  Same as `to_currency_code/1` but raises on error.

  ### Arguments

  * `territory` is a territory code atom, string, or a
    `t:Localize.LanguageTag.t/0`.

  ### Returns

  * The current currency code atom for the territory.

  ### Raises

  * Raises an exception if the territory is unknown.

  ### Examples

      iex> Localize.Territory.to_currency_code!(:US)
      :USD

  """
  @spec to_currency_code!(atom() | String.t() | LanguageTag.t()) :: atom()
  def to_currency_code!(territory) do
    case to_currency_code(territory) do
      {:ok, result} -> result
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Returns all active currency codes for a territory, sorted
  by start date (oldest first).

  ### Arguments

  * `territory` is a territory code atom, string, or a
    `t:Localize.LanguageTag.t/0`.

  ### Returns

  * `{:ok, [currency_code, ...]}` on success.

  * `{:error, exception}` if the territory is unknown.

  ### Examples

      iex> Localize.Territory.to_currency_codes(:US)
      {:ok, [:USD]}

  """
  @spec to_currency_codes(atom() | String.t() | LanguageTag.t()) ::
          {:ok, [atom()]} | {:error, Exception.t()}
  def to_currency_codes(%LanguageTag{territory: territory}), do: to_currency_codes(territory)

  def to_currency_codes(territory) do
    case info(territory) do
      {:ok, %{currency: currency}} ->
        active =
          currency
          |> Enum.reject(fn {_code, meta} ->
            Map.has_key?(meta, :tender) or Map.has_key?(meta, :to)
          end)
          |> Enum.sort_by(fn {_code, meta} -> meta[:from] end, Date)
          |> Enum.map(&elem(&1, 0))

        {:ok, active}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Same as `to_currency_codes/1` but raises on error.

  ### Arguments

  * `territory` is a territory code atom, string, or a
    `t:Localize.LanguageTag.t/0`.

  ### Returns

  * A list of currency code atoms.

  ### Raises

  * Raises an exception if the territory is unknown.

  ### Examples

      iex> Localize.Territory.to_currency_codes!(:US)
      [:USD]

  """
  @spec to_currency_codes!(atom() | String.t() | LanguageTag.t()) :: [atom()]
  def to_currency_codes!(territory) do
    case to_currency_codes(territory) do
      {:ok, result} -> result
      {:error, exception} -> raise exception
    end
  end

  # ── Individual territories ──────────────────────────────────

  @regions [
    "005",
    "011",
    "013",
    "014",
    "015",
    "017",
    "018",
    "021",
    "029",
    "030",
    "034",
    "035",
    "039",
    "053",
    "054",
    "057",
    "061",
    "143",
    "145",
    "151",
    "154",
    "155"
  ]

  @doc """
  Returns a sorted list of territory codes for individual
  territories.

  Only leaf territories are returned — those contained by a
  continental or sub-continental region. Macro-regions and
  groupings (e.g., `:"001"` World, `:"150"` Europe) are
  excluded.

  To retrieve the full map of ISO 3166 code mappings
  (Alpha-2, Alpha-3, numeric) for all territories, see
  `territory_codes/1`.

  ### Returns

  * A sorted list of territory code atoms.

  ### Examples

      iex> codes = Localize.Territory.individual_territories()
      iex> :US in codes
      true

      iex> codes = Localize.Territory.individual_territories()
      iex> :"001" in codes
      false

  """
  @spec individual_territories() :: [atom()]
  def individual_territories do
    containers = SupplementalData.territory_containers()

    @regions
    |> Enum.flat_map(fn region ->
      region_atom = String.to_atom(region)
      Map.get(containers, region_atom, [])
    end)
    |> Enum.sort()
  end

  # ── Flag ─────────────────────────────────────────────────────

  @unicode_flag_codepoint_offset 0x1F1A5

  @doc """
  Returns a Unicode flag emoji for a territory or locale.

  Converts a two-letter ISO 3166 territory code into the
  corresponding regional indicator flag emoji. Territories
  that are not two-letter codes (e.g., region codes like
  `:"001"`) return an empty string.

  When given a `t:Localize.LanguageTag.t/0`, the territory
  is extracted from the tag.

  ### Arguments

  * `territory_or_locale` is a territory code atom, string,
    or a `t:Localize.LanguageTag.t/0`.

  ### Returns

  * `{:ok, flag_string}` where `flag_string` is the Unicode
    flag emoji, or an empty string if the territory does not
    have a flag representation.

  * `{:error, exception}` if the territory is not known.

  ### Examples

      iex> Localize.Territory.unicode_flag(:US)
      {:ok, "🇺🇸"}

      iex> Localize.Territory.unicode_flag(:GB)
      {:ok, "🇬🇧"}

      iex> Localize.Territory.unicode_flag(:"001")
      {:ok, ""}

      iex> {:ok, tag} = Localize.validate_locale(:en)
      iex> Localize.Territory.unicode_flag(tag)
      {:ok, "🇺🇸"}

  """
  @spec unicode_flag(LanguageTag.t() | atom() | String.t()) ::
          {:ok, String.t()} | {:error, Exception.t()}
  def unicode_flag(%LanguageTag{territory: territory}) when not is_nil(territory) do
    unicode_flag(territory)
  end

  def unicode_flag(%LanguageTag{} = locale) do
    with {:ok, territory} <- default_territory(locale) do
      unicode_flag(territory)
    end
  end

  def unicode_flag(territory) do
    with {:ok, territory_atom} <- Localize.validate_territory(territory) do
      flag_string =
        territory_atom
        |> Atom.to_charlist()
        |> generate_flag()

      {:ok, flag_string}
    end
  end

  @doc """
  Same as `unicode_flag/1` but raises on error.

  ### Arguments

  * `territory` is a territory code atom, string, or a
    `t:Localize.LanguageTag.t/0`.

  ### Returns

  * The emoji flag string for the territory.

  ### Raises

  * Raises an exception if the territory is unknown.

  ### Examples

      iex> Localize.Territory.unicode_flag!(:US)
      "🇺🇸"

  """
  @spec unicode_flag!(LanguageTag.t() | atom() | String.t()) :: String.t()
  def unicode_flag!(territory) do
    case unicode_flag(territory) do
      {:ok, result} -> result
      {:error, exception} -> raise exception
    end
  end

  defp generate_flag([_, _] = iso_code) do
    iso_code
    |> Enum.map(&(&1 + @unicode_flag_codepoint_offset))
    |> Kernel.to_string()
  end

  defp generate_flag(_), do: ""

  # ── Utility ──────────────────────────────────────────────────

  @doc """
  Returns the territory code representing the world.

  ### Returns

  * The atom `:"001"`.

  ### Examples

      iex> Localize.Territory.the_world()
      :"001"

  """
  @spec the_world() :: :"001"
  def the_world, do: :"001"

  @doc """
  Returns the territory fallback chain for a territory.

  The chain starts with the territory itself and includes each
  containing territory in order of increasing scope, ending with
  `:"001"` (the world).

  ### Arguments

  * `territory` is a territory code atom, string, or integer.

  ### Returns

  * `{:ok, chain}` where `chain` is a list of territory atoms.

  * `{:error, exception}` if the territory is not known.

  ### Examples

      iex> Localize.Territory.territory_chain(:US)
      {:ok, [:US, :UN, :"001"]}

      iex> Localize.Territory.territory_chain(:"001")
      {:ok, [:"001"]}

  """
  @spec territory_chain(atom() | String.t() | integer()) ::
          {:ok, [atom()]} | {:error, Exception.t()}
  def territory_chain(:"001" = world) do
    {:ok, [world]}
  end

  def territory_chain(territory) do
    with {:ok, territory_atom} <- Localize.validate_territory(territory) do
      case Map.fetch(SupplementalData.territory_containment(), territory_atom) do
        {:ok, chain} ->
          {:ok, [territory_atom | chain]}

        :error ->
          {:ok, [territory_atom]}
      end
    end
  end

  @doc """
  Returns the default territory for a locale.

  Extracts the territory from a locale's language tag. If the
  locale does not have an explicit territory, the likely subtag
  data is used to infer one.

  ### Arguments

  * `locale` is a locale identifier atom, string, or a
    `t:Localize.LanguageTag.t/0`.

  ### Returns

  * `{:ok, territory_atom}` where `territory_atom` is the
    inferred territory.

  * `{:error, exception}` if the locale is not valid.

  ### Examples

      iex> Localize.Territory.default_territory(:en)
      {:ok, :US}

      iex> Localize.Territory.default_territory(:ja)
      {:ok, :JP}

  """
  @spec default_territory(atom() | String.t() | LanguageTag.t()) ::
          {:ok, atom()} | {:error, Exception.t()}
  def default_territory(%LanguageTag{territory: territory})
      when not is_nil(territory) do
    {:ok, territory}
  end

  def default_territory(locale) do
    with {:ok, language_tag} <- Localize.validate_locale(locale) do
      {:ok, language_tag.territory}
    end
  end

  # ── Name normalization ──────────────────────────────────────

  @doc """
  Normalizes a territory or subdivision name for matching.

  Downcases the string, removes ` & ` and `.`, and collapses
  whitespace.

  ### Arguments

  * `name` is a territory or subdivision name string.

  ### Returns

  * A normalized string.

  ### Examples

      iex> Localize.Territory.normalize_name("Congo - Brazzaville")
      "congo - brazzaville"

  """
  @spec normalize_name(String.t()) :: String.t()
  def normalize_name(name) when is_binary(name) do
    name
    |> String.downcase()
    |> String.replace(" & ", "")
    |> String.replace(".", "")
    |> String.replace(~r/(\s)+/u, "\\1")
  end

  # ── Private helpers ─────────────────────────────────────────

  defp resolve_territory(%LanguageTag{territory: territory}) do
    Localize.validate_territory(territory)
  end

  defp resolve_territory(territory) do
    Localize.validate_territory(territory)
  end

  defp validate_style(style) when style in @styles, do: {:ok, style}

  defp validate_style(style) do
    {:error, Localize.UnknownStyleError.exception(style: style, territory: nil)}
  end

  # ── Territory from locale ──────────────────────────────────────

  @doc """
  Returns the effective territory for a locale.

  Resolves the territory using the following precedence:

  1. The `rg` (region override) Unicode extension parameter,
     if present (e.g., `"en-US-u-rg-gbzzzz"` → `:GB`).

  2. The explicit territory in the language tag (e.g.,
     `"en-AU"` → `:AU`).

  3. The territory inferred from likely subtags via
     `Localize.validate_locale/1` (e.g., `"en"` → `:US`,
     `"de"` → `:DE`).

  ### Arguments

  * `locale` is a locale identifier string, atom, or a
    `t:Localize.LanguageTag.t/0` struct.

  ### Returns

  * `{:ok, territory_code}` where `territory_code` is an atom.

  * `{:error, exception}` if the locale cannot be resolved.

  ### Examples

      iex> Localize.Territory.territory_from_locale("en-AU")
      {:ok, :AU}

      iex> Localize.Territory.territory_from_locale("en")
      {:ok, :US}

      iex> Localize.Territory.territory_from_locale("de")
      {:ok, :DE}

  """
  @spec territory_from_locale(Localize.LanguageTag.t() | String.t() | atom()) ::
          {:ok, atom()} | {:error, Exception.t()}
  def territory_from_locale(locale) when is_binary(locale) or is_atom(locale) do
    with {:ok, language_tag} <- Localize.validate_locale(locale) do
      territory_from_locale(language_tag)
    end
  end

  def territory_from_locale(%Localize.LanguageTag{locale: %{rg: rg}})
      when not is_nil(rg) do
    {:ok, rg}
  end

  def territory_from_locale(%Localize.LanguageTag{territory: territory})
      when not is_nil(territory) do
    {:ok, territory}
  end

  def territory_from_locale(%Localize.LanguageTag{} = tag) do
    case Localize.validate_locale(tag) do
      {:ok, %{territory: territory}} when not is_nil(territory) ->
        {:ok, territory}

      _ ->
        {:ok, Localize.default_locale().territory}
    end
  end
end
