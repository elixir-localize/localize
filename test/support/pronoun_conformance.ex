defmodule Localize.Inflection.PronounConformance do
  @moduledoc false

  # Parses and runs the upstream data-driven pronoun test files
  # (`test/resources/inflection/dialog/pronoun/XX.xml`).

  alias Localize.Inflection.{Concept, PronounConcept, SpeakableString}

  @dependency_prefix "dependency="
  @dependency_sound "dependency=sound"

  @doc """
  Parses an upstream pronoun inflectionTest XML file into a list of
  case maps.

  """
  def parse_file(path) do
    initial_state = %{
      cases: [],
      element: nil,
      case: nil,
      text: ""
    }

    {:ok, state, _rest} =
      :xmerl_sax_parser.file(String.to_charlist(path),
        event_fun: &handle_event/3,
        event_state: initial_state
      )

    Enum.reverse(state.cases)
  end

  defp handle_event({:startElement, _uri, ~c"test", _qname, _attributes}, _location, state) do
    test_case = %{
      constraints: %{},
      source: "",
      queries: %{},
      expected: ""
    }

    %{state | case: test_case}
  end

  defp handle_event({:startElement, _uri, ~c"source", _qname, attributes}, _location, state) do
    test_case = %{state.case | constraints: attribute_map(attributes)}
    %{state | case: test_case, element: :source, text: ""}
  end

  defp handle_event({:startElement, _uri, ~c"codependent", _qname, attributes}, _location, state) do
    dependencies =
      Map.new(attribute_map(attributes), fn {name, value} ->
        {@dependency_prefix <> name, value}
      end)

    test_case = %{state.case | constraints: Map.merge(dependencies, state.case.constraints)}
    %{state | case: test_case, element: nil, text: ""}
  end

  defp handle_event({:startElement, _uri, ~c"result", _qname, attributes}, _location, state) do
    test_case = %{state.case | queries: attribute_map(attributes)}
    %{state | case: test_case, element: :result, text: ""}
  end

  defp handle_event({:startElement, _uri, ~c"text", _qname, attributes}, _location, state) do
    attributes = attribute_map(attributes)

    speakable =
      SpeakableString.new(Map.fetch!(attributes, "print"), Map.fetch!(attributes, "speak"))

    test_case =
      case state.element do
        :source -> %{state.case | source: speakable}
        :result -> %{state.case | expected: speakable}
      end

    %{state | case: test_case, text: ""}
  end

  defp handle_event({:characters, characters}, _location, %{element: element} = state)
       when element in [:source, :result] do
    %{state | text: state.text <> List.to_string(characters)}
  end

  defp handle_event({:endElement, _uri, ~c"source", _qname}, _location, state) do
    test_case =
      if state.case.source == "" and state.text != "" do
        %{state.case | source: state.text}
      else
        state.case
      end

    %{state | case: test_case, element: nil, text: ""}
  end

  defp handle_event({:endElement, _uri, ~c"result", _qname}, _location, state) do
    test_case =
      if state.case.expected == "" and state.text != "" do
        %{state.case | expected: state.text}
      else
        state.case
      end

    %{state | case: test_case, element: nil, text: ""}
  end

  defp handle_event({:endElement, _uri, ~c"test", _qname}, _location, state) do
    %{state | cases: [state.case | state.cases], case: nil}
  end

  defp handle_event(_event, _location, state), do: state

  defp attribute_map(attributes) do
    Map.new(attributes, fn {_uri, _prefix, name, value} ->
      {List.to_string(name), List.to_string(value)}
    end)
  end

  @doc """
  Runs one parsed case for a locale, returning :ok or
  `{:error, description}`.

  """
  def run_case(locale, test_case) do
    options =
      case test_case.source do
        "" -> []
        source -> [initial_pronoun: SpeakableString.print(source)]
      end

    with {:ok, concept} <- PronounConcept.new(locale, options),
         {:ok, concept, possessee} <- apply_constraints(concept, test_case.constraints) do
      query_errors =
        Enum.flat_map(test_case.queries, fn {name, expected} ->
          check_query(concept, name, expected)
        end)

      case query_errors ++ check_render(concept, possessee, test_case.expected) do
        [] -> :ok
        errors -> {:error, Enum.join(errors, "; ")}
      end
    else
      {:error, reason} -> {:error, "cannot build concept: #{inspect(reason)}"}
    end
  end

  # Plain constraints go on the pronoun; "dependency=<feature>"
  # constraints go on a possessee concept, with the sound
  # dependency represented by a vowel- or consonant-initial string.
  defp apply_constraints(concept, constraints) do
    possessee_string =
      if Map.get(constraints, @dependency_sound) in ["vowel-start", "vowel-end"] do
        "a"
      else
        ""
      end

    has_possessee? = Enum.any?(constraints, fn {name, _value} -> String.contains?(name, "=") end)

    with {:ok, possessee} <- Concept.new(concept.locale, possessee_string) do
      Enum.reduce_while(constraints, {:ok, concept, if(has_possessee?, do: possessee)}, fn
        {name, value}, {:ok, concept, possessee} ->
          case String.split(name, "=", parts: 2) do
            [_plain] ->
              case PronounConcept.put_constraint(concept, name, value) do
                {:ok, concept} -> {:cont, {:ok, concept, possessee}}
                {:error, _reason} = error -> {:halt, error}
              end

            [_dependency, feature_name] when name != @dependency_sound ->
              case Concept.put_constraint(possessee, feature_name, value) do
                {:ok, possessee} -> {:cont, {:ok, concept, possessee}}
                {:error, _reason} = error -> {:halt, error}
              end

            _sound ->
              {:cont, {:ok, concept, possessee}}
          end
      end)
    end
  end

  defp check_query(concept, name, expected) do
    # The public API returns grammeme values as atoms; the upstream
    # test expectations are strings.
    got =
      case PronounConcept.feature_value(concept, name) do
        value when is_atom(value) and value != nil -> Atom.to_string(value)
        value -> value
      end

    cond do
      got == nil and expected == "" -> []
      got == nil -> ["#{name}: got nil, want #{inspect(expected)}"]
      got == expected -> []
      true -> ["#{name}: got #{inspect(got)}, want #{inspect(expected)}"]
    end
  end

  defp check_render(_concept, _possessee, ""), do: []

  defp check_render(concept, possessee, expected) do
    got = PronounConcept.to_speakable_string(concept, possessee)
    expected = normalize(expected)

    if got == expected do
      []
    else
      ["render: got #{inspect(got)}, want #{inspect(expected)}"]
    end
  end

  defp normalize(value) when is_binary(value), do: value
  defp normalize({print, speak}), do: SpeakableString.new(print, speak)

  @doc """
  Runs a whole file and returns `{passed, failures}` where failures
  are `{index, case, description}` tuples.

  """
  def run_file(locale, path) do
    cases = parse_file(path)

    {passed, failures} =
      cases
      |> Enum.with_index(1)
      |> Enum.reduce({0, []}, fn {test_case, index}, {passed, failures} ->
        case run_case(locale, test_case) do
          :ok -> {passed + 1, failures}
          {:error, description} -> {passed, [{index, test_case, description} | failures]}
        end
      end)

    {passed, Enum.reverse(failures)}
  end
end
