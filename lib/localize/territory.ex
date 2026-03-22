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
  Returns the list of available territory display name styles.

  ### Returns

  * `[:short, :standard, :variant]`.

  ### Examples

      iex> Localize.Territory.available_styles()
      [:short, :standard, :variant]

  """
  @spec available_styles() :: [:short | :standard | :variant]
  def available_styles, do: @styles

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
         {:ok, style_atom} <- validate_style(style) do
      locale_id = Localize.Locale.to_locale_id(locale)

      case Localize.Locale.get(locale_id, [:territories]) do
        {:ok, territories} ->
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
              {:error,
               Localize.UnknownTerritoryError.exception(territory: territory_atom)}
          end

        {:error, _} = error ->
          error
      end
    end
  end

  @doc """
  Same as `display_name/2` but raises on error.

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

  # ── Subdivision display names ───────────────────────────────

  @doc """
  Returns the localized display name for a subdivision code.

  ### Arguments

  * `subdivision` is a subdivision code atom or string
    (e.g., `"usca"`, `"gbcma"`, `:caon`).

  * `options` is a keyword list of options.

  ### Options

  * `:locale` is a locale identifier. The default is
    `Localize.get_locale()`.

  ### Returns

  * `{:ok, name}` where `name` is the localized subdivision name.

  * `{:error, exception}` if the subdivision is unknown or the
    locale has no translation for it.

  ### Examples

      iex> Localize.Territory.subdivision_name(:caon, locale: :en)
      {:ok, "Ontario"}

      iex> Localize.Territory.subdivision_name("gbcma", locale: :en)
      {:ok, "Cumbria"}

  """
  @spec subdivision_name(atom() | String.t(), Keyword.t()) ::
          {:ok, String.t()} | {:error, Exception.t()}
  def subdivision_name(subdivision, options \\ []) do
    locale = Keyword.get(options, :locale, Localize.get_locale())
    locale_id = Localize.Locale.to_locale_id(locale)
    code = normalize_subdivision_code(subdivision)

    with {:ok, subdivisions} <- Localize.Locale.get(locale_id, [:subdivisions]) do
      case Map.get(subdivisions, code) do
        nil ->
          {:error,
           Localize.UnknownSubdivisionError.exception(subdivision: code)}

        name ->
          {:ok, name}
      end
    end
  end

  @doc """
  Same as `subdivision_name/2` but raises on error.

  ### Examples

      iex> Localize.Territory.subdivision_name!(:caon, locale: :en)
      "Ontario"

  """
  @spec subdivision_name!(atom() | String.t(), Keyword.t()) :: String.t()
  def subdivision_name!(subdivision, options \\ []) do
    case subdivision_name(subdivision, options) do
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

  @doc """
  Translates a subdivision name from one locale to another.

  ### Arguments

  * `name` is a localized subdivision name string.

  * `from_locale` is the locale the name is in.

  * `options` is a keyword list of options.

  ### Options

  * `:to` is the target locale. The default is
    `Localize.get_locale()`.

  ### Returns

  * `{:ok, translated_name}` on success.

  * `{:error, exception}` if the name cannot be found or
    translated.

  ### Examples

      iex> Localize.Territory.translate_subdivision("Ontario", :en, to: :pt)
      {:ok, "Ontário"}

  """
  @spec translate_subdivision(String.t(), atom() | String.t() | LanguageTag.t(), Keyword.t()) ::
          {:ok, String.t()} | {:error, Exception.t()}
  def translate_subdivision(name, from_locale, options \\ []) do
    to_locale = Keyword.get(options, :to, Localize.get_locale())
    from_locale_id = Localize.Locale.to_locale_id(from_locale)

    with {:ok, subdivisions} <- Localize.Locale.get(from_locale_id, [:subdivisions]) do
      normalized = normalize_name(name)

      inverted =
        for {code, sub_name} <- subdivisions,
            into: %{},
            do: {normalize_name(sub_name), code}

      case Map.get(inverted, normalized) do
        nil ->
          {:error,
           Localize.UnknownSubdivisionError.exception(subdivision: name)}

        code ->
          subdivision_name(code, locale: to_locale)
      end
    end
  end

  @doc """
  Same as `translate_subdivision/3` but raises on error.

  ### Examples

      iex> Localize.Territory.translate_subdivision!("Ontario", :en, to: :pt)
      "Ontário"

  """
  @spec translate_subdivision!(String.t(), atom() | String.t() | LanguageTag.t(), Keyword.t()) ::
          String.t()
  def translate_subdivision!(name, from_locale, options \\ []) do
    case translate_subdivision(name, from_locale, options) do
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
    locale_id = Localize.Locale.to_locale_id(locale)

    with {:ok, territories} <- Localize.Locale.get(locale_id, [:territories]) do
      normalized = normalize_name(name)

      inverted =
        for {code, names} <- territories,
            display_name <- Map.values(names),
            into: %{},
            do: {normalize_name(display_name), code}

      case Map.get(inverted, normalized) do
        nil ->
          {:error,
           Localize.UnknownTerritoryError.exception(territory: name)}

        code ->
          {:ok, code}
      end
    end
  end

  @doc """
  Same as `to_territory_code/2` but raises on error.

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
          {:error,
           Localize.UnknownTerritoryError.exception(territory: territory)}

        sorted ->
          {:ok, sorted}
      end
    end
  end

  @doc """
  Same as `parent/1` but raises on error.

  ### Examples

      iex> Localize.Territory.parent!(:GB)
      [:"154", :UN]

  """
  @spec parent!(atom() | String.t() | LanguageTag.t()) :: [atom()]
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
          {:error,
           Localize.UnknownTerritoryError.exception(territory: territory)}

        child_list ->
          {:ok, child_list}
      end
    end
  end

  @doc """
  Same as `children/1` but raises on error.

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

  * `parent_territory` is a territory code atom.

  * `child_territory` is a territory code atom.

  ### Returns

  * `true` if the parent contains the child.

  * `false` otherwise.

  ### Examples

      iex> Localize.Territory.contains?(:EU, :DK)
      true

      iex> Localize.Territory.contains?(:DK, :EU)
      false

  """
  @spec contains?(atom() | LanguageTag.t(), atom() | LanguageTag.t()) :: boolean()
  def contains?(%LanguageTag{territory: parent}, child), do: contains?(parent, child)
  def contains?(parent, %LanguageTag{territory: child}), do: contains?(parent, child)

  def contains?(parent, child) do
    containers = SupplementalData.territory_containers()

    case Map.get(containers, parent) do
      nil -> false
      children -> child in children
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
          {:error,
           Localize.UnknownTerritoryError.exception(territory: territory)}

        info_map ->
          {:ok, info_map}
      end
    end
  end

  @doc """
  Same as `info/1` but raises on error.

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
  Returns a map of territory codes (ISO 3166 Alpha-2) to their
  Alpha-3, FIPS 10, and numeric code equivalents.

  ### Returns

  * A map of `%{territory_atom => %{alpha3: string, ...}}`.

  ### Examples

      iex> codes = Localize.Territory.territory_codes()
      iex> Map.get(codes, :US)
      %{alpha3: "USA", numeric: "840"}

  """
  @spec territory_codes() :: %{atom() => map()}
  def territory_codes do
    SupplementalData.territory_codes()
  end

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

  # ── Country codes ───────────────────────────────────────────

  @regions [
    "005", "011", "013", "014", "015", "017", "018", "021",
    "029", "030", "034", "035", "039", "053", "054", "057",
    "061", "143", "145", "151", "154", "155"
  ]

  @doc """
  Returns a sorted list of country codes (territories that are
  not regions or groupings).

  ### Returns

  * A sorted list of territory code atoms.

  ### Examples

      iex> codes = Localize.Territory.country_codes()
      iex> :US in codes
      true

      iex> codes = Localize.Territory.country_codes()
      iex> :"001" in codes
      false

  """
  @spec country_codes() :: [atom()]
  def country_codes do
    containers = SupplementalData.territory_containers()

    @regions
    |> Enum.flat_map(fn region ->
      region_atom = String.to_atom(region)
      Map.get(containers, region_atom, [])
    end)
    |> Enum.sort()
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
    {:error,
     Localize.UnknownStyleError.exception(style: style, territory: nil)}
  end

  defp normalize_subdivision_code(code) when is_atom(code), do: code

  defp normalize_subdivision_code(code) when is_binary(code) do
    code |> String.downcase() |> String.to_atom()
  end
end
