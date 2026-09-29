defmodule Localize.Inflection.Concept do
  @moduledoc """
  An inflectable string with grammatical constraints.

  A concept wraps a word or phrase for a locale. Constraints (such
  as `number=plural` or `definiteness=definite`) are applied with
  `put_constraint/3`; grammatical properties are queried with
  `feature_value/2`; and `to_speakable_string/1` renders the phrase
  with all constraints applied.

  A concept can also carry forms of its own for sets of constraints,
  given as `:display_data` to `new/3`. It then renders as the first
  of its forms that holds every constraint put on it, and otherwise
  as the locale's rules inflect the phrase.

  This is the equivalent of the upstream `InflectableStringConcept`,
  and with display data of the upstream `SemanticConcept`.

  """

  import Localize.Utils.Helpers, only: [is_keyword_list: 1]

  alias Localize.Inflection.{
    Data,
    DisplayValue,
    Feature,
    FeatureModel,
    Locale,
    SpeakableString,
    Synthesizer
  }

  defstruct [:locale, :value, constraints: %{}, initial: %{}, display_data: [], guess: true]

  @type t :: %__MODULE__{
          locale: atom,
          value: SpeakableString.t(),
          constraints: %{optional(binary) => binary},
          initial: %{optional(binary) => binary},
          display_data: [{SpeakableString.t(), %{optional(binary) => binary}}],
          guess: boolean
        }

  @speak "speak"

  defguardp is_speakable(value)
            when is_binary(value) or
                   (is_tuple(value) and tuple_size(value) == 2 and is_binary(elem(value, 0)) and
                      is_binary(elem(value, 1)))

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

  * `:display_data` is a list of `{form, constraints}` entries, forms
    of the concept and the features each has, such as
    `{"octopodes", %{number: :plural}}`. A form is a binary or a
    `{print, speak}` tuple. The concept renders as the first form,
    starting with `value` and its `:initial` features, that holds
    every constraint put on it, and takes its features from that
    form; when no form does, the locale's rules inflect `value`.

  ### Returns

  * `{:ok, concept}` or `{:error, reason}` when the locale data is
    unavailable, or a constraint or display data entry is invalid.

  ### Examples

      iex> {:ok, concept} = Localize.Inflection.Concept.new(:en, "cat", constraints: %{number: :plural})
      iex> Localize.Inflection.Concept.to_speakable_string(concept)
      "cats"

      iex> {:error, error} = Localize.Inflection.Concept.new(:en, "cat", constraints: %{number: :dual})
      iex> error.value
      "dual"
      iex> error.allowed_values
      ["plural", "singular"]

      iex> display_data = [{"octopodes", %{number: :plural}}]
      iex> {:ok, concept} = Localize.Inflection.Concept.new(:en, "octopus", display_data: display_data)
      iex> {:ok, concept} = Localize.Inflection.Concept.put_constraint(concept, :number, :plural)
      iex> Localize.Inflection.Concept.to_speakable_string(concept)
      "octopodes"

  """
  def new(locale, value, options \\ [])

  def new(locale, value, options) when is_speakable(value) and is_keyword_list(options) do
    with :ok <- validate_value(value),
         {:ok, constraints} <- Feature.constraints(Keyword.get(options, :constraints, %{})),
         {:ok, initial} <- Feature.constraints(Keyword.get(options, :initial, %{})),
         {:ok, locale} <- Locale.resolve(locale),
         :ok <- Data.ensure_loaded(locale),
         {:ok, display_data} <- display_data(locale, Keyword.get(options, :display_data, [])),
         concept = %__MODULE__{locale: locale, value: value, display_data: display_data},
         {:ok, concept} <- validate(concept, initial, :initial) do
      validate(concept, constraints, :constraints)
    end
  end

  def new(_locale, _value, options) when not is_keyword_list(options),
    do: {:error, Localize.Utils.Helpers.invalid_options(options)}

  def new(_locale, value, _options),
    do: {:error, Localize.Utils.Helpers.invalid_value(value, "a word or phrase string")}

  # A binary that is not UTF-8 is no word, and the tokenizer's Unicode regular
  # expressions raise on it.
  defp validate_value({print, speak}) do
    with :ok <- validate_value(print), do: validate_value(speak)
  end

  defp validate_value(value) do
    if String.valid?(value),
      do: :ok,
      else: {:error, Localize.Utils.Helpers.invalid_value(value, "a UTF-8 word or phrase")}
  end

  defp validate(concept, values, field) do
    with {:ok, canonical} <- canonical_constraints(concept.locale, values) do
      {:ok, Map.update!(concept, field, &Map.merge(&1, canonical))}
    end
  end

  # Constraints in their canonical form, each checked against the
  # locale's feature model.
  defp canonical_constraints(locale, values) do
    Enum.reduce_while(values, {:ok, %{}}, fn {name, value}, {:ok, canonical} ->
      value = FeatureModel.canonicalize(locale, name, value)

      case validate_constraint(locale, name, value) do
        :ok -> {:cont, {:ok, Map.put(canonical, name, value)}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  # Display data is a list of `{form, constraints}` entries whose
  # constraints are checked as `:initial` is.
  defp display_data(locale, entries) when is_list(entries) do
    entries
    |> Enum.reduce_while({:ok, []}, fn entry, {:ok, forms} ->
      case display_form(locale, entry) do
        {:ok, form} -> {:cont, {:ok, [form | forms]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, forms} -> {:ok, Enum.reverse(forms)}
      {:error, _reason} = error -> error
    end
  end

  defp display_data(_locale, entries) do
    {:error,
     Localize.Utils.Helpers.invalid_value(entries, "a list of {form, constraints} entries")}
  end

  defp display_form(locale, {form, constraints}) when is_speakable(form) do
    with {:ok, constraints} <- Feature.constraints(constraints),
         {:ok, constraints} <- canonical_constraints(locale, constraints) do
      {:ok, {form, constraints}}
    end
  end

  defp display_form(_locale, entry) do
    {:error, Localize.Utils.Helpers.invalid_value(entry, "a {form, constraints} entry")}
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

    with :ok <- validate_constraint(concept.locale, name, value) do
      {:ok, %{concept | constraints: Map.put(concept.constraints, name, value)}}
    end
  end

  def put_constraint(concept, _name, _value),
    do: {:error, Localize.Utils.Helpers.invalid_value(concept, "a Localize.Inflection.Concept")}

  defp validate_constraint(locale, name, value) do
    case FeatureModel.feature(locale, name) do
      nil ->
        {:error, Localize.UnknownFeatureError.exception(feature: name, locale: locale)}

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

  A stored constraint takes precedence. A concept with display data
  next takes the value its rendered form has; otherwise the locale's
  default feature function computes the value from the (possibly
  inflected) display string.

  ### Arguments

  * `concept` is a concept from `new/3`.

  * `name` is a feature name such as `:number` or `"gender"`.

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
        nil -> derived_feature_value(concept, name)
        constraint -> constraint
      end

    Feature.to_public(concept.locale, name, value)
  end

  def feature_value(_concept, _name), do: nil

  # A form from display data carries some of its own features, which
  # upstream's SemanticConcept reads first; the rest, and every
  # feature of a plain phrase, come from the locale's synthesizer.
  defp derived_feature_value(concept, name) do
    with %DisplayValue{} = display_value <- display_value(concept, true) do
      own_value =
        if concept.display_data != [], do: DisplayValue.feature_value(display_value, name)

      own_value || synthesized_feature_value(concept, name, display_value)
    end
  end

  defp synthesized_feature_value(concept, name, display_value) do
    case Synthesizer.for_locale(concept.locale) do
      nil -> nil
      synthesizer -> synthesizer.feature_value(name, display_value, concept.constraints)
    end
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

  def exists?(_concept), do: false

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

  def to_speakable_string(concept),
    do: {:error, Localize.Utils.Helpers.invalid_value(concept, "a Localize.Inflection.Concept")}

  defp display_value(%__MODULE__{display_data: []} = concept, guess?) do
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

  # A concept with display data renders as the first of its forms that
  # holds every constraint, and otherwise as the locale's rules derive a
  # form from them, as upstream's SemanticConcept does. The speak
  # constraint takes no part in the match; it overrides the spoken form
  # of whatever renders.
  defp display_value(%__MODULE__{} = concept, guess?) do
    forms = display_forms(concept)
    constraints = without_speak(concept.constraints)

    case Enum.find(forms, &holds_all?(&1, constraints)) do
      %DisplayValue{} = form -> apply_speak(form, concept.constraints)
      nil -> derived_display_value(concept, forms, guess?)
    end
  end

  defp display_forms(concept) do
    [
      DisplayValue.new(concept.value, concept.initial)
      | Enum.map(concept.display_data, fn {form, constraints} ->
          DisplayValue.new(form, constraints)
        end)
    ]
  end

  defp holds_all?(%DisplayValue{constraints: form_constraints}, constraints) do
    Enum.all?(constraints, fn {name, value} -> Map.get(form_constraints, name) == value end)
  end

  # The synthesizers inflect the first form, as upstream's display
  # functions do.
  defp derived_display_value(concept, forms, guess?) do
    result =
      case Synthesizer.for_locale(concept.locale) do
        nil -> nil
        synthesizer -> synthesizer.display_value(forms, concept.constraints, guess?)
      end

    case result do
      %DisplayValue{} = display_value -> apply_speak(display_value, concept.constraints)
      nil when guess? -> apply_speak(hd(forms), concept.constraints)
      nil -> nil
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
