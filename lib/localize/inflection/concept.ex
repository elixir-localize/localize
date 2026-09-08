defmodule Localize.Inflection.Concept do
  @moduledoc """
  An inflectable string with grammatical constraints.

  A concept wraps a word or phrase for a locale. Constraints (such
  as `number=plural` or `definiteness=definite`) are applied with
  `put_constraint/3`; grammatical properties are queried with
  `feature_value/2`; and `to_string/1` renders the phrase with all
  constraints applied.

  This is the equivalent of the upstream `InflectableStringConcept`.

  """

  alias Localize.Inflection.{
    Data,
    DisplayValue,
    Feature,
    FeatureModel,
    Locale,
    SpeakableString,
    Synthesizer
  }

  defstruct [:locale, :value, constraints: %{}, initial: %{}, guess: true]

  @type t :: %__MODULE__{
          locale: atom,
          value: SpeakableString.t(),
          constraints: %{optional(binary) => binary},
          initial: %{optional(binary) => binary},
          guess: boolean
        }

  @speak "speak"

  @doc """
  Creates a concept for a word or phrase.

  ### Arguments

  * `locale` is a locale atom or string, canonically BCP47 (`:en`, `"zh-TW"`), for which data has been generated.

  * `value` is the word or phrase, either a binary or a
    `{print, speak}` tuple.

  * `options` is a keyword list of options.

  ### Options

  * `:constraints` is a map of feature constraints to apply, as if
    set with `put_constraint/3`.

  * `:initial` is a map of features known to hold for the value
    itself (for example a known grammatical gender), used when
    deriving other features rather than requested for rendering.

  ### Returns

  * `{:ok, concept}` or `{:error, reason}` when the locale data is
    unavailable or a constraint is invalid.

  ### Examples

      iex> {:ok, concept} = Localize.Inflection.Concept.new(:en, "cat", constraints: %{number: :plural})
      iex> Localize.Inflection.Concept.to_speakable_string(concept)
      "cats"

      iex> {:error, error} = Localize.Inflection.Concept.new(:en, "cat", constraints: %{number: :dual})
      iex> error.value
      "dual"
      iex> error.allowed_values
      ["plural", "singular"]

  """
  def new(locale, value, options \\ []) do
    constraints = options |> Keyword.get(:constraints, %{}) |> Feature.normalize_constraints()
    initial = options |> Keyword.get(:initial, %{}) |> Feature.normalize_constraints()

    with {:ok, locale} <- Locale.resolve(locale),
         :ok <- Data.ensure_loaded(locale),
         {:ok, concept} <- validate(%__MODULE__{locale: locale, value: value}, initial, :initial) do
      validate(concept, constraints, :constraints)
    end
  end

  defp validate(concept, values, field) do
    Enum.reduce_while(values, {:ok, concept}, fn {name, value}, {:ok, concept} ->
      value = FeatureModel.canonicalize(concept.locale, name, value)

      case validate_constraint(concept, name, value) do
        :ok -> {:cont, {:ok, Map.update!(concept, field, &Map.put(&1, name, value))}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  @doc """
  Puts a constraint on the concept.

  ### Arguments

  * `concept` is a concept from `new/3`.

  * `name` is a feature name such as "number" or "definiteness".

  * `value` is the constraint value such as "plural".

  ### Returns

  * `{:ok, concept}` or `{:error, reason}` when the feature is
    unknown or the value is not valid for a bounded feature.

  ### Examples

      iex> {:ok, concept} = Localize.Inflection.Concept.new(:en, "light")
      iex> {:ok, concept} = Localize.Inflection.Concept.put_constraint(concept, :number, :plural)
      iex> Localize.Inflection.Concept.to_speakable_string(concept)
      "lights"

  """
  def put_constraint(%__MODULE__{} = concept, name, value) do
    name = Feature.to_internal(name)
    value = FeatureModel.canonicalize(concept.locale, name, Feature.to_internal(value))

    with :ok <- validate_constraint(concept, name, value) do
      {:ok, %{concept | constraints: Map.put(concept.constraints, name, value)}}
    end
  end

  defp validate_constraint(concept, name, value) do
    case FeatureModel.feature(concept.locale, name) do
      nil ->
        {:error, Localize.UnknownFeatureError.exception(feature: name, locale: concept.locale)}

      %{type: :bounded, values: values} ->
        if MapSet.member?(values, value) do
          :ok
        else
          {:error,
           Localize.InvalidValueError.exception(
             value: value,
             expected: :grammeme,
             allowed_values: Enum.sort(values),
             context: name
           )}
        end

      %{type: :unbounded} ->
        :ok
    end
  end

  @doc """
  Returns the value of a feature for this concept.

  A stored constraint takes precedence; otherwise the locale's
  default feature function computes the value from the (possibly
  inflected) display string.

  ### Returns

  * A speakable string, or nil when the feature has no value.

  ### Examples

      iex> {:ok, concept} = Localize.Inflection.Concept.new(:en, "light")
      iex> Localize.Inflection.Concept.feature_value(concept, :number)
      :singular

  """
  def feature_value(%__MODULE__{} = concept, name) do
    name = Feature.to_internal(name)

    value =
      case Map.get(concept.constraints, name) do
        nil ->
          with synthesizer when not is_nil(synthesizer) <- Synthesizer.for_locale(concept.locale),
               %DisplayValue{} = display_value <- display_value(concept, true) do
            synthesizer.feature_value(name, display_value, concept.constraints)
          end

        constraint ->
          constraint
      end

    Feature.to_public(concept.locale, name, value)
  end

  @doc """
  Returns true when the concept can be rendered with its
  constraints without guessing.

  Rendering without guessing includes the synthesizers' unchanged
  passthrough: a word the dictionary does not know may still render
  as itself, so `exists?/1` answers "does rendering produce
  something?", not "is the requested form attested in the
  dictionary?". Use `Localize.Inflection.known?/2` to test
  dictionary membership.

  ### Examples

      iex> {:ok, concept} = Localize.Inflection.Concept.new(:en, "cat", constraints: %{number: :plural})
      iex> Localize.Inflection.Concept.exists?(concept)
      true

  """
  def exists?(%__MODULE__{} = concept) do
    display_value(concept, false) != nil
  end

  @doc """
  Renders the concept with all constraints applied.

  The synthesizers may fall back to suffix-exemplar guessing for
  words the dictionary does not know. Setting the concept's
  `guess` field to false disables guessing: forms then change
  only through attested dictionary paths, and a failed render
  returns the value unchanged.

  ### Returns

  * A speakable string (a binary, or `{print, speak}` when the
    spoken form differs).

  ### Examples

      iex> {:ok, concept} = Localize.Inflection.Concept.new(:en, "cat", constraints: %{case: :genitive})
      iex> Localize.Inflection.Concept.to_speakable_string(concept)
      "cat’s"

  """
  def to_speakable_string(%__MODULE__{} = concept) do
    case display_value(concept, concept.guess) do
      nil ->
        concept.value
        |> DisplayValue.new(concept.initial)
        |> apply_speak(concept.constraints)
        |> DisplayValue.to_speakable_string()

      display_value ->
        DisplayValue.to_speakable_string(display_value)
    end
  end

  defp display_value(%__MODULE__{} = concept, guess?) do
    synthesizer = Synthesizer.for_locale(concept.locale)

    result =
      if synthesizer && map_size(without_speak(concept.constraints)) > 0 do
        display_data = [DisplayValue.new(concept.value, concept.initial)]
        synthesizer.display_value(display_data, concept.constraints, guess?)
      end

    case result do
      %DisplayValue{} = display_value ->
        apply_speak(display_value, concept.constraints)

      nil when guess? ->
        apply_speak(DisplayValue.new(concept.value, concept.initial), concept.constraints)

      nil ->
        nil
    end
  end

  defp without_speak(constraints), do: Map.delete(constraints, @speak)

  # An explicit speak constraint overrides any derived spoken form.
  defp apply_speak(display_value, constraints) do
    case Map.get(constraints, @speak) do
      nil ->
        display_value

      speak ->
        %{display_value | constraints: Map.put(display_value.constraints, @speak, speak)}
    end
  end
end
