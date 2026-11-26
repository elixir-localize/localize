defmodule Localize.Number.Rbnf.RuleSetName do
  @moduledoc false

  # Reads an RBNF rule-set name as a family and the grammatical features
  # its other segments name: `spellout-ordinal-masculine-genitive` is the
  # `:spellout_ordinal` family with the gender `:masculine` and the case
  # `:genitive`. Segments are read as a set, since CLDR's order varies
  # (`masculine-animate-accusative` beside `masculine-accusative-animate`).
  #
  # Each segment is looked up in a table of literal strings compiled into
  # this module, so no atom is made from a name; the feature values are
  # `Localize.GrammaticalFeature`'s. A name with any segment not in the
  # table carries a style rather than a feature (`financial`, `verbose`,
  # German `-n`, `-r`, `-s`, `-m`, …) and is not read: it stays reachable
  # by its exact name only.
  #
  # Gender follows CLDR's `grammaticalFeatures.xml`, which treats Slavic
  # masculine animacy as gender values: `masculine-animate` and a bare
  # `animate` are `:animate`, `masculine-personal` and Slovak
  # `masculine-human` are `:personal`. Swedish `reale` (utrum) is
  # `:common`, the value CLDR gives Swedish.

  @families [
    {["digits", "ordinal"], :digits_ordinal},
    {["spellout", "ordinal"], :spellout_ordinal},
    {["spellout", "cardinal"], :spellout_cardinal},
    {["spellout", "numbering"], :spellout_numbering}
  ]

  @genders %{
    "masculine" => :masculine,
    "feminine" => :feminine,
    "neuter" => :neuter,
    "common" => :common,
    "reale" => :common
  }

  # Segments that mark a masculine noun's animacy, read in CLDR's model as
  # a gender of their own.
  @animacy %{
    "animate" => :animate,
    "inanimate" => :inanimate,
    "personal" => :personal,
    "human" => :personal
  }

  @segments Map.merge(
              %{
                "plural" => {:grammatical_number, :plural},
                "dual" => {:grammatical_number, :dual},
                "definite" => {:grammatical_definiteness, :definite}
              },
              Map.new(
                Localize.GrammaticalFeature.values(:grammatical_case),
                &{Atom.to_string(&1), {:grammatical_case, &1}}
              )
            )

  @type family :: :digits_ordinal | :spellout_ordinal | :spellout_cardinal | :spellout_numbering

  @type features :: %{optional(Localize.GrammaticalFeature.feature()) => atom()}

  # The family a rule-set name belongs to and the features it marks, or
  # `:error` for a name outside the families or with a style segment. The
  # name is an atom or string, with `_` or `-` between its segments.
  @spec parse(atom() | String.t()) :: {:ok, family(), features()} | :error
  def parse(name) when is_atom(name) do
    name
    |> Atom.to_string()
    |> parse()
  end

  def parse(name) when is_binary(name) do
    segments = String.split(name, ["_", "-"])

    case family(segments) do
      {:ok, family, rest} -> features(family, rest)
      :error -> :error
    end
  end

  def parse(_name) do
    :error
  end

  defp family(segments) do
    Enum.find_value(@families, :error, fn {prefix, family} ->
      if List.starts_with?(segments, prefix) do
        {:ok, family, Enum.drop(segments, length(prefix))}
      end
    end)
  end

  defp features(family, segments) do
    with {:ok, features} <- read_segments(segments, %{}, nil) do
      {:ok, family, features}
    end
  end

  # Gender and animacy are gathered apart and joined at the end, so the
  # order they come in does not matter. Every other segment fills its
  # feature once; a second value for one feature makes the name unreadable.
  defp read_segments([], features, gender) do
    with {:ok, gender} <- join_gender(gender) do
      {:ok, put_gender(features, gender)}
    end
  end

  defp read_segments([segment | rest], features, gender) do
    case read_segment(segment) do
      {:gender, value} -> read_gender(rest, features, gender, {:gender, value})
      {:animacy, value} -> read_gender(rest, features, gender, {:animacy, value})
      {feature, value} -> read_feature(rest, features, gender, feature, value)
      :error -> :error
    end
  end

  defp read_segment(segment) do
    cond do
      Map.has_key?(@genders, segment) -> {:gender, Map.fetch!(@genders, segment)}
      Map.has_key?(@animacy, segment) -> {:animacy, Map.fetch!(@animacy, segment)}
      Map.has_key?(@segments, segment) -> Map.fetch!(@segments, segment)
      true -> :error
    end
  end

  defp read_feature(rest, features, gender, feature, value) do
    if Map.has_key?(features, feature) do
      :error
    else
      read_segments(rest, Map.put(features, feature, value), gender)
    end
  end

  defp read_gender(rest, features, marks, marked) do
    read_segments(rest, features, [marked | List.wrap(marks)])
  end

  defp join_gender(nil) do
    {:ok, nil}
  end

  defp join_gender([{_kind, value}]) do
    {:ok, value}
  end

  defp join_gender([{:animacy, value}, {:gender, :masculine}]) do
    {:ok, value}
  end

  defp join_gender([{:gender, :masculine}, {:animacy, value}]) do
    {:ok, value}
  end

  defp join_gender(_marks) do
    :error
  end

  defp put_gender(features, nil) do
    features
  end

  defp put_gender(features, gender) do
    Map.put(features, :grammatical_gender, gender)
  end
end
