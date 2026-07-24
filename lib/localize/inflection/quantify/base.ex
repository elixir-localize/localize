defmodule Localize.Inflection.Quantify.Base do
  @moduledoc false

  # The base quantify implementation, ported from
  # `CommonConceptFactoryImpl`: map the plural category to a
  # number constraint (guarded by the language's bounded values),
  # render, and join as "number SPACE noun". Languages with a
  # single plural category render the noun unconstrained with the
  # category forced to :other, as upstream.

  alias Localize.Inflection.{Concept, FeatureModel, Quantify, SpeakableString}

  def quantify_formatted(formatted_number, category, state) do
    if state.single_category? do
      quantify_type(formatted_number, :other, true, state, &join/4)
    else
      quantify_type(formatted_number, category, false, state, &join/4)
    end
  end

  @doc false
  # The shared quantifyType: constrain number by category (ONE ->
  # singular, TWO -> dual, everything else -> plural), skipping
  # the constraint when the language does not bound that value;
  # fall back to the unconstrained render when the constrained
  # render fails.
  def quantify_type(formatted_number, category, use_default?, state, join) do
    concept = state.concept

    noun =
      if use_default? do
        Concept.to_speakable_string(concept)
      else
        type = number_type(category)

        constrained =
          if bounded_number?(concept.locale, type) do
            Quantify.constrained_render(concept, [{"number", type}])
          else
            Concept.to_speakable_string(concept)
          end

        constrained || Concept.to_speakable_string(concept)
      end

    join.(formatted_number, noun, Quantify.measure_word(concept), category)
  end

  @doc false
  def number_type(:one), do: "singular"
  def number_type(:two), do: "dual"
  def number_type(_category), do: "plural"

  @doc false
  def bounded_number?(locale, type) do
    case FeatureModel.feature(locale, "number") do
      %{type: :bounded, values: values} -> MapSet.member?(values, type)
      _other -> false
    end
  end

  @doc false
  # Number first, single space, noun; measure word ignored.
  def join(formatted_number, noun, _measure_word, _category) do
    formatted_number |> SpeakableString.concat(" ") |> SpeakableString.concat(noun)
  end
end
