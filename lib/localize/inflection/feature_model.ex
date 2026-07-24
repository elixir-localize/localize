defmodule Localize.Inflection.FeatureModel do
  @moduledoc false

  # The per-locale registry of semantic features, built from the
  # grammar.xml definitions in the locale artifact.
  #
  # Each grammatical category becomes a bounded, aliased feature
  # (so a bare grammeme like "plural" resolves to `number=plural`).
  # Each display feature (defArticle and friends) becomes a bounded
  # or unbounded feature depending on whether it declares values.

  alias Localize.Inflection.Data

  # Deprecated grammeme names accepted as aliases, as upstream:
  # the Russian synthesizer treats ablative and locative as the
  # instrumental and prepositional cases.
  @grammeme_aliases %{
    ru: %{"case" => %{"ablative" => "instrumental", "locative" => "prepositional"}}
  }

  @doc """
  Canonicalizes a grammeme value, resolving deprecated per-locale
  aliases (Russian ablative/locative).

  """
  def canonicalize(locale, feature, value) do
    @grammeme_aliases
    |> get_in([locale, feature, value])
    |> Kernel.||(value)
  end

  @doc """
  Returns the feature definition for `name`, or nil.

  The definition is `%{name:, type: :bounded | :unbounded, values:}`
  where values is a MapSet (empty for unbounded features).

  """
  def feature(locale, name) do
    Map.get(features(locale), name)
  end

  @doc """
  Returns all features for the locale as a map of name to
  definition.

  """
  def features(locale) do
    key = {__MODULE__, locale}

    case :persistent_term.get(key, nil) do
      nil ->
        built = build(locale)
        :persistent_term.put(key, built)
        built

      built ->
        built
    end
    |> Map.fetch!(:features)
  end

  @doc """
  Resolves a bare grammeme value to `{category_feature_name, value}`
  using the category aliases, or nil.

  """
  def alias_for(locale, value) do
    key = {__MODULE__, locale}

    case :persistent_term.get(key, nil) do
      nil ->
        built = build(locale)
        :persistent_term.put(key, built)
        built

      built ->
        built
    end
    |> Map.fetch!(:aliases)
    |> Map.get(value)
  end

  defp build(locale) do
    artifact_features = Data.metadata!(locale).features

    category_features =
      Map.new(artifact_features.categories, fn {category, %{grammemes: grammemes}} ->
        {category, %{name: category, type: :bounded, values: MapSet.new(grammemes)}}
      end)

    display_features =
      Map.new(artifact_features.features, fn {name, %{values: values}} ->
        type = if values == [], do: :unbounded, else: :bounded
        {name, %{name: name, type: type, values: MapSet.new(values)}}
      end)

    # Only aliasable categories contribute aliases; when two
    # aliasable categories share a grammeme, the first category in
    # name order wins, as upstream.
    aliases =
      artifact_features.categories
      |> Enum.sort_by(fn {category, _definition} -> category end)
      |> Enum.reduce(%{}, fn
        {category, %{grammemes: grammemes, aliasable: true}}, aliases ->
          Enum.reduce(grammemes, aliases, fn grammeme, aliases ->
            Map.put_new(aliases, grammeme, {category, grammeme})
          end)

        {_category, %{aliasable: false}}, aliases ->
          aliases
      end)

    %{features: Map.merge(category_features, display_features), aliases: aliases}
  end
end
