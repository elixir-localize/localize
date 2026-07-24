defmodule Localize.Inflection.PronounConcept do
  @moduledoc """
  A pronoun with grammatical constraints.

  The locale pronoun table (ported from the upstream
  `pronoun_XX.csv` resources) maps each pronoun surface form to its
  grammatical constraints. Constraints put on the concept select
  the matching pronoun; an initial pronoun seeds default
  constraints so that reinflection ("they" with `gender=masculine`
  becomes "he") preserves unconstrained properties.

  This is the equivalent of the upstream `PronounConcept`.

  """

  # The per-language synthesizers and conformance harnesses are ported
  # from the upstream C++ linguistic rule tables; their branchiness and
  # nesting mirror the reference implementation they are verified
  # against (see guides/inflection.md).
  # credo:disable-for-this-file Credo.Check.Refactor.Nesting

  alias Localize.Inflection.{
    Concept,
    Data,
    Feature,
    FeatureModel,
    Locale,
    PhraseProperties,
    SpeakableString
  }

  defstruct [
    :locale,
    :table_locale,
    :entries,
    :custom_count,
    default_constraints: %{},
    default_index: nil,
    constraints: %{}
  ]

  @type t :: %__MODULE__{
          locale: atom,
          table_locale: binary,
          entries: [{binary, %{optional(binary) => binary}}],
          custom_count: non_neg_integer,
          default_constraints: %{optional(binary) => binary},
          default_index: non_neg_integer | nil,
          constraints: %{optional(binary) => binary}
        }

  @dependency_prefix "dependency="
  @sound "sound"
  @speak "speak"

  # Regional locales whose pronoun tables live under another name.
  @locale_fallbacks %{
    "wuu_CN" => "zh",
    "yue_HK" => "yue_Hant",
    "zh_HK" => "yue_Hant",
    "zh_TW" => "zh_Hant"
  }

  @doc """
  Creates a pronoun concept for a locale.

  ### Arguments

  * `locale` is a locale atom or string, canonically in BCP47 form
    (`:"zh-TW"`, `"zh-TW"`); the underscore form is also accepted.
    Regional locales fall back to their parent language for both
    the feature model and the pronoun table.

  * `options` is a keyword list of options.

  ### Options

  * `:initial_pronoun` is a pronoun surface form whose grammatical
    properties seed the default constraints (unambiguous properties
    only).

  * `:display_data` is a list of `{word, constraints}` custom
    pronoun entries searched before the locale table.

  * `:default_constraints` is a map of feature name to value used
    to break ties between otherwise equal matches.

  ### Returns

  * `{:ok, concept}` or `{:error, reason}` when the locale has no
    pronoun table or the initial pronoun is unknown.

  ### Examples

      iex> {:ok, concept} = Localize.Inflection.PronounConcept.new(:en)
      iex> Localize.Inflection.PronounConcept.to_speakable_string(concept)
      "they"

      iex> {:ok, concept} = Localize.Inflection.PronounConcept.new(:en, initial_pronoun: "him")
      iex> {:ok, concept} = Localize.Inflection.PronounConcept.put_constraint(concept, :case, :nominative)
      iex> Localize.Inflection.PronounConcept.to_speakable_string(concept)
      "he"

  """
  def new(locale, options \\ []) do
    with {:ok, model_locale} <- resolve_model_locale(locale),
         {:ok, table_locale, table_entries} <- entries_for(model_locale, locale) do
      custom =
        for {word, constraints} <- Keyword.get(options, :display_data, []) do
          {word, Feature.normalize_constraints(constraints)}
        end

      concept = %__MODULE__{
        locale: model_locale,
        table_locale: table_locale,
        entries: custom ++ table_entries,
        custom_count: length(custom),
        default_constraints:
          options |> Keyword.get(:default_constraints, %{}) |> Feature.normalize_constraints()
      }

      case Keyword.get(options, :initial_pronoun) do
        nil -> {:ok, concept}
        pronoun -> seed_from_pronoun(concept, pronoun)
      end
    end
  end

  # The feature model comes from the closest ancestor locale with
  # generated data (zh-TW uses the zh features).
  defp resolve_model_locale(locale) do
    with {:ok, atom} <- Locale.resolve(locale),
         :ok <- Data.ensure_loaded(atom) do
      {:ok, atom}
    else
      {:error, %_struct{} = exception} ->
        {:error, exception}

      _error ->
        {:error, Localize.InflectionDataNotAvailableError.exception(locale: locale)}
    end
  end

  # Resolves the pronoun table through the upstream fallback chain
  # (special pairs first, then the parent locale) and parses it
  # against the model locale's features. Parsed tables are cached.
  defp entries_for(model_locale, locale) do
    locale
    |> Locale.normalize()
    |> resolve_table_locale()
    |> case do
      nil ->
        {:error, Localize.InflectionNotSupportedError.exception(locale: locale)}

      table_locale ->
        key = {__MODULE__, model_locale, table_locale}

        case :persistent_term.get(key, nil) do
          nil ->
            entries = parse_table(model_locale, table_path(table_locale))
            :persistent_term.put(key, entries)
            {:ok, table_locale, entries}

          entries ->
            {:ok, table_locale, entries}
        end
    end
  end

  defp resolve_table_locale(""), do: nil

  defp resolve_table_locale(locale) do
    if File.exists?(table_path(locale)) do
      locale
    else
      resolve_table_locale(Map.get(@locale_fallbacks, locale) || Locale.parent(locale))
    end
  end

  defp table_path(table_locale) do
    Localize.Inflection.DataDir.path("pronoun_#{table_locale}.csv")
  end

  defp parse_table(model_locale, path) do
    path
    |> File.read!()
    |> String.split("\n")
    |> Enum.reject(&(String.trim(&1) == ""))
    |> Enum.map(fn line ->
      [word | cells] = String.split(String.trim_trailing(line, "\r"), ",")

      constraints =
        Enum.reduce(cells, %{}, fn cell, acc ->
          {key, value} = parse_cell(model_locale, cell)
          Map.put_new(acc, key, value)
        end)

      {word, constraints}
    end)
  end

  # A cell is a grammeme alias ("third" -> person=third), a bare
  # feature name ("gender" -> applies to all values), or an
  # explicit "name=value". A "dependency=" prefix targets the
  # referenced concept instead of the pronoun itself.
  defp parse_cell(model_locale, cell) do
    {dependency?, constraint} =
      case cell do
        @dependency_prefix <> rest -> {true, rest}
        other -> {false, other}
      end

    {feature_name, value} =
      case FeatureModel.alias_for(model_locale, constraint) do
        {feature_name, value} ->
          {feature_name, value}

        nil ->
          {name, value} =
            case String.split(constraint, "=", parts: 2) do
              [name, value] -> {name, value}
              [name] -> {name, ""}
            end

          if FeatureModel.feature(model_locale, name) == nil do
            raise ArgumentError,
                  "unknown constraint #{inspect(cell)} for #{model_locale} pronouns"
          end

          {name, value}
      end

    if dependency? do
      {@dependency_prefix <> feature_name, value}
    else
      {feature_name, value}
    end
  end

  # The initial pronoun's grammatical properties become default
  # constraints; a property that differs between readings ("her" is
  # accusative or genitive) is ambiguous and dropped.
  defp seed_from_pronoun(concept, pronoun) do
    folded = fold(pronoun)

    {defaults, index} =
      concept.entries
      |> Enum.with_index()
      |> Enum.reduce({%{}, nil}, fn {{word, constraints}, index}, {defaults, first_index} ->
        if fold(String.trim_trailing(word, " ")) == folded do
          defaults =
            Enum.reduce(constraints, defaults, fn {name, value}, defaults ->
              case Map.fetch(defaults, name) do
                :error -> Map.put(defaults, name, value)
                {:ok, ^value} -> defaults
                {:ok, _other} -> Map.put(defaults, name, "")
              end
            end)

          {defaults, first_index || index}
        else
          {defaults, first_index}
        end
      end)

    if index == nil do
      {:error, Localize.UnknownPronounError.exception(pronoun: pronoun, locale: concept.locale)}
    else
      defaults = defaults |> Enum.reject(fn {_name, value} -> value == "" end) |> Map.new()
      {:ok, %{concept | default_constraints: defaults, default_index: index}}
    end
  end

  defp fold(string), do: String.downcase(string)

  @doc """
  Puts a constraint on the concept.

  ### Arguments

  * `concept` is a pronoun concept from `new/2`.

  * `name` is a feature name such as "person" or "case".

  * `value` is the constraint value such as "third".

  ### Returns

  * `{:ok, concept}` or `{:error, reason}` when the feature is
    unknown or the value is not valid for a bounded feature.

  ### Examples

      iex> {:ok, concept} = Localize.Inflection.PronounConcept.new(:en)
      iex> {:ok, concept} = Localize.Inflection.PronounConcept.put_constraint(concept, :person, :first)
      iex> Localize.Inflection.PronounConcept.to_speakable_string(concept)
      "I"

  """
  def put_constraint(%__MODULE__{} = concept, name, value) do
    name = Feature.to_internal(name)
    value = Feature.to_internal(value)

    case FeatureModel.feature(concept.locale, name) do
      nil ->
        {:error, Localize.UnknownFeatureError.exception(feature: name, locale: concept.locale)}

      %{type: :bounded, values: values} ->
        if MapSet.member?(values, value) do
          {:ok, %{concept | constraints: Map.put(concept.constraints, name, value)}}
        else
          {:error,
           Localize.InvalidValueError.exception(
             value: value,
             expected: :grammeme,
             allowed_values: Enum.sort(values),
             context: name
           )}
        end

      %{type: :unbounded} ->
        {:ok, %{concept | constraints: Map.put(concept.constraints, name, value)}}
    end
  end

  @doc """
  Removes a constraint from the concept.

  """
  def clear_constraint(%__MODULE__{} = concept, name) do
    %{concept | constraints: Map.delete(concept.constraints, Feature.to_internal(name))}
  end

  @doc """
  Removes all constraints from the concept.

  ### Examples

      iex> {:ok, concept} = Localize.Inflection.PronounConcept.new(:en)
      iex> {:ok, concept} = Localize.Inflection.PronounConcept.put_constraint(concept, :person, :first)
      iex> concept |> Localize.Inflection.PronounConcept.reset() |> Localize.Inflection.PronounConcept.to_speakable_string()
      "they"

  """
  def reset(%__MODULE__{} = concept) do
    %{concept | constraints: %{}}
  end

  @doc """
  Returns the value of a feature for the currently selected
  pronoun, or nil.

  ### Arguments

  * `concept` is a pronoun concept from `new/2`.

  * `name` is a feature name such as "gender".

  ### Returns

  * The feature value string, or nil when the selected pronoun does
    not constrain the feature.

  ### Examples

      iex> {:ok, concept} = Localize.Inflection.PronounConcept.new(:en)
      iex> Localize.Inflection.PronounConcept.feature_value(concept, :case)
      :nominative

      iex> {:ok, concept} = Localize.Inflection.PronounConcept.new(:en)
      iex> Localize.Inflection.PronounConcept.feature_value(concept, :gender)
      nil

  """
  def feature_value(%__MODULE__{} = concept, name) do
    name = Feature.to_internal(name)

    case current_value(concept, nil, true, true) do
      nil -> nil
      {_word, constraints} -> Feature.to_public(concept.locale, name, Map.get(constraints, name))
    end
  end

  @doc """
  Returns true when a pronoun matches the constraints without
  falling back to the default entry.

  """
  def exists?(%__MODULE__{} = concept) do
    current_value(concept, nil, false, true) != nil
  end

  @doc """
  Returns true when a custom display-data entry matches the
  constraints.

  """
  def custom_match?(%__MODULE__{} = concept) do
    current_value(concept, nil, false, false) != nil
  end

  @doc """
  Renders the selected pronoun.

  ### Arguments

  * `concept` is a pronoun concept from `new/2`.

  * `referenced_concept` is an optional `Localize.Inflection.Concept`
    the pronoun depends on (a possessee), used to satisfy
    `dependency=` constraints such as the French elision before a
    vowel.

  ### Returns

  * A speakable string (a binary, or `{print, speak}`), or nil when
    no pronoun matches.

  """
  def to_speakable_string(concept, referenced_concept \\ nil)

  def to_speakable_string(%__MODULE__{} = concept, referenced_concept) do
    case current_value(concept, referenced_concept, true, true) do
      nil ->
        nil

      {"", _constraints} ->
        nil

      {word, constraints} ->
        case Map.get(constraints, @speak) do
          nil -> word
          speak -> SpeakableString.new(word, speak)
        end
    end
  end

  # ── Matching ─────────────────────────────────────────────────

  defp current_value(concept, referenced_concept, return_default?, match_all?) do
    case first_possible_value(concept, referenced_concept, return_default?, match_all?) do
      {"", _constraints} -> nil
      other -> other
    end
  end

  defp first_possible_value(concept, referenced_concept, return_default?, match_all?) do
    if referenced_concept == nil and matching_initial_pronoun?(concept) do
      Enum.at(concept.entries, concept.default_index)
    else
      candidates =
        if match_all? do
          concept.entries
        else
          Enum.take(concept.entries, concept.custom_count)
        end

      best = best_match(concept, referenced_concept, candidates)

      case best do
        nil when return_default? -> List.first(concept.entries)
        nil -> nil
        {entry, _generics, _unmatched} -> entry
      end
    end
  end

  # With no referenced concept, an initial pronoun whose entry
  # matches every constraint exactly is returned unchanged.
  defp matching_initial_pronoun?(%{default_index: nil}), do: false

  defp matching_initial_pronoun?(concept) do
    {_word, entry_constraints} = Enum.at(concept.entries, concept.default_index)

    Enum.all?(concept.constraints, fn {name, value} ->
      Map.get(entry_constraints, name) == value
    end)
  end

  # Entries are scanned in order; a candidate replaces the current
  # best only when strictly better: fewer generic (empty-value)
  # matches, or equally generic and fewer unmatched default
  # constraints.
  defp best_match(concept, referenced_concept, candidates) do
    Enum.reduce_while(candidates, nil, fn {_word, entry_constraints} = entry, best ->
      with {:match, generics} <- match_constraints(concept.constraints, entry_constraints),
           true <- dependencies_match?(concept, referenced_concept, entry_constraints) do
        unmatched =
          Enum.count(concept.default_constraints, fn {name, value} ->
            match_state(entry_constraints, name, value) == :no_match
          end)

        better? =
          case best do
            nil ->
              true

            {_entry, best_generics, _u} when generics < best_generics ->
              true

            {_entry, best_generics, best_unmatched} ->
              generics == best_generics and unmatched < best_unmatched
          end

        best = if better?, do: {entry, generics, unmatched}, else: best

        case best do
          {_entry, 0, 0} -> {:halt, best}
          _other -> {:cont, best}
        end
      else
        _no_match -> {:cont, best}
      end
    end)
  end

  defp match_constraints(constraints, entry_constraints) do
    Enum.reduce_while(constraints, {:match, 0}, fn {name, value}, {:match, generics} ->
      case match_state(entry_constraints, name, value) do
        :no_match -> {:halt, :no_match}
        :generic_match -> {:cont, {:match, generics + 1}}
        :full_match -> {:cont, {:match, generics}}
      end
    end)
  end

  defp match_state(entry_constraints, name, value) do
    case Map.fetch(entry_constraints, name) do
      :error -> :no_match
      {:ok, ^value} -> :full_match
      # An empty value applies to all values, but a later entry may
      # be more specific (them versus him or her).
      {:ok, ""} -> :generic_match
      {:ok, _other} -> :no_match
    end
  end

  # `dependency=` constraints hold against the referenced concept:
  # the sound of its rendered string, or one of its feature values.
  defp dependencies_match?(_concept, nil, _entry_constraints), do: true

  defp dependencies_match?(concept, referenced_concept, entry_constraints) do
    Enum.all?(entry_constraints, fn
      {@dependency_prefix <> feature_name, value} ->
        if feature_name == @sound do
          rendered = Concept.to_speakable_string(referenced_concept) || ""
          matching_sound?(concept.locale, SpeakableString.print(rendered), value)
        else
          matching_feature_value?(referenced_concept, feature_name, value)
        end

      {_name, _value} ->
        true
    end)
  end

  defp matching_sound?(locale, rendered, match_type) do
    if match_type in ["consonant-start", "vowel-start"] do
      vowel? = PhraseProperties.starts_with_vowel?(locale, rendered)

      not ((vowel? and match_type == "consonant-start") or
             (not vowel? and match_type == "vowel-start"))
    else
      vowel? = PhraseProperties.ends_with_vowel?(locale, rendered)

      not ((vowel? and match_type == "consonant-end") or
             (not vowel? and match_type == "vowel-end"))
    end
  end

  defp matching_feature_value?(referenced_concept, feature_name, value) do
    print =
      case Concept.feature_value(referenced_concept, feature_name) do
        nil -> nil
        atom when is_atom(atom) -> Atom.to_string(atom)
        other -> SpeakableString.print(other)
      end

    not ((print == nil and value == "") or (print != nil and print != value))
  end
end
