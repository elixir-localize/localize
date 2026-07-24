defmodule Localize.Inflection do
  @moduledoc """
  Grammatical inflection for natural language messages, based on the
  data published by the [Unicode inflection project](https://github.com/unicode-org/inflection).

  Words and phrases are wrapped in a `Localize.Inflection.Concept`,
  constrained by grammatical features (number, gender, case,
  definiteness, …) and rendered in their grammatically correct
  surface form. Grammatical properties of a phrase can also be
  queried, for use with grammar-dependent message selection such as
  MessageFormat 2 `.match` selectors.

  ### Examples

      iex> Localize.Inflection.inflect("light on the patio", :en, number: :plural)
      {:ok, "lights on the patio"}

      iex> Localize.Inflection.inflect("the cat", :en, definiteness: :indefinite)
      {:ok, "a cat"}

      iex> Localize.Inflection.feature("lights", :en, :number)
      {:ok, :plural}

  """

  alias Localize.Inflection.{Concept, Data, Feature, PronounConcept, Quantify, SpeakableString}

  @doc """
  Inflects a word or phrase according to grammatical constraints.

  ### Arguments

  * `phrase` is the word or phrase to inflect.

  * `locale` is a locale atom or string, canonically BCP47,
    such as `:en` or `:es`.

  * `constraints` is a keyword list or map of feature names to
    values, such as `number: :plural` or
    `definiteness: :definite`.

  ### Returns

  * `{:ok, inflected}` with the phrase in its requested form, or
    `{:error, reason}` when a constraint is invalid or the locale
    is unavailable.

  ### Examples

      iex> Localize.Inflection.inflect("cat", :en, number: :plural)
      {:ok, "cats"}

      iex> Localize.Inflection.inflect("gato", :es, gender: :feminine)
      {:ok, "gata"}

      iex> Localize.Inflection.inflect("लड़का", :hi, gender: :feminine)
      {:ok, "लड़की"}

      iex> Localize.Inflection.inflect("кошка", :ru, case: :dative)
      {:ok, "кошке"}

      iex> Localize.Inflection.inflect("новый", :ru, gender: :feminine, case: :dative)
      {:ok, "новой"}

      iex> Localize.Inflection.inflect("новый дом", :ru, case: :instrumental)
      {:ok, "новым домом"}

  """
  def inflect(phrase, locale, constraints) do
    constraints = Feature.normalize_constraints(constraints)

    with {:ok, concept} <- Concept.new(locale, phrase, constraints: constraints) do
      case Concept.to_speakable_string(concept) do
        nil -> {:error, :not_inflectable}
        speakable -> {:ok, SpeakableString.print(speakable)}
      end
    end
  end

  @doc """
  Queries a grammatical feature of a word or phrase.

  ### Arguments

  * `phrase` is the word or phrase to inspect.

  * `locale` is a locale atom or string, canonically BCP47, for which data has been generated.

  * `feature` is the feature name, such as "number", "gender" or
    "definiteness".

  ### Returns

  * `{:ok, value}` where value is the feature value (an atom for
    grammeme-valued features, a string for display features such
    as articles) or nil when the feature cannot be determined, or
    `{:error, reason}`.

  ### Examples

      iex> Localize.Inflection.feature("luces", :es, :number)
      {:ok, :plural}

      iex> Localize.Inflection.feature("universidad", :es, :gender)
      {:ok, :feminine}

  """
  def feature(phrase, locale, feature) do
    with {:ok, concept} <- Concept.new(locale, phrase) do
      case Concept.feature_value(concept, feature) do
        nil -> {:ok, nil}
        value when is_atom(value) -> {:ok, value}
        value -> {:ok, SpeakableString.print(value)}
      end
    end
  end

  @doc """
  Returns the grammatical features defined for a locale.

  ### Arguments

  * `locale` is a locale atom or string, canonically BCP47, for which data has been generated.

  ### Returns

  * `{:ok, features}` where features maps each feature name atom to
    `%{type:, values:}` — type is `:bounded` or `:unbounded` and
    values is the sorted list of valid grammeme atoms (empty for
    unbounded features) — or `{:error, reason}`.

  ### Examples

      iex> {:ok, features} = Localize.Inflection.features(:en)
      iex> features.number
      %{type: :bounded, values: [:plural, :singular]}

  """
  def features(locale) do
    with {:ok, locale} <- Localize.Inflection.Locale.resolve(locale),
         :ok <- Data.ensure_loaded(locale) do
      {:ok, Feature.public_features(locale)}
    end
  end

  @doc """
  Returns the valid values of one grammatical feature for a locale.

  ### Arguments

  * `locale` is a locale atom or string, canonically BCP47, for which data has been generated.

  * `feature` is a feature name such as `:case` or `:number`.

  ### Returns

  * `{:ok, values}` with the sorted list of valid grammeme atoms,
    or `{:error, reason}` when the locale is unavailable or does
    not define the feature.

  ### Examples

      iex> Localize.Inflection.feature_values(:de, :case)
      {:ok, [:accusative, :dative, :genitive, :nominative]}

      iex> Localize.Inflection.feature_values(:en, :case)
      {:ok, [:accusative, :genitive, :nominative]}

      iex> Localize.Inflection.feature_values(:en, :sizzle)
      {:error, {:unknown_feature, :sizzle}}

  """
  def feature_values(locale, feature) do
    with {:ok, features} <- features(locale) do
      case Map.get(features, feature) do
        nil -> {:error, {:unknown_feature, feature}}
        %{values: values} -> {:ok, values}
      end
    end
  end

  @doc """
  Selects the pronoun matching grammatical constraints, optionally
  reinflecting an existing pronoun.

  ### Arguments

  * `locale` is a locale atom or string with a pronoun table, such as `:en`.

  * `initial_pronoun` is an optional pronoun whose grammatical
    properties (person, number, …) carry over where not overridden
    by the constraints.

  * `constraints` is a keyword list or map of feature names to
    values, such as `person: :first` or `case: :genitive`.

  ### Returns

  * `{:ok, pronoun}` with the selected pronoun, or
    `{:error, reason}` when the locale has no pronoun table, the
    initial pronoun is unknown, or a constraint is invalid.

  ### Examples

      iex> Localize.Inflection.pronoun(:en, person: :first, case: :genitive)
      {:ok, "mine"}

      iex> Localize.Inflection.pronoun(:en, "they", gender: :feminine)
      {:ok, "she"}

      iex> Localize.Inflection.pronoun(:fr, person: :second, number: :singular, case: :accusative)
      {:ok, "te "}

  """
  def pronoun(locale, initial_pronoun \\ nil, constraints) do
    options = if initial_pronoun, do: [initial_pronoun: initial_pronoun], else: []

    with {:ok, concept} <- PronounConcept.new(locale, options),
         {:ok, concept} <- put_pronoun_constraints(concept, constraints) do
      case PronounConcept.to_speakable_string(concept) do
        nil -> {:error, :no_matching_pronoun}
        speakable -> {:ok, SpeakableString.print(speakable)}
      end
    end
  end

  @doc """
  Quantifies a word or phrase with a pre-formatted number so the
  noun agrees grammatically with the count.

  ### Arguments

  * `formatted_number` is the formatted number as a speakable
    string (formatting the number is the caller's responsibility;
    in Localize it comes from the number formatter).

  * `phrase` is the word or phrase to quantify.

  * `locale` is a locale atom or string, canonically BCP47.

  * `options` is a keyword list of options.

  ### Options

  * `:plural` is the CLDR plural category of the number
    (`:zero | :one | :two | :few | :many | :other`); when absent
    the configured provider is consulted (see
    `:number` option.

  * `:number` is the numeric value, needed when the category comes
    from the provider and for Serbo-Croatian fraction handling.

  * `:constraints` is a map of grammatical constraints on the
    phrase (for example a case the surrounding sentence requires).

  ### Returns

  * `{:ok, quantified}` with the printed quantified phrase, or
    `{:error, reason}`.

  ### Examples

      iex> Localize.Inflection.quantify("2", "kilometer", :en, plural: :other)
      {:ok, "2 kilometers"}

      iex> Localize.Inflection.quantify("2", "час", :ru, plural: :few)
      {:ok, "2 часа"}

      iex> Localize.Inflection.quantify("5", "час", :ru, plural: :many)
      {:ok, "5 часов"}

      iex> Localize.Inflection.quantify("3", "talo", :fi, plural: :other)
      {:ok, "3 taloa"}

  """
  def quantify(formatted_number, phrase, locale, options \\ []) do
    constraints = Keyword.get(options, :constraints, %{})

    with {:ok, concept} <- Concept.new(locale, phrase, constraints: constraints),
         {:ok, speakable} <-
           Quantify.quantify_formatted(locale, formatted_number, concept, options) do
      {:ok, SpeakableString.print(speakable)}
    end
  end

  defp put_pronoun_constraints(concept, constraints) do
    Enum.reduce_while(constraints, {:ok, concept}, fn {name, value}, {:ok, concept} ->
      case PronounConcept.put_constraint(concept, to_string(name), value) do
        {:ok, concept} -> {:cont, {:ok, concept}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end
end
