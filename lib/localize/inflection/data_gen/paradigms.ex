defmodule Localize.Inflection.DataGen.Paradigms do
  @moduledoc false

  # Parses the upstream `inflectional_XX.xml` inflection pattern
  # (paradigm) files.
  #
  # Each `<pattern>` has a hexadecimal `name` referenced from the
  # lexicon (`inflection=<name>`), one or more `<pos>` elements, an
  # optional `<suffix>` (the lemma suffix), and an `<inflections>`
  # list. Each `<inflection>` carries grammeme values as attribute
  # values (the attribute names are grammatical categories and are
  # not stored) and a template `<t><stem/>suffix</t>`.

  @doc """
  Parses an `inflectional_XX.xml` file into a list of pattern maps.

  Each pattern is `%{name:, pos:, lemma_suffix:, inflections:}`
  where inflections are `{grammeme_values, suffix}` tuples in
  document order.

  """
  def parse_file(path) do
    initial_state = %{
      patterns: [],
      pattern: nil,
      element: nil,
      inflection: nil,
      text: ""
    }

    {:ok, state, _rest} =
      :xmerl_sax_parser.file(String.to_charlist(path),
        event_fun: &handle_event/3,
        event_state: initial_state
      )

    Enum.reverse(state.patterns)
  end

  defp handle_event({:startElement, _uri, ~c"pattern", _qname, attributes}, _location, state) do
    name = attribute_value(attributes, ~c"name")
    %{state | pattern: %{name: name, pos: [], lemma_suffix: "", inflections: []}}
  end

  defp handle_event({:startElement, _uri, element, _qname, _attributes}, _location, state)
       when element in [~c"pos", ~c"suffix", ~c"t"] do
    %{state | element: List.to_string(element), text: ""}
  end

  defp handle_event({:startElement, _uri, ~c"inflection", _qname, attributes}, _location, state) do
    grammemes = for {_uri, _prefix, _name, value} <- attributes, do: List.to_string(value)
    %{state | inflection: grammemes}
  end

  defp handle_event({:startElement, _uri, ~c"stem", _qname, _attributes}, _location, state) do
    # Text after <stem/> within <t> is the inflection suffix.
    %{state | text: ""}
  end

  defp handle_event({:characters, characters}, _location, %{element: element} = state)
       when element in ["pos", "suffix", "t"] do
    %{state | text: state.text <> List.to_string(characters)}
  end

  defp handle_event({:endElement, _uri, ~c"pos", _qname}, _location, state) do
    pattern = Map.update!(state.pattern, :pos, &[state.text | &1])
    %{state | pattern: pattern, element: nil}
  end

  defp handle_event({:endElement, _uri, ~c"suffix", _qname}, _location, state) do
    %{state | pattern: %{state.pattern | lemma_suffix: state.text}, element: nil}
  end

  defp handle_event({:endElement, _uri, ~c"t", _qname}, _location, state) do
    inflection = {state.inflection, state.text}
    pattern = Map.update!(state.pattern, :inflections, &[inflection | &1])
    %{state | pattern: pattern, element: nil, inflection: nil}
  end

  defp handle_event({:endElement, _uri, ~c"pattern", _qname}, _location, state) do
    pattern = %{
      state.pattern
      | pos: Enum.reverse(state.pattern.pos),
        inflections: Enum.reverse(state.pattern.inflections)
    }

    %{state | patterns: [pattern | state.patterns], pattern: nil}
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
