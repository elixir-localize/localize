defmodule Localize.Inflection.DataGen.Features do
  @moduledoc false

  # Parses the upstream `features/grammar.xml` document that defines,
  # for each language, its grammatical categories (with their
  # grammemes) and its display features (such as `defArticle` and
  # `indefArticle` with their surface values).
  #
  # The `<common>` section applies to every language and is merged
  # into each language's definition.

  @doc """
  Parses `grammar.xml` returning a map of language id to
  `%{categories:, features:}`.

  Categories map a category name to
  `%{grammemes: [name], aliasable: boolean}` in document order.
  Only aliasable categories let a bare grammeme ("plural") resolve
  to its category; `aliasable="false"` categories (numberPronoun
  and friends) require an explicit `name=value` reference. Features
  map a feature name to `%{default:, values: [value]}`.

  """
  def parse_file(path) do
    initial_state = %{
      languages: %{},
      language: nil,
      categories: %{},
      category: nil,
      grammemes: [],
      features: %{},
      feature: nil,
      values: [],
      common: nil
    }

    # grammar.xml declares a DOCTYPE referencing grammar.dtd; OTP 26
    # fatals when the external DTD cannot be opened, so skip it —
    # the grammemes are read from the elements, not validated.
    {:ok, state, _rest} =
      :xmerl_sax_parser.file(String.to_charlist(path), [
        :skip_external_dtd,
        event_fun: &handle_event/3,
        event_state: initial_state
      ])

    common = state.common || %{categories: %{}, features: %{}}

    Map.new(state.languages, fn {language, definition} ->
      # A language category with the same name as a common category
      # extends it (ru pos adds adposition to the common pos set);
      # the first-inserted (common) aliasable flag wins, as
      # upstream.
      categories =
        Map.merge(common.categories, definition.categories, fn _name, common_cat, lang_cat ->
          %{
            grammemes: Enum.uniq(common_cat.grammemes ++ lang_cat.grammemes),
            aliasable: common_cat.aliasable
          }
        end)

      merged = %{
        categories: categories,
        features: Map.merge(common.features, definition.features)
      }

      {language, merged}
    end)
  end

  defp handle_event({:startElement, _uri, ~c"common", _qname, _attributes}, _location, state) do
    %{state | language: :common, categories: %{}, features: %{}}
  end

  defp handle_event({:startElement, _uri, ~c"language", _qname, attributes}, _location, state) do
    %{state | language: attribute_value(attributes, ~c"id"), categories: %{}, features: %{}}
  end

  defp handle_event({:startElement, _uri, ~c"category", _qname, attributes}, _location, state) do
    category = %{
      name: attribute_value(attributes, ~c"name"),
      aliasable: attribute_value(attributes, ~c"aliasable") != "false"
    }

    %{state | category: category, grammemes: []}
  end

  defp handle_event({:startElement, _uri, ~c"grammeme", _qname, attributes}, _location, state) do
    if state.category do
      %{state | grammemes: [attribute_value(attributes, ~c"name") | state.grammemes]}
    else
      state
    end
  end

  defp handle_event({:startElement, _uri, ~c"feature", _qname, attributes}, _location, state) do
    name = attribute_value(attributes, ~c"name")
    default = attribute_value(attributes, ~c"default")
    %{state | feature: %{name: name, default: default}, values: []}
  end

  defp handle_event({:startElement, _uri, ~c"value", _qname, attributes}, _location, state) do
    if state.feature do
      %{state | values: [attribute_value(attributes, ~c"result") | state.values]}
    else
      state
    end
  end

  defp handle_event({:endElement, _uri, ~c"category", _qname}, _location, state) do
    category = %{grammemes: Enum.reverse(state.grammemes), aliasable: state.category.aliasable}
    categories = Map.put(state.categories, state.category.name, category)
    %{state | categories: categories, category: nil, grammemes: []}
  end

  defp handle_event({:endElement, _uri, ~c"feature", _qname}, _location, state) do
    feature = %{default: state.feature.default, values: Enum.reverse(state.values)}
    features = Map.put(state.features, state.feature.name, feature)
    %{state | features: features, feature: nil, values: []}
  end

  defp handle_event({:endElement, _uri, ~c"common", _qname}, _location, state) do
    %{state | common: %{categories: state.categories, features: state.features}, language: nil}
  end

  defp handle_event({:endElement, _uri, ~c"language", _qname}, _location, state) do
    definition = %{categories: state.categories, features: state.features}
    languages = Map.put(state.languages, state.language, definition)
    %{state | languages: languages, language: nil}
  end

  defp handle_event(_event, _location, state) do
    state
  end

  defp attribute_value(attributes, name) do
    Enum.find_value(attributes, fn
      {_uri, _prefix, ^name, value} -> List.to_string(value)
      _other -> nil
    end)
  end
end
