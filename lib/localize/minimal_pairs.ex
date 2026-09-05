defmodule Localize.MinimalPairs do
  @moduledoc """
  Access to CLDR's minimal pairs: short translated phrases that show a
  grammatical form in context.

  A minimal pair is the smallest sentence that distinguishes one form from
  another — English cardinals are `"{0} day"` and `"{0} days"`, which differ
  only in the plural. CLDR ships them so translators can check that a rule
  selects the form they expect, and they serve the same purpose at runtime
  for anything that wants to show a worked example of a locale's plural,
  ordinal, case or gender behaviour.

  Four categories are available, and which of them a locale has depends on
  its grammar: every locale has cardinals, most have ordinals, and only
  locales that inflect for case or gender carry those.

  """

  alias Localize.Number.PluralRule

  @categories [:cardinal, :ordinal, :case, :gender]

  @typedoc "A grammatical feature CLDR ships minimal pairs for."
  @type category :: :cardinal | :ordinal | :case | :gender

  @doc """
  Returns the cardinal minimal pairs for a locale.

  ### Arguments

  * `locale` is a locale identifier atom, string, or a
    `t:Localize.LanguageTag.t/0`.

  ### Returns

  * `{:ok, map}` of plural category to phrase, such as
    `%{one: "{0} day", other: "{0} days"}`. The map is empty for a
    locale CLDR ships no pairs for.

  * `{:error, exception}` if the locale is unknown.

  ### Examples

      iex> {:ok, pairs} = Localize.MinimalPairs.cardinal(:en)
      iex> pairs[:one]
      "{0} day"

  """
  @spec cardinal(Localize.locale()) ::
          {:ok, %{atom() => String.t()}} | {:error, Exception.t()}
  def cardinal(locale), do: category(locale, :cardinal)

  @doc """
  Returns the ordinal minimal pairs for a locale.

  ### Arguments

  * `locale` is a locale identifier atom, string, or a
    `t:Localize.LanguageTag.t/0`.

  ### Returns

  * `{:ok, map}` of plural category to phrase, such as
    `%{one: "Take the {0}st right.", other: "Take the {0}th right."}`.

  * `{:error, exception}` if the locale is unknown.

  ### Examples

      iex> {:ok, pairs} = Localize.MinimalPairs.ordinal(:en)
      iex> pairs[:two]
      "Take the {0}nd right."

  """
  @spec ordinal(Localize.locale()) ::
          {:ok, %{atom() => String.t()}} | {:error, Exception.t()}
  def ordinal(locale), do: category(locale, :ordinal)

  @doc """
  Returns the grammatical-case minimal pairs for a locale.

  ### Arguments

  * `locale` is a locale identifier atom, string, or a
    `t:Localize.LanguageTag.t/0`.

  ### Returns

  * `{:ok, map}` of case name to phrase. Empty for a locale that does not
    inflect for case.

  * `{:error, exception}` if the locale is unknown.

  ### Examples

      iex> {:ok, pairs} = Localize.MinimalPairs.grammatical_case(:de)
      iex> Map.keys(pairs) |> Enum.sort()
      [:accusative, :dative, :genitive, :nominative]

      iex> Localize.MinimalPairs.grammatical_case(:en)
      {:ok, %{}}

  """
  @spec grammatical_case(Localize.locale()) ::
          {:ok, %{atom() => String.t()}} | {:error, Exception.t()}
  def grammatical_case(locale), do: category(locale, :case)

  @doc """
  Returns the grammatical-gender minimal pairs for a locale.

  ### Arguments

  * `locale` is a locale identifier atom, string, or a
    `t:Localize.LanguageTag.t/0`.

  ### Returns

  * `{:ok, map}` of gender name to phrase. Empty for a locale that does not
    inflect for gender.

  * `{:error, exception}` if the locale is unknown.

  ### Examples

      iex> {:ok, pairs} = Localize.MinimalPairs.grammatical_gender(:de)
      iex> Map.keys(pairs) |> Enum.sort()
      [:feminine, :masculine, :neuter]

  """
  @spec grammatical_gender(Localize.locale()) ::
          {:ok, %{atom() => String.t()}} | {:error, Exception.t()}
  def grammatical_gender(locale), do: category(locale, :gender)

  @doc """
  Formats a number into the minimal pair its plural category selects.

  Picks the cardinal or ordinal phrase the number would take in this locale
  and substitutes the number into it, which is what makes minimal pairs
  useful as a check: the output is the sentence a correct implementation
  should produce.

  ### Arguments

  * `number` is any number.

  * `category` is `:cardinal` (the default) or `:ordinal`.

  ### Options

  * `:locale` is any locale returned by `Localize.all_locale_ids/0`. Defaults
    to `Localize.get_locale/0`.

  ### Returns

  * `{:ok, string}` with the number substituted for `{0}`.

  * `{:error, exception}` if the locale is unknown, the category is not
    `:cardinal` or `:ordinal`, or the locale has no pair for the category
    the number selects.

  ### Examples

      iex> Localize.MinimalPairs.format(1, :cardinal, locale: :en)
      {:ok, "1 day"}

      iex> Localize.MinimalPairs.format(3, :cardinal, locale: :en)
      {:ok, "3 days"}

      iex> Localize.MinimalPairs.format(2, :ordinal, locale: :en)
      {:ok, "Take the 2nd right."}

      iex> Localize.MinimalPairs.format(2, locale: :en)
      {:ok, "2 days"}

  """
  @spec format(number(), :cardinal | :ordinal, Keyword.t()) ::
          {:ok, String.t()} | {:error, Exception.t()}
  def format(number, category \\ :cardinal, options \\ [])

  # `format(2, locale: :en)` is the natural call and would otherwise bind the
  # options to `category`.
  def format(number, options, []) when is_list(options) do
    format(number, :cardinal, options)
  end

  def format(number, category, options) when category in [:cardinal, :ordinal] do
    locale = Keyword.get(options, :locale, Localize.get_locale())

    with {:ok, pairs} <- category(locale, category),
         {:ok, plural} <- plural_category(number, category, locale),
         {:ok, phrase} <- fetch_phrase(pairs, plural, category, locale) do
      {:ok, String.replace(phrase, "{0}", to_string(number))}
    end
  end

  def format(_number, category, _options) do
    {:error,
     Localize.InvalidValueError.exception(
       value: category,
       expected: ":cardinal or :ordinal",
       context: "Localize.MinimalPairs.format/3"
     )}
  end

  @doc """
  Returns the categories for which minimal pairs may be available.

  ### Returns

  * `[:cardinal, :ordinal, :case, :gender]`.

  ### Examples

      iex> Localize.MinimalPairs.categories()
      [:cardinal, :ordinal, :case, :gender]

  """
  @spec categories() :: [category(), ...]
  def categories, do: @categories

  # ── Private helpers ─────────────────────────────────────────

  defp category(locale, category) do
    with {:ok, locale_id} <- Localize.Locale.cldr_locale_id_from(locale),
         {:ok, pairs} <- Localize.Locale.get(locale_id, [:minimal_pairs]) do
      {:ok, Map.get(pairs || %{}, category, %{})}
    end
  end

  defp plural_category(number, :cardinal, locale),
    do: wrap_plural(PluralRule.Cardinal.plural_rule(number, locale))

  defp plural_category(number, :ordinal, locale),
    do: wrap_plural(PluralRule.Ordinal.plural_rule(number, locale))

  defp wrap_plural({:error, _} = error), do: error
  defp wrap_plural(plural) when is_atom(plural), do: {:ok, plural}

  defp fetch_phrase(pairs, plural, category, locale) do
    case Map.fetch(pairs, plural) do
      {:ok, phrase} ->
        {:ok, phrase}

      :error ->
        {:error,
         Localize.NoMinimalPairError.exception(
           locale: locale,
           category: category,
           plural_category: plural
         )}
    end
  end
end
