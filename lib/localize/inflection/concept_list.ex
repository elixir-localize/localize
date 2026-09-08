defmodule Localize.Inflection.ConceptList do
  @moduledoc """
  An and/or list of concepts rendered with locale-correct
  conjunctions.

  This is the port of the upstream `SemanticConceptList` and the
  `createAndList`/`createOrList` factories. Separators derive from
  Localize's own CLDR list patterns, and language-specific
  conjunction rules are applied on top: Spanish *y* becomes *e*
  before an i-sound (with the diphthong exception), Italian *e*
  becomes *ed* before a vowel, Hebrew prefixes ו directly to
  Hebrew words but hyphenates Latin ones, and the Korean particle
  과/와 follows the sound of the preceding word.

  Constraints put on the list propagate to every member, so an
  and-list of nouns can be pluralized or case-marked as a unit.
  Lists nest: a `ConceptList` can be a member of another
  `ConceptList`.

  """

  alias Localize.Inflection.{Concept, FeatureModel, Locale, SpeakableString}
  alias Localize.Inflection.ConceptList.{Hebrew, Italian, Korean, Spanish}

  defstruct [
    :locale,
    :conjunction,
    :conjunction_kind,
    concepts: [],
    before_first: nil,
    after_first: nil,
    item_delimiter: nil,
    before_last: nil,
    after_last: nil,
    item_prefix: nil,
    item_suffix: nil,
    avoid_affix_redundancy: true
  ]

  @type t :: %__MODULE__{}

  # Language-specific list behavior, applied over the CLDR-derived
  # base wiring. `custom:` selects a Conjunction module (dynamic
  # before-last); keyword entries overwrite separators with static
  # strings. zh_HK routes to the Cantonese configuration, as in
  # the upstream provider.
  @factories %{
    "ar" => %{
      and: [before_last: "، و", item_delimiter: "، و"],
      or: [before_last: "، أو ", item_delimiter: "، أو "]
    },
    "es" => %{and: [custom: Spanish], or: [custom: Spanish]},
    "he" => %{and: [custom: Hebrew], or: [before_last: " או "]},
    "it" => %{and: [custom: Italian], or: [before_last: " o "]},
    "ja" => %{
      and: [after_first: "と", item_delimiter: "、", before_last: ""],
      or: [after_first: "または", item_delimiter: "、", before_last: ""]
    },
    "ko" => %{and: [custom: Korean], or: [before_last: "또는 "]},
    "th" => %{
      and: [item_delimiter: ", ", before_last: " และ "],
      or: [item_delimiter: ", ", before_last: " หรือ "]
    },
    "tr" => %{and: [before_last: " ve "], or: [before_last: " ya da "]},
    "yue" => %{
      and: [before_last: "同", item_delimiter: "、"],
      or: [before_last: "或", item_delimiter: "、"]
    },
    "zh_HK" => %{
      and: [before_last: "同", item_delimiter: "、"],
      or: [before_last: "或", item_delimiter: "、"]
    }
  }

  @doc """
  Builds an and-list of concepts.

  ### Arguments

  * `locale` is a locale atom or string, canonically BCP47.

  * `concepts` is a list of `Localize.Inflection.Concept` or
    nested `Localize.Inflection.ConceptList` members; nil members
    are dropped.

  ### Returns

  * `{:ok, list}` or `{:error, exception}` when the locale's list
    patterns are unavailable.

  ### Examples

      iex> {:ok, jane} = Localize.Inflection.Concept.new(:es, "Jane")
      iex> {:ok, ivan} = Localize.Inflection.Concept.new(:es, "Ivan")
      iex> {:ok, list} = Localize.Inflection.ConceptList.and_list(:es, [jane, ivan])
      iex> Localize.Inflection.ConceptList.to_speakable_string(list)
      "Jane e Ivan"

      iex> concepts =
      ...>   for word <- ["gato", "gata"] do
      ...>     {:ok, concept} = Localize.Inflection.Concept.new(:es, word)
      ...>     concept
      ...>   end
      iex> {:ok, list} = Localize.Inflection.ConceptList.and_list(:es, concepts)
      iex> {:ok, list} = Localize.Inflection.ConceptList.put_constraint(list, :number, :plural)
      iex> Localize.Inflection.ConceptList.to_speakable_string(list)
      "gatos y gatas"

  """
  def and_list(locale, concepts) do
    build(locale, concepts, :and, :standard)
  end

  @doc """
  Builds an or-list of concepts.

  See `and_list/2` for arguments and returns.

  ### Examples

      iex> concepts =
      ...>   for word <- ["Jane", "Omar"] do
      ...>     {:ok, concept} = Localize.Inflection.Concept.new(:es, word)
      ...>     concept
      ...>   end
      iex> {:ok, list} = Localize.Inflection.ConceptList.or_list(:es, concepts)
      iex> Localize.Inflection.ConceptList.to_speakable_string(list)
      "Jane u Omar"

  """
  def or_list(locale, concepts) do
    build(locale, concepts, :or, :or)
  end

  defp build(locale, concepts, kind, style) do
    concepts = Enum.reject(concepts, &is_nil/1)
    internal = Locale.normalize(locale)
    customization = customization(internal, kind)

    case Keyword.get(customization, :custom) do
      nil -> base_list(locale, internal, concepts, style, customization)
      custom -> {:ok, custom_list(internal, concepts, kind, custom)}
    end
  end

  # Custom conjunction classes bypass the CLDR wiring: a plain
  # ", " delimiter and a dynamic before-last, for every size.
  defp custom_list(internal, concepts, kind, custom) do
    %__MODULE__{
      locale: internal,
      concepts: concepts,
      item_delimiter: ", ",
      conjunction: custom,
      conjunction_kind: kind
    }
  end

  defp base_list(locale, internal, concepts, style, customization) do
    with {:ok, separators} <- separators(locale, style) do
      base =
        if length(concepts) == 2 do
          %__MODULE__{locale: internal, concepts: concepts, before_last: separators.two}
        else
          %__MODULE__{
            locale: internal,
            concepts: concepts,
            item_delimiter: separators.delimiter,
            before_last: separators.before_last
          }
        end

      {:ok, apply_customization(base, customization)}
    end
  end

  defp customization(internal, kind) do
    configuration =
      Map.get(@factories, internal) || Map.get(@factories, Locale.parent(internal)) || %{}

    Map.get(configuration, kind, [])
  end

  defp apply_customization(list, customization) do
    Enum.reduce(customization, list, fn {field, value}, list ->
      put_separator(list, field, value)
    end)
  end

  # The separators derive from Localize's CLDR list patterns: the
  # two-item separator from the two pattern, the delimiter from the
  # start pattern (the upstream model applies it to middle gaps
  # too) and the before-last conjunction from the end pattern, with
  # non-breaking spaces replaced by regular spaces.
  defp separators(locale, style) do
    with {:ok, patterns} <- Localize.List.list_patterns_for(list_pattern_locale(locale)),
         %{^style => pattern} <- patterns do
      {:ok,
       %{
         two: pattern_separator(Map.fetch!(pattern, :two)),
         delimiter: pattern_separator(Map.fetch!(pattern, :start)),
         before_last: pattern_separator(Map.fetch!(pattern, :end))
       }}
    else
      %{} -> {:error, Localize.InflectionNotSupportedError.exception(locale: locale)}
      {:error, _reason} = error -> error
    end
  end

  defp list_pattern_locale(locale) do
    locale |> to_string() |> String.replace("_", "-")
  end

  defp pattern_separator([0 | tokens]) do
    tokens
    |> Enum.take_while(&(&1 != 1))
    |> Enum.map_join("", &to_string/1)
    |> String.replace("\u00A0", " ")
  end

  @doc """
  Sets a separator field.

  ### Arguments

  * `list` is a concept list.

  * `field` is one of `:before_first`, `:after_first`,
    `:item_delimiter`, `:before_last`, `:after_last`,
    `:item_prefix` or `:item_suffix`.

  * `value` is the separator as a speakable string; the empty
    string unsets the field, re-enabling any language-specific
    dynamic conjunction.

  """
  def put_separator(%__MODULE__{} = list, field, value)
      when field in [
             :before_first,
             :after_first,
             :item_delimiter,
             :before_last,
             :after_last,
             :item_prefix,
             :item_suffix
           ] do
    normalized = if value in [nil, ""], do: nil, else: value
    Map.put(list, field, normalized)
  end

  @doc """
  Returns the number of members.

  """
  def size(%__MODULE__{concepts: concepts}), do: length(concepts)

  @doc """
  Returns true when the list has at least one member.

  """
  def exists?(%__MODULE__{concepts: concepts}), do: concepts != []

  @doc """
  Puts a constraint on every member and records it on the list.

  """
  def put_constraint(%__MODULE__{} = list, name, value) do
    list.concepts
    |> Enum.reduce_while({:ok, []}, fn member, {:ok, members} ->
      case member_put_constraint(member, name, value) do
        {:ok, member} -> {:cont, {:ok, [member | members]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, members} -> {:ok, %{list | concepts: Enum.reverse(members)}}
      {:error, _reason} = error -> error
    end
  end

  @doc """
  Returns the value of a feature for the list.

  A grammatical category (number, gender, case, ...) returns the
  first member's value; a display feature renders the whole list
  with each member replaced by its feature value.

  """
  def feature_value(%__MODULE__{concepts: []}, _name), do: nil

  def feature_value(%__MODULE__{} = list, name) do
    if FeatureModel.category?(model_locale(list), to_string(name)) do
      member_feature_value(List.first(list.concepts), name)
    else
      assemble(list, name)
    end
  end

  # The feature model locale comes from the first member (zh_HK
  # lists carry zh concepts).
  defp model_locale(%__MODULE__{concepts: [%Concept{locale: locale} | _rest]}), do: locale

  defp model_locale(%__MODULE__{concepts: [%__MODULE__{} = nested | _rest]}),
    do: model_locale(nested)

  @doc """
  Renders the list with locale-correct separators.

  ### Returns

  * A speakable string, or nil when the list is empty.

  """
  def to_speakable_string(%__MODULE__{} = list) do
    assemble(list, nil)
  end

  # ── Assembly ─────────────────────────────────────────────────

  # The upstream algorithm, index-faithful: members that render
  # empty are skipped without becoming the previous item, and the
  # first/last roles are positional, so a dropped first item also
  # drops before_first and disables after_first.
  defp assemble(%__MODULE__{concepts: []}, _feature), do: nil

  defp assemble(%__MODULE__{} = list, feature) do
    last_index = length(list.concepts) - 1

    {parts, _previous} =
      list.concepts
      |> Enum.with_index()
      |> Enum.reduce({[], nil}, fn {member, index}, {parts, previous} ->
        formatted = format_member(member, feature)

        if formatted == nil or SpeakableString.print(formatted) == "" do
          {parts, previous}
        else
          parts =
            parts
            |> emit_before_first(list, index, formatted)
            |> emit_gap(list, index, last_index, previous, formatted)
            |> emit_item(list, formatted)
            |> emit_after_last(list, index, last_index, formatted)

          {parts, {index, formatted}}
        end
      end)

    case parts do
      [] -> nil
      parts -> parts |> Enum.reverse() |> Enum.reduce("", &SpeakableString.concat(&2, &1))
    end
  end

  defp format_member(member, nil), do: member_render(member)
  defp format_member(member, feature), do: member_feature_value(member, feature)

  defp emit_before_first(parts, list, 0, formatted) do
    push(parts, separator(list, :before_first, {formatted}))
  end

  defp emit_before_first(parts, _list, _index, _formatted), do: parts

  # The gap between the previous emitted item and this one:
  # after_first when the previous was the first item, before_last
  # when this is the last, composed in that order; a non-empty
  # composition suppresses the item delimiter.
  defp emit_gap(parts, _list, _index, _last_index, nil, _formatted), do: parts

  defp emit_gap(parts, list, index, last_index, {previous_index, previous_formatted}, formatted) do
    gap = ""

    gap =
      if previous_index == 0 do
        SpeakableString.concat(
          gap,
          separator(list, :after_first, {previous_formatted, formatted})
        )
      else
        gap
      end

    gap =
      if index == last_index do
        SpeakableString.concat(
          gap,
          separator(list, :before_last, {previous_formatted, formatted})
        )
      else
        gap
      end

    cond do
      last_index == 0 or index == 0 ->
        parts

      SpeakableString.print(gap) == "" ->
        push(parts, separator(list, :item_delimiter, {previous_formatted, formatted}))

      true ->
        push(parts, gap)
    end
  end

  defp emit_item(parts, list, formatted) do
    prefix = separator(list, :item_prefix, {formatted})
    suffix = separator(list, :item_suffix, {formatted})
    print = SpeakableString.print(formatted)

    parts =
      if list.avoid_affix_redundancy and
           String.starts_with?(print, SpeakableString.print(prefix)) do
        parts
      else
        push(parts, prefix)
      end

    parts = push(parts, formatted)

    if list.avoid_affix_redundancy and String.ends_with?(print, SpeakableString.print(suffix)) do
      parts
    else
      push(parts, suffix)
    end
  end

  defp emit_after_last(parts, list, index, last_index, formatted) when index == last_index do
    push(parts, separator(list, :after_last, {formatted}))
  end

  defp emit_after_last(parts, _list, _index, _last_index, _formatted), do: parts

  defp push(parts, separator) do
    if SpeakableString.print(separator) == "" and SpeakableString.speak(separator) == "" do
      parts
    else
      [separator | parts]
    end
  end

  # A stored separator wins; an unset field consults the dynamic
  # conjunction (only before_last is dynamic today), else "".
  defp separator(list, field, arguments) do
    case Map.fetch!(list, field) do
      nil -> dynamic_separator(list, field, arguments)
      value -> value
    end
  end

  defp dynamic_separator(%{conjunction: nil}, _field, _arguments), do: ""

  defp dynamic_separator(list, :before_last, {previous_formatted, formatted}) do
    list.conjunction.before_last(list.conjunction_kind, previous_formatted, formatted)
  end

  defp dynamic_separator(_list, _field, _arguments), do: ""

  # ── Member dispatch ──────────────────────────────────────────

  defp member_render(%Concept{} = concept), do: Concept.to_speakable_string(concept)
  defp member_render(%__MODULE__{} = list), do: to_speakable_string(list)

  defp member_feature_value(%Concept{} = concept, name), do: Concept.feature_value(concept, name)
  defp member_feature_value(%__MODULE__{} = list, name), do: feature_value(list, name)

  defp member_put_constraint(%Concept{} = concept, name, value) do
    Concept.put_constraint(concept, name, value)
  end

  defp member_put_constraint(%__MODULE__{} = list, name, value) do
    put_constraint(list, name, value)
  end
end
