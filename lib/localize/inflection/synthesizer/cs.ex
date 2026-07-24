defmodule Localize.Inflection.Synthesizer.Cs do
  @moduledoc false

  # The Czech grammar synthesizer, ported from
  # `CsGrammarSynthesizer`: four dictionary category lookups plus
  # the shared prefixed display function with the "nej" superlative
  # prefix.

  @behaviour Localize.Inflection.Synthesizer

  alias Localize.Inflection.{Lookup, PrefixedDisplay}

  @locale :cs

  @cases ~w(nominative genitive dative accusative instrumental locative vocative)

  @priorities [
    ["noun", "adjective"],
    @cases,
    ["singular", "plural"],
    ["masculine", "feminine", "neuter"],
    ["inanimate", "animate"]
  ]

  @lookups %{
    "gender" => ["masculine", "feminine", "neuter"],
    "number" => ["singular", "plural"],
    "case" => @cases,
    "animacy" => ["animate", "inanimate", "human"]
  }

  @impl true
  def feature_value(feature, display_value, _constraints) when is_map_key(@lookups, feature) do
    case Lookup.determine(@locale, display_value.display_string, Map.fetch!(@lookups, feature)) do
      "" -> nil
      value -> value
    end
  end

  def feature_value(_feature, _display_value, _constraints), do: nil

  @impl true
  def display_value(display_data, constraints, _guess?) do
    PrefixedDisplay.display_value(@locale, display_data, constraints,
      priorities: @priorities,
      extra_feature: "animacy",
      prefix: {"nej", "adjective"}
    )
  end
end
