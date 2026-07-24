defmodule Localize.Inflection.Feature do
  @moduledoc false

  # Boundary conversion between the public API's atoms and the
  # engine's internal strings. Feature names and grammeme values
  # are atoms at the API surface (matching the Localize
  # convention); the engine, the data pipeline and the upstream
  # conformance suites all speak strings. Unbounded feature values
  # (the "speak" channel, article strings) stay binaries.

  alias Localize.Inflection.FeatureModel

  @doc """
  Normalizes a feature name or grammeme value to its internal
  string form.

  """
  def to_internal(value) when is_atom(value), do: Atom.to_string(value)
  def to_internal(value) when is_binary(value), do: value

  @doc """
  Normalizes a constraints map or keyword list to internal string
  keys and values.

  """
  def normalize_constraints(constraints) do
    Map.new(constraints, fn {name, value} -> {to_internal(name), to_internal(value)} end)
  end

  @doc """
  Converts an internal feature value to its public form: an atom
  when the feature is bounded and the value is one of its
  grammemes, otherwise the value unchanged.

  """
  def to_public(locale, feature_name, value) when is_binary(value) do
    case FeatureModel.feature(locale, to_internal(feature_name)) do
      %{type: :bounded, values: values} ->
        # Grammeme names come from the library's own shipped data,
        # a small closed set, so atom creation is safe.
        if MapSet.member?(values, value) do
          String.to_atom(value)
        else
          value
        end

      _other ->
        value
    end
  end

  def to_public(_locale, _feature_name, value), do: value

  @doc """
  Returns the public form of a locale's feature definitions: a map
  of feature name atom to `%{type:, values:}` with grammeme values
  as sorted atoms.

  """
  def public_features(locale) do
    Map.new(FeatureModel.features(locale), fn {name, definition} ->
      values =
        definition.values
        |> Enum.sort()
        |> Enum.map(&String.to_atom/1)

      {String.to_atom(name), %{type: definition.type, values: values}}
    end)
  end
end
