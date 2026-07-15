defmodule Localize.Territory.Subdivision do
  @moduledoc """
  Territory subdivision localization functions.

  Subdivisions are administrative divisions within a territory, such as
  states, provinces, regions, or counties. They are identified by ISO
  3166-2 codes (lowercase atoms like `:caon` for Ontario, Canada or
  `:gbeng` for England, United Kingdom).

  ### Lookup functions

  This module provides three related but distinct functions for
  discovering subdivisions. Understanding the difference between them
  is important:

  * `subdivision_names_for/1` — takes a **locale**, returns a map of
    every subdivision code to its display name in that locale.
    Answers: "what subdivisions can I display in Japanese?"

  * `subdivisions_for/1` — takes a **locale**, returns the sorted
    list of subdivision codes that have translations in that locale.
    This is just the keys of `subdivision_names_for/1`. Answers:
    "which subdivision codes does my locale's data cover?"

  * `for_territory/1` — takes a **territory**, returns the structural
    subdivisions that belong to that territory from CLDR supplemental
    data. Independent of any locale. Answers: "what are the provinces
    of Canada?"

  The first two are locale-scoped (different locales may have different
  sets of translated subdivisions). The third is territory-scoped
  (the structural hierarchy of administrative divisions is the same
  regardless of which locale is asking).

  ### Display names

  * `display_name/2` returns the localized name for a single subdivision
    code in a specified locale.

  """

  alias Localize.LanguageTag

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

      iex> Localize.Territory.Subdivision.display_name(:caon, locale: :en)
      {:ok, "Ontario"}

      iex> Localize.Territory.Subdivision.display_name("gbcma", locale: :en)
      {:ok, "Cumbria"}

  """
  @spec display_name(atom() | String.t(), Keyword.t()) ::
          {:ok, String.t()} | {:error, Exception.t()}
  def display_name(subdivision, options \\ []) do
    locale = Keyword.get(options, :locale, Localize.get_locale())
    code = normalize_subdivision_code(subdivision)

    with {:ok, locale_id} <- Localize.Locale.cldr_locale_id_from(locale),
         {:ok, subdivisions} <- Localize.Locale.get(locale_id, [:subdivisions]) do
      case Map.get(subdivisions, code) do
        nil ->
          {:error, Localize.UnknownSubdivisionError.exception(subdivision: subdivision)}

        name ->
          {:ok, name}
      end
    end
  end

  @doc """
  Same as `display_name/2` but raises on error.

  ### Options

  * See `display_name/2` for the supported options.

  ### Examples

      iex> Localize.Territory.Subdivision.display_name!(:caon, locale: :en)
      "Ontario"

  """
  @spec display_name!(atom() | String.t(), Keyword.t()) :: String.t()
  def display_name!(subdivision, options \\ []) do
    case display_name(subdivision, options) do
      {:ok, name} -> name
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Returns a map of every subdivision code to its display name in a
  given locale.

  The returned map contains an entry for every subdivision that has a
  translation in the locale's data. This is locale-scoped — different
  locales cover different sets of subdivisions depending on which
  translations CLDR has for that locale.

  For the structural subdivisions of a specific territory regardless
  of locale, use `for_territory/1`.

  ### Arguments

  * `options` is a keyword list of options.

  ### Options

  * `:locale` is a locale identifier. The default is
    `Localize.get_locale()`.

  ### Returns

  * `{:ok, subdivisions}` where `subdivisions` is a map of
    subdivision code atoms to localized name strings.

  * `{:error, exception}` if the locale cannot be resolved.

  ### Examples

      iex> {:ok, subdivisions} = Localize.Territory.Subdivision.subdivision_names_for(locale: :en)
      iex> Map.get(subdivisions, :caon)
      "Ontario"

      iex> {:ok, subdivisions} = Localize.Territory.Subdivision.subdivision_names_for(locale: :fr)
      iex> Map.get(subdivisions, :gbeng)
      "Angleterre"

  """
  @spec subdivision_names_for(Keyword.t()) ::
          {:ok, %{atom() => String.t()}} | {:error, Exception.t()}
  def subdivision_names_for(options \\ []) do
    locale = Keyword.get(options, :locale, Localize.get_locale())

    with {:ok, locale_id} <- Localize.Locale.cldr_locale_id_from(locale) do
      Localize.Locale.get(locale_id, [:subdivisions])
    end
  end

  @doc """
  Returns the sorted list of subdivision codes that have translations
  in a given locale.

  Equivalent to the keys of `subdivision_names_for/1`, sorted.

  For the structural subdivisions of a specific territory regardless
  of locale, use `for_territory/1`.

  ### Arguments

  * `options` is a keyword list of options.

  ### Options

  * `:locale` is a locale identifier. The default is
    `Localize.get_locale()`.

  ### Returns

  * `{:ok, codes}` where `codes` is a sorted list of subdivision
    code atoms.

  * `{:error, exception}` if the locale cannot be resolved.

  ### Examples

      iex> {:ok, codes} = Localize.Territory.Subdivision.subdivisions_for(locale: :en)
      iex> :caon in codes
      true

  """
  @spec subdivisions_for(Keyword.t()) ::
          {:ok, [atom()]} | {:error, Exception.t()}
  def subdivisions_for(options \\ []) do
    with {:ok, subdivisions} <- subdivision_names_for(options) do
      {:ok, subdivisions |> Map.keys() |> Enum.sort()}
    end
  end

  @doc """
  Returns the structural subdivisions of a territory.

  Returns the administrative subdivisions that belong to a territory
  according to CLDR supplemental data. This is locale-independent —
  the structural hierarchy is the same regardless of which locale is
  asking.

  For the set of subdivisions that have translations in a specific
  locale, use `subdivision_names_for/1` or `subdivisions_for/1`.

  ### Arguments

  * `territory` is a territory code atom (e.g. `:CA`), a territory
    code string (e.g. `"CA"`), or a `t:Localize.LanguageTag.t/0`
    from which the territory is derived via
    `Localize.Territory.territory_from_locale/1`.

  ### Returns

  * `{:ok, [atom()]}` — a list of subdivision code atoms.

  * `{:error, exception}` if the territory is not known.

  ### Examples

      iex> {:ok, subdivisions} = Localize.Territory.Subdivision.for_territory(:GB)
      iex> :gbeng in subdivisions
      true

      iex> {:ok, subdivisions} = Localize.Territory.Subdivision.for_territory("CA")
      iex> :caon in subdivisions
      true

  """
  @spec for_territory(atom() | String.t() | LanguageTag.t()) ::
          {:ok, [atom()]} | {:error, Exception.t()}
  def for_territory(%LanguageTag{} = language_tag) do
    with {:ok, territory} <- Localize.Territory.territory_from_locale(language_tag) do
      for_territory(territory)
    end
  end

  def for_territory(territory) do
    with {:ok, code} <- Localize.validate_territory(territory) do
      subdivisions = Map.get(Localize.SupplementalData.territory_subdivisions(), code, [])
      {:ok, subdivisions}
    end
  end

  # ── Private helpers ─────────────────────────────────────────

  defp normalize_subdivision_code(code) when is_atom(code), do: code

  # Use `existing_atom/1` so attacker-supplied binary codes can't
  # grow the atom table. CLDR subdivision codes (`"usca"`, `"gbcma"`,
  # etc.) are pre-atomised as keys of the per-locale subdivisions map
  # at startup. Unknown binaries return nil; the caller's
  # `Map.get(subdivisions, nil)` falls through to the
  # `UnknownSubdivisionError` path, which reports the original
  # (un-normalized) input.
  defp normalize_subdivision_code(code) when is_binary(code) do
    code |> String.downcase() |> Localize.Utils.Helpers.existing_atom()
  end
end
