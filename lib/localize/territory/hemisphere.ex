defmodule Localize.Territory.Hemisphere do
  @moduledoc """
  Returns the hemisphere a territory lies in.

  A season is the other half of the year either side of the equator, so
  anything that writes or reckons seasons needs to know which hemisphere a
  place is in. `hemisphere/1` answers for a territory code or for a locale,
  whose territory it takes from `Localize.Territory.territory_from_locale/1`.

  A territory the equator runs through has no single answer and is
  `:ambiguous`: Brazil, Indonesia and Kenya each have summer in both halves
  of the year depending where in them you stand.

  ## Where the data comes from

  CLDR carries no latitude for a territory, so the classification here is the
  library's own. Of the 261 territory codes CLDR knows, 154 own a zone in the
  IANA time zone database and their hemisphere is checked against the
  latitude it records (`test/localize/territory/hemisphere_test.exs`); the
  rest share another territory's zone and carry no coordinate of their own.

  A region (`:"002"`, `:"419"`) is not classified here at all. It is answered
  from the territories it contains, so a region cannot disagree with its own
  members: `:"005"` (South America) is `:ambiguous` because Brazil is, and
  `:"053"` (Australasia) is `:southern` because everything in it is.

  """

  # The equator runs through these, so neither half of the year is their
  # summer. The waters of a territory are not enough — the equator passes
  # between Equatorial Guinea's mainland and Annobón without crossing either,
  # and that territory is classified by where its people are.
  @ambiguous [:BR, :CD, :CG, :CO, :EC, :GA, :ID, :KE, :KI, :MV, :SO, :ST, :UG, :UM]

  # Everything below the equator. A territory that is neither here nor above,
  # and that contains no other territory, is northern — the northern half
  # holds the great majority of the codes and listing them would be noise.
  @southern [
    # South America
    :AR,
    :BO,
    :CL,
    :FK,
    :GS,
    :PE,
    :PY,
    :UY,

    # Africa and its islands
    :AO,
    :BI,
    :BW,
    :KM,
    :LS,
    :MG,
    :MU,
    :MW,
    :MZ,
    :NA,
    :RE,
    :RW,
    :SC,
    :SH,
    :SZ,
    :TZ,
    :YT,
    :ZA,
    :ZM,
    :ZW,

    # Oceania
    :AS,
    :AU,
    :CK,
    :FJ,
    :NC,
    :NF,
    :NR,
    :NU,
    :NZ,
    :PF,
    :PG,
    :PN,
    :SB,
    :TK,
    :TO,
    :TV,
    :VU,
    :WF,
    :WS,

    # Asia
    :TL,

    # The Indian Ocean
    :CC,
    :CX,
    :DG,
    :IO,
    :TF,

    # The southern Atlantic and the Antarctic
    :AC,
    :AQ,
    :BV,
    :HM,
    :TA
  ]

  @typedoc "The half of the world a territory lies in, or neither."
  @type t :: :northern | :southern | :ambiguous

  @doc """
  Returns the hemisphere a territory lies in.

  ### Arguments

  * `territory` is a territory code as an atom or a string, or a
    `t:Localize.LanguageTag.t/0` whose effective territory is used.

  ### Returns

  * `{:ok, :northern}` for a territory above the equator.

  * `{:ok, :southern}` for a territory below it.

  * `{:ok, :ambiguous}` for a territory the equator runs through, and for a
    region holding territories on both sides of it.

  * `{:error, exception}` if the territory is not known, or a locale names no
    territory.

  ### Examples

      iex> Localize.Territory.Hemisphere.hemisphere(:AU)
      {:ok, :southern}

      iex> Localize.Territory.Hemisphere.hemisphere("JP")
      {:ok, :northern}

      iex> Localize.Territory.Hemisphere.hemisphere(:BR)
      {:ok, :ambiguous}

      iex> {:ok, language_tag} = Localize.validate_locale("en-AU")
      iex> Localize.Territory.Hemisphere.hemisphere(language_tag)
      {:ok, :southern}

      iex> Localize.Territory.Hemisphere.hemisphere(:"053")
      {:ok, :southern}

      iex> Localize.Territory.Hemisphere.hemisphere(:"005")
      {:ok, :ambiguous}

  """
  @spec hemisphere(Localize.LanguageTag.t() | atom() | String.t()) ::
          {:ok, t()} | {:error, Exception.t()}
  def hemisphere(%Localize.LanguageTag{} = language_tag) do
    with {:ok, territory} <- Localize.Territory.territory_from_locale(language_tag) do
      hemisphere(territory)
    end
  end

  def hemisphere(territory) do
    with {:ok, code} <- Localize.validate_territory(territory),
         :ok <- known_territory(code) do
      {:ok, hemisphere_of(code, [])}
    end
  end

  @doc """
  Returns the hemisphere a territory lies in, raising on error.

  ### Arguments

  * `territory` is a territory code as an atom or a string, or a
    `t:Localize.LanguageTag.t/0`. See `hemisphere/1`.

  ### Returns

  * The hemisphere, one of `:northern`, `:southern` or `:ambiguous`.

  ### Raises

  * Raises if the territory is not known, or a locale names no territory.

  ### Examples

      iex> Localize.Territory.Hemisphere.hemisphere!(:NZ)
      :southern

      iex> Localize.Territory.Hemisphere.hemisphere!(:FR)
      :northern

  """
  @spec hemisphere!(Localize.LanguageTag.t() | atom() | String.t()) :: t() | no_return()
  def hemisphere!(territory) do
    case hemisphere(territory) do
      {:ok, hemisphere} -> hemisphere
      {:error, exception} -> raise exception
    end
  end

  # `Localize.validate_territory/1` accepts any code shaped like a region
  # subtag — `:QQ` and `:ZZ` among them — because a locale may carry one.
  # A code CLDR knows no territory for lies nowhere, so it is refused rather
  # than answered as northern by the default below.
  defp known_territory(code) do
    if code in Localize.Territory.known_territories() do
      :ok
    else
      {:error, Localize.UnknownTerritoryError.exception(territory: code)}
    end
  end

  # `visited` guards against a containment cycle rather than expecting one:
  # CLDR's containment is a tree from `001` down, but a region answered from
  # its members must not be able to loop if that ever stops being true.
  defp hemisphere_of(code, visited) do
    cond do
      code in @ambiguous -> :ambiguous
      code in @southern -> :southern
      true -> hemisphere_of_contained(code, visited)
    end
  end

  # A region takes the hemisphere its territories agree on, and is ambiguous
  # where they do not. A code containing nothing is northern: it is neither
  # listed above nor a region, so it lies above the equator.
  defp hemisphere_of_contained(code, visited) do
    case Localize.Territory.children(code) do
      {:ok, children} -> hemisphere_of_children(children, [code | visited])
      {:error, _contains_nothing} -> :northern
    end
  end

  defp hemisphere_of_children(children, visited) do
    children
    |> Enum.reject(&(&1 in visited))
    |> Enum.map(&hemisphere_of(&1, visited))
    |> Enum.uniq()
    |> case do
      [hemisphere] -> hemisphere
      _none_or_several -> :ambiguous
    end
  end
end
