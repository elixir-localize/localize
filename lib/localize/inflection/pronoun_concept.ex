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

  import Localize.Utils.Helpers, only: [is_keyword_list: 1]

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
    Regional locales fall back to their parent language for the
    feature model, and for the pronoun table unless the region has
    one of its own: `zh-TW` uses the Traditional Chinese table that
    ships with `zh`, and `zh-HK` the Cantonese (`yue`) table.

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

  * `{:ok, concept}` on success.

  * `{:error, reason}` when the locale has no pronoun table, the
    inflection data it needs (its own, or that of the language
    whose table it uses) has not been downloaded, or the initial
    pronoun is unknown.

  ### Examples

      iex> {:ok, concept} = Localize.Inflection.PronounConcept.new(:en)
      iex> Localize.Inflection.PronounConcept.to_speakable_string(concept)
      "they"

      iex> {:ok, concept} = Localize.Inflection.PronounConcept.new(:en, initial_pronoun: "him")
      iex> {:ok, concept} = Localize.Inflection.PronounConcept.put_constraint(concept, :case, :nominative)
      iex> Localize.Inflection.PronounConcept.to_speakable_string(concept)
      "he"

  """
  def new(locale, options \\ [])

  def new(locale, options) when is_keyword_list(options) do
    with {:ok, custom} <- display_data(Keyword.get(options, :display_data, [])),
         {:ok, initial_pronoun} <- initial_pronoun(Keyword.get(options, :initial_pronoun)),
         {:ok, default_constraints} <-
           Feature.constraints(Keyword.get(options, :default_constraints, %{})),
         {:ok, model_locale} <- resolve_model_locale(locale),
         {:ok, table_locale, table_entries} <- entries_for(model_locale, locale) do
      concept = %__MODULE__{
        locale: model_locale,
        table_locale: table_locale,
        entries: custom ++ table_entries,
        custom_count: length(custom),
        default_constraints: default_constraints
      }

      case initial_pronoun do
        nil -> {:ok, concept}
        pronoun -> seed_from_pronoun(concept, pronoun)
      end
    end
  end

  def new(_locale, options), do: {:error, Localize.Utils.Helpers.invalid_options(options)}

  # Display data is a list of `{word, constraints}` entries; an entry of
  # another shape is ignored.
  defp display_data(entries) when is_list(entries) do
    {:ok,
     for(
       {word, constraints} when is_binary(word) <- entries,
       do: {word, Feature.normalize_constraints(constraints)}
     )}
  end

  defp display_data(entries) do
    {:error,
     Localize.Utils.Helpers.invalid_value(entries, "a list of {word, constraints} entries")}
  end

  defp initial_pronoun(pronoun) when is_nil(pronoun) or is_binary(pronoun), do: {:ok, pronoun}

  defp initial_pronoun(pronoun),
    do: {:error, Localize.Utils.Helpers.invalid_value(pronoun, "a pronoun string")}

  # The feature model comes from the closest ancestor locale with
  # generated data (zh-TW uses the zh features).
  defp resolve_model_locale(locale) do
    with {:ok, atom} <- Locale.resolve(locale),
         :ok <- loaded_data(atom, locale) do
      {:ok, atom}
    end
  end

  # `ensure_loaded/1` reports a bare reason — a posix error, or an artifact
  # predating the packed lexicon — which this names for the locale asked for.
  # An error already carrying an exception, such as literal memory being
  # exhausted, says more than that and is kept.
  defp loaded_data(atom, locale) do
    case Data.ensure_loaded(atom) do
      :ok ->
        :ok

      {:error, %_struct{} = exception} ->
        {:error, exception}

      {:error, _reason} ->
        {:error, Localize.InflectionDataNotAvailableError.exception(locale: locale)}
    end
  end

  # Resolves the pronoun table through the fallback chain and parses
  # it against the model locale's features. Parsed tables are cached.
  defp entries_for(model_locale, locale) do
    case resolve_table(Locale.normalize(locale)) do
      {:ok, table_locale, lines} ->
        key = {__MODULE__, model_locale, table_locale}

        case :persistent_term.get(key, nil) do
          nil ->
            entries = parse_lines(model_locale, lines)
            Localize.LiteralMemory.cache(key, entries)
            {:ok, table_locale, entries}

          entries ->
            {:ok, table_locale, entries}
        end

      {:error, exception} ->
        {:error, exception}

      nil ->
        {:error, Localize.InflectionNotSupportedError.exception(locale: locale)}
    end
  end

  # Script pairs first, then the parent locale. Every table ships in an
  # artifact: a supported locale's in its own, and a script table that
  # no supported locale owns (zh_Hant) in its language's, under
  # `:script_pronouns`. A table whose artifact is not available is an
  # error, never a fall through to some other table.
  defp resolve_table(""), do: nil

  defp resolve_table(locale) do
    cond do
      locale in Locale.supported() ->
        artifact_table(locale)

      lines = script_table(locale) ->
        {:ok, locale, lines}

      true ->
        # Upstream's own walk (`LocaleUtils::getFallbackPair`): its
        # fallbacks, then `Locale.upstream_fallback/1`.
        resolve_table(Map.get(@locale_fallbacks, locale) || Locale.upstream_fallback(locale))
    end
  end

  # The table can belong to another language than the model locale
  # (zh-HK takes yue's), so its artifact is resolved in its own right:
  # downloaded when that is permitted, and otherwise reported as not
  # available rather than raised.
  defp artifact_table(table_locale) do
    with {:ok, atom} <- Locale.resolve(table_locale),
         {:ok, artifact} <- artifact_metadata(atom, table_locale) do
      {:ok, table_locale, artifact.pronouns}
    end
  end

  # As `loaded_data/2`: a bare reason is named for the locale asked for, and
  # an error already carrying an exception is kept.
  defp artifact_metadata(atom, table_locale) do
    case Data.metadata(atom) do
      {:ok, artifact} ->
        {:ok, artifact}

      {:error, %{__exception__: true} = exception} ->
        {:error, exception}

      {:error, _reason} ->
        {:error, Localize.InflectionDataNotAvailableError.exception(locale: table_locale)}
    end
  end

  defp script_table(table_locale) do
    [language | _subtags] = String.split(table_locale, "_")

    case supported_artifact(language) do
      {:ok, artifact} -> Map.get(artifact.script_pronouns, table_locale)
      :none -> nil
    end
  end

  # `:none` where the language has no inflection data to read pronouns from.
  defp supported_artifact(language) do
    if language in Locale.supported() do
      resolved_artifact(language)
    else
      :none
    end
  end

  defp resolved_artifact(language) do
    case Locale.resolve(language) do
      {:ok, atom} -> artifact_or_none(atom)
      {:error, _unresolved} -> :none
    end
  end

  defp artifact_or_none(atom) do
    case Data.metadata(atom) do
      {:ok, artifact} -> {:ok, artifact}
      {:error, _unavailable} -> :none
    end
  end

  defp parse_lines(model_locale, lines) do
    Enum.map(lines, fn line ->
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

  def put_constraint(concept, _name, _value), do: {:error, invalid_concept(concept)}

  @doc """
  Removes a constraint from the concept.

  ### Arguments

  * `concept` is a pronoun concept from `new/2`.

  * `name` is the grammatical feature to remove, such as `:person`.

  ### Returns

  * The concept without the constraint, or

  * `{:error, exception}` when `concept` is not a pronoun concept.

  ### Examples

      iex> {:ok, concept} = Localize.Inflection.PronounConcept.new(:en)
      iex> {:ok, concept} = Localize.Inflection.PronounConcept.put_constraint(concept, :person, :first)
      iex> concept |> Localize.Inflection.PronounConcept.clear_constraint(:person) |> Localize.Inflection.PronounConcept.to_speakable_string()
      "they"

  """
  def clear_constraint(%__MODULE__{} = concept, name) do
    %{concept | constraints: Map.delete(concept.constraints, Feature.to_internal(name))}
  end

  def clear_constraint(concept, _name), do: {:error, invalid_concept(concept)}

  defp invalid_concept(value),
    do: Localize.Utils.Helpers.invalid_value(value, "a Localize.Inflection.PronounConcept")

  @doc """
  Removes all constraints from the concept.

  ### Arguments

  * `concept` is a pronoun concept from `new/2`.

  ### Returns

  * The concept without constraints, or

  * `{:error, exception}` when `concept` is not a pronoun concept.

  ### Examples

      iex> {:ok, concept} = Localize.Inflection.PronounConcept.new(:en)
      iex> {:ok, concept} = Localize.Inflection.PronounConcept.put_constraint(concept, :person, :first)
      iex> concept |> Localize.Inflection.PronounConcept.reset() |> Localize.Inflection.PronounConcept.to_speakable_string()
      "they"

  """
  def reset(%__MODULE__{} = concept) do
    %{concept | constraints: %{}}
  end

  def reset(concept), do: {:error, invalid_concept(concept)}

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

  def feature_value(_concept, _name), do: nil

  @doc """
  Returns true when a pronoun matches the constraints without
  falling back to the default entry.

  ### Arguments

  * `concept` is a pronoun concept from `new/2`.

  ### Returns

  * `true` when a pronoun matches, and `false` otherwise or when
    `concept` is not a pronoun concept.

  ### Examples

      iex> {:ok, concept} = Localize.Inflection.PronounConcept.new(:en)
      iex> {:ok, concept} = Localize.Inflection.PronounConcept.put_constraint(concept, :person, :first)
      iex> Localize.Inflection.PronounConcept.exists?(concept)
      true

  """
  def exists?(%__MODULE__{} = concept) do
    current_value(concept, nil, false, true) != nil
  end

  def exists?(_concept), do: false

  @doc """
  Returns true when a custom display-data entry matches the
  constraints.

  ### Arguments

  * `concept` is a pronoun concept from `new/2`.

  ### Returns

  * `true` when an entry of the concept's `:display_data` matches,
    and `false` otherwise or when `concept` is not a pronoun concept.

  ### Examples

      iex> {:ok, concept} =
      ...>   Localize.Inflection.PronounConcept.new(:en,
      ...>     display_data: [{"xe", %{person: :third, number: :singular}}]
      ...>   )
      iex> {:ok, third} = Localize.Inflection.PronounConcept.put_constraint(concept, :person, :third)
      iex> Localize.Inflection.PronounConcept.custom_match?(third)
      true
      iex> {:ok, first} = Localize.Inflection.PronounConcept.put_constraint(concept, :person, :first)
      iex> Localize.Inflection.PronounConcept.custom_match?(first)
      false

  """
  def custom_match?(%__MODULE__{} = concept) do
    current_value(concept, nil, false, false) != nil
  end

  def custom_match?(_concept), do: false

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
    no pronoun matches or `concept` is not a pronoun concept.

  ### Examples

      iex> {:ok, concept} = Localize.Inflection.PronounConcept.new(:en)
      iex> {:ok, concept} = Localize.Inflection.PronounConcept.put_constraint(concept, :person, :first)
      iex> Localize.Inflection.PronounConcept.to_speakable_string(concept)
      "I"

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

  def to_speakable_string(_concept, _referenced_concept), do: nil

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

  # Entries are scanned in order, `halted/2` deciding which of a candidate
  # and the current best survives.
  defp best_match(concept, referenced_concept, candidates) do
    Enum.reduce_while(candidates, nil, fn entry, best ->
      scanned(concept, referenced_concept, entry, best)
    end)
  end

  # A candidate that matches neither the constraints nor the dependencies
  # leaves the current best standing.
  defp scanned(concept, referenced_concept, {_word, entry_constraints} = entry, best) do
    case matched_generics(concept, referenced_concept, entry_constraints) do
      {:ok, generics} -> scored(concept, entry, entry_constraints, generics, best)
      :no_match -> {:cont, best}
    end
  end

  defp matched_generics(concept, referenced_concept, entry_constraints) do
    with {:match, generics} <- match_constraints(concept.constraints, entry_constraints),
         :match <- dependency_state(concept, referenced_concept, entry_constraints) do
      {:ok, generics}
    end
  end

  # The predicate in the vocabulary `match_constraints/2` answers in, so that
  # the `with` above needs no `else`.
  defp dependency_state(concept, referenced_concept, entry_constraints) do
    if dependencies_match?(concept, referenced_concept, entry_constraints) do
      :match
    else
      :no_match
    end
  end

  defp scored(concept, entry, entry_constraints, generics, best) do
    unmatched =
      Enum.count(concept.default_constraints, fn {name, value} ->
        match_state(entry_constraints, name, value) == :no_match
      end)

    halted({entry, generics, unmatched}, best)
  end

  # A candidate replaces the current best only when strictly better: fewer
  # generic matches, or equally generic and fewer unmatched defaults. An
  # entry matching every constraint fully ends the scan.
  defp halted(candidate, best), do: halt_or_continue(better_of(candidate, best))

  defp better_of(candidate, nil), do: candidate

  defp better_of({_entry, generics, _unmatched} = candidate, {_best, best_generics, _u})
       when generics < best_generics do
    candidate
  end

  defp better_of({_entry, generics, unmatched} = candidate, best) do
    {_best, best_generics, best_unmatched} = best

    if generics == best_generics and unmatched < best_unmatched, do: candidate, else: best
  end

  defp halt_or_continue({_entry, 0, 0} = best), do: {:halt, best}
  defp halt_or_continue(best), do: {:cont, best}

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
