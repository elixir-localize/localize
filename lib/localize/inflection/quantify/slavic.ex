defmodule Localize.Inflection.Quantify.Slavic do
  @moduledoc false

  # The shared Slavic quantification, ported from
  # `SlavicCommonConceptFactory`: the number governs the counted
  # noun's number and case (2 часа genitive singular paucal, 5
  # часов genitive plural, fractions genitive singular). The
  # per-language configuration selects the agreement mode for the
  # few/many/other categories; Polish adds accusative case
  # adjustment and Serbo-Croatian routes every fraction to the
  # genitive singular and forces the genitive on governed plurals.

  alias Localize.Inflection.{Concept, Quantify}
  alias Localize.Inflection.Quantify.Base

  def quantify_formatted(formatted_number, category, state) do
    cond do
      Map.get(state.config, :bcs, false) and fraction?(state.number) ->
        # BCS decimals spread across one/few/other, so the category
        # alone cannot identify a fraction; any non-integer takes
        # the genitive singular.
        resolve_quantity(formatted_number, state, :fraction_genitive_sg, category)

      state.single_category? ->
        Base.quantify_type(formatted_number, :other, true, state, &Base.join/4)

      true ->
        resolve_quantity(formatted_number, state, agreement(category, state.config), category)
    end
  end

  defp fraction?(number) when is_float(number), do: number != Float.floor(number)
  defp fraction?(_number), do: false

  # ONE -> singular base; FEW/MANY from config; OTHER and any
  # other category (zero/two never occur for these locales) take
  # the other mode.
  defp agreement(:one, _config), do: :singular_base
  defp agreement(:few, config), do: config.few
  defp agreement(:many, config), do: config.many
  defp agreement(_category, config), do: config.other

  defp resolve_quantity(formatted_number, state, mode, category) do
    concept = state.concept
    config = state.config
    base_case = Quantify.feature_print(concept, "case")

    {number_constraint, case_constraint} =
      case mode do
        :singular_base ->
          {"singular", adjust_case(category, concept, base_case, config)}

        :paucal_governed ->
          animacy = Quantify.feature_print(concept, "animacy")
          number = if direct_case?(base_case, animacy), do: "singular", else: "plural"
          {number, gated_genitive(base_case, mode, config)}

        :paucal_plural ->
          {"plural", adjust_case(category, concept, base_case, config)}

        :governed_plural ->
          {"plural", gated_genitive(base_case, mode, config)}

        :fraction_genitive_sg ->
          {"singular", "genitive"}
      end

    constraints =
      [{"number", number_constraint}] ++
        if(case_constraint, do: [{"case", case_constraint}], else: [])

    noun =
      Quantify.constrained_render(concept, constraints) ||
        Concept.to_speakable_string(concept)

    Base.join(formatted_number, noun, "", category)
  end

  # The 2-4 paucal looks like a genitive singular only in the
  # direct cases: nominative (or no case) and the inanimate
  # accusative.
  defp direct_case?(base_case, animacy) do
    base_case in ["", "nominative"] or (base_case == "accusative" and animacy == "inanimate")
  end

  # The genitive of government applies only over direct-ish base
  # cases; oblique cases keep their own form — except that BCS
  # forces the genitive on every governed plural.
  defp gated_genitive(base_case, mode, config) do
    cond do
      Map.get(config, :bcs, false) and mode == :governed_plural -> "genitive"
      base_case in ["", "nominative", "accusative"] -> "genitive"
      true -> nil
    end
  end

  # Only Polish adjusts the case, and only over an accusative base.
  defp adjust_case(category, concept, "accusative", %{adjust_case: :pl}) do
    gender = Quantify.feature_print(concept, "gender")

    case category do
      :one ->
        case gender do
          "neuter" ->
            "nominative"

          "masculine" ->
            if Quantify.feature_print(concept, "animacy") in ["human", "animate"] do
              "genitive"
            else
              "nominative"
            end

          _other ->
            nil
        end

      :few ->
        if gender == "masculine" and Quantify.feature_print(concept, "animacy") == "human" do
          "genitive"
        else
          "nominative"
        end

      _other ->
        nil
    end
  end

  defp adjust_case(_category, _concept, _base_case, _config), do: nil
end
