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

  import Localize.Utils.Helpers, only: [is_keyword_list: 1]

  alias Localize.Inflection.{Concept, Locale, SpeakableString}
  alias Localize.Inflection.Quantify.{Arabic, Base, Finnish, Hebrew, Join, Numeral, Slavic}

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
  def quantify_formatted(locale, formatted_number, concept, options \\ [])

  def quantify_formatted(locale, formatted_number, %Concept{} = concept, options)
      when (is_atom(locale) or is_binary(locale) or is_struct(locale, Localize.LanguageTag)) and
             (is_binary(formatted_number) or
                (is_tuple(formatted_number) and tuple_size(formatted_number) == 2 and
                   is_binary(elem(formatted_number, 0)) and is_binary(elem(formatted_number, 1)))) and
             is_keyword_list(options) do
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

  def quantify_formatted(_locale, _formatted_number, _concept, options)
      when not is_keyword_list(options),
      do: {:error, Localize.Utils.Helpers.invalid_options(options)}

  def quantify_formatted(locale, _formatted_number, _concept, _options)
      when not is_atom(locale) and not is_binary(locale) and
             not is_struct(locale, Localize.LanguageTag),
      do: {:error, Localize.InvalidLocaleError.exception(locale_id: locale)}

  def quantify_formatted(_locale, formatted_number, %Concept{}, _options) do
    {:error,
     Localize.Utils.Helpers.invalid_value(formatted_number, "a formatted number as a string")}
  end

  def quantify_formatted(_locale, _formatted_number, concept, _options),
    do: {:error, Localize.Utils.Helpers.invalid_value(concept, "a Localize.Inflection.Concept")}

  @doc """
  Quantifies a concept with a number, writing the number as the
  language writes the number of a quantity.

  The number is written in the locale's digits. Where the language's
  numbers agree with the noun (in gender, and in case in German,
  Finnish and the Slavic languages), its spoken form is the words that
  agree; Hebrew and Italian write the smallest numbers as words. The
  result is then joined as `quantify_formatted/4` joins it.

  ### Arguments

  * `locale` is a locale atom or string; it selects the language's
    quantification rules.

  * `number` is an integer, a float or a `Decimal`.

  * `concept` is a `Localize.Inflection.Concept`.

  * `options` is a keyword list of options.

  ### Options

  * `:plural` is the CLDR plural category of the number; when absent
    it is selected from `number` by Localize's plural rules.

  ### Returns

  * `{:ok, speakable}` with the quantified phrase, or
    `{:error, reason}`.

  ### Examples

      iex> {:ok, concept} = Localize.Inflection.Concept.new(:es, "niña")
      iex> Localize.Inflection.Quantify.quantify(:es, 1, concept)
      {:ok, {"1 niña", "una niña"}}

      iex> {:ok, concept} = Localize.Inflection.Concept.new(:en, "kilometer")
      iex> Localize.Inflection.Quantify.quantify(:en, 2, concept)
      {:ok, "2 kilometers"}

  """
  def quantify(locale, number, concept, options \\ [])

  def quantify(locale, number, %Concept{} = concept, options)
      when (is_number(number) or is_struct(number, Decimal)) and is_keyword_list(options) do
    with {:ok, formatted} <- formatted_number(locale, number, concept) do
      quantify_formatted(locale, formatted, concept, Keyword.put(options, :number, number))
    end
  end

  def quantify(_locale, number, %Concept{}, options) when is_keyword_list(options),
    do: {:error, Localize.Utils.Helpers.invalid_value(number, "a number")}

  def quantify(_locale, _number, %Concept{}, options),
    do: {:error, Localize.Utils.Helpers.invalid_options(options)}

  def quantify(_locale, _number, concept, _options),
    do: {:error, Localize.Utils.Helpers.invalid_value(concept, "a Localize.Inflection.Concept")}

  @doc false
  # The number as the language writes the number of a quantity of the
  # concept, as a speakable string.
  def formatted_number(locale, number, %Concept{} = concept) do
    language = locale |> Locale.normalize() |> String.split("_") |> hd()
    Numeral.formatted(language, locale, number, concept)
  end

  @categories [:zero, :one, :two, :few, :many, :other]

  # The category comes from the :plural option, or from Localize's
  # own plural rules when a numeric value was given.
  defp resolve_category(internal, number, options) do
    case Keyword.get(options, :plural) do
      nil when is_nil(number) ->
        {:error, Localize.NoPluralCategoryError.exception(locale: internal)}

      nil ->
        bcp47 = String.replace(internal, "_", "-")

        case Localize.Number.PluralRule.plural_type(number, locale: bcp47) do
          category when category in @categories -> {:ok, category}
          {:error, _reason} = error -> error
        end

      category when category in @categories ->
        {:ok, category}

      other ->
        {:error,
         Localize.InvalidValueError.exception(
           value: other,
           expected: :plural_category,
           allowed_values: @categories
         )}
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
        not match?([_, _ | _], categories)
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
