defmodule Localize.Inflection.Quantify do
  @moduledoc """
  Quantified noun phrases: a number joined with a noun that agrees
  with it grammatically.

  This is the port of the upstream `CommonConceptFactory` quantify
  feature. The plural category drives a `number` constraint on the
  concept (singular, dual or plural where the language has them),
  per-language rules adjust the grammatical case (Slavic numeral
  government, the Arabic counted-noun cases), and a per-language
  join places the number, noun and any measure word (CJK
  classifiers, Thai).

  The number arrives pre-formatted and the plural category is
  resolved through Localize's own plural rules (or supplied per call): number
  formatting and plural selection remain with the caller, which
  for Localize means its own formatting and plural rules.

  """

  alias Localize.Inflection.{Concept, Locale, SpeakableString}
  alias Localize.Inflection.Quantify.{Arabic, Base, Finnish, Hebrew, Join, Slavic}

  # Locale (internal form) to quantify implementation. Languages
  # not listed use the base implementation, as upstream. The zh_HK
  # routing to the Cantonese factory mirrors the upstream provider.
  @factories %{
    "ar" => {Arabic, nil},
    "ru" =>
      {Slavic, %{few: :paucal_governed, many: :governed_plural, other: :fraction_genitive_sg}},
    "uk" =>
      {Slavic, %{few: :paucal_plural, many: :governed_plural, other: :fraction_genitive_sg}},
    "pl" =>
      {Slavic,
       %{
         few: :paucal_plural,
         many: :governed_plural,
         other: :fraction_genitive_sg,
         adjust_case: :pl
       }},
    "cs" =>
      {Slavic, %{few: :paucal_plural, many: :fraction_genitive_sg, other: :governed_plural}},
    "sk" =>
      {Slavic, %{few: :paucal_plural, many: :fraction_genitive_sg, other: :governed_plural}},
    "sr" =>
      {Slavic,
       %{few: :paucal_governed, many: :governed_plural, other: :governed_plural, bcs: true}},
    "hr" =>
      {Slavic,
       %{few: :paucal_governed, many: :governed_plural, other: :governed_plural, bcs: true}},
    "he" => {Hebrew, nil},
    "fi" => {Finnish, nil},
    "it" => {Join, %{join: :no_space_for_one}},
    "ml" => {Join, %{join: :noun_first_for_one}},
    "ja" => {Join, %{join: :number_measure_noun}},
    "zh" => {Join, %{join: :number_measure_noun}},
    "yue" => {Join, %{join: :number_measure_noun}},
    "ko" => {Join, %{join: :korean}},
    "th" => {Join, %{join: :noun_number_measure}},
    "zh_HK" => {Join, %{join: :number_measure_noun}}
  }

  # Languages whose cardinal plural rules define a single category
  # (CLDR: only "other"); the base entry point then renders the
  # noun unconstrained. Derived from the CLDR cardinal keyword
  # sets for the supported languages.
  @single_category_locales ~w(id ja ko ms th vi yue zh zh_HK)

  @doc """
  Quantifies a concept with a pre-formatted number.

  ### Arguments

  * `locale` is a locale atom or string; it selects the language's
    quantification rules and may be more specific than the
    concept's locale (`:"zh-HK"` selects the Cantonese classifier
    join).

  * `formatted_number` is the formatted number as a speakable
    string (binary or `{print, speak}`).

  * `concept` is a `Localize.Inflection.Concept`.

  * `options` is a keyword list of options.

  ### Options

  * `:plural` is the CLDR plural category of the number; when
    absent it is selected by Localize's plural rules from the
    `:number` option.

  * `:number` is the numeric value, used to resolve the plural
    category via the provider and, for Serbo-Croatian, to detect
    fractions (which take the genitive singular).

  ### Returns

  * `{:ok, speakable}` with the quantified phrase, or
    `{:error, reason}`.

  ### Examples

      iex> {:ok, concept} = Localize.Inflection.Concept.new(:en, "kilometer")
      iex> Localize.Inflection.Quantify.quantify_formatted(:en, "2", concept, plural: :other)
      {:ok, "2 kilometers"}

      iex> {:ok, concept} = Localize.Inflection.Concept.new(:ru, "час")
      iex> Localize.Inflection.Quantify.quantify_formatted(:ru, "2", concept, plural: :few)
      {:ok, "2 часа"}

  """
  def quantify_formatted(locale, formatted_number, %Concept{} = concept, options \\ []) do
    internal = Locale.normalize(locale)
    number = Keyword.get(options, :number)

    with {:ok, category} <- resolve_category(internal, number, options) do
      {module, config} = factory(internal)

      state = %{
        config: config,
        concept: concept,
        number: number,
        single_category?: single_category?(internal, options)
      }

      {:ok, module.quantify_formatted(formatted_number, category, state)}
    end
  end

  @categories [:zero, :one, :two, :few, :many, :other]

  # The category comes from the :plural option, or from Localize's
  # own plural rules when a numeric value was given.
  defp resolve_category(internal, number, options) do
    case Keyword.get(options, :plural) do
      nil when is_nil(number) ->
        {:error, :no_plural_category}

      nil ->
        bcp47 = String.replace(internal, "_", "-")

        case Localize.Number.PluralRule.plural_type(number, locale: bcp47) do
          category when category in @categories -> {:ok, category}
          {:error, _reason} = error -> error
        end

      category when category in @categories ->
        {:ok, category}

      other ->
        {:error, {:invalid_plural_category, other}}
    end
  end

  defp factory(internal) do
    Map.get(@factories, internal) ||
      Map.get(@factories, Locale.parent(internal)) ||
      {Base, nil}
  end

  defp single_category?(internal, options) do
    case Keyword.get(options, :plural_categories) do
      nil ->
        internal in @single_category_locales or
          Locale.parent(internal) in @single_category_locales

      categories ->
        length(categories) <= 1
    end
  end

  @doc false
  # The measure word is an explicit constraint, never a computed
  # feature value, as upstream.
  def measure_word(%Concept{} = concept) do
    Map.get(concept.constraints, "measure", "")
  end

  @doc false
  # Feature values as internal strings for factory logic; the
  # public API returns atoms.
  def feature_print(%Concept{} = concept, feature) do
    case Concept.feature_value(concept, feature) do
      nil -> ""
      atom when is_atom(atom) -> Atom.to_string(atom)
      other -> SpeakableString.print(other)
    end
  end

  @doc false
  # Constrains and renders; an invalid constraint or failed render
  # returns nil so callers fall back, mirroring the upstream
  # nil-render fallbacks.
  def constrained_render(%Concept{} = concept, constraints) do
    constraints
    |> Enum.reduce_while({:ok, concept}, fn {feature, value}, {:ok, concept} ->
      case Concept.put_constraint(concept, feature, value) do
        {:ok, concept} -> {:cont, {:ok, concept}}
        {:error, _reason} -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, constrained} -> Concept.to_speakable_string(constrained)
      :error -> nil
    end
  end
end
