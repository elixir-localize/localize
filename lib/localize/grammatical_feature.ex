defmodule Localize.GrammaticalFeature do
  @moduledoc false

  # The values of the grammatical options Localize takes —
  # `:grammatical_case`, `:grammatical_gender`, `:grammatical_number` and
  # `:grammatical_definiteness` — as literal atoms compiled into this
  # module, and the one place a caller's value for one of them is
  # checked. An atom is accepted only if it is in the option's list, and
  # a string only through the compiled map from each value's name to its
  # atom, so no atom is ever made from a caller's value.
  #
  # The values are CLDR's. Case and definiteness are the union of the
  # values `grammaticalFeatures.xml` lists and the ones RBNF rule-set
  # names use. Gender follows `grammaticalFeatures.xml` in treating Slavic
  # masculine animacy as gender values: `animate`, `inanimate` and Polish
  # `personal` stand in place of `masculine`. CLDR has no grammatical
  # number among its features; the values here are the ones RBNF names
  # mark (`plural`, `dual`) and the unmarked `singular`.

  @cases ~w(
    nominative accusative genitive dative instrumental locative prepositional
    vocative ablative oblique ergative partitive essive translative inessive
    elative illative adessive allative abessive comitative terminative
    sociative causal delative sublative superessive locativecopulative
  )a

  @genders ~w(masculine feminine neuter common animate inanimate personal)a

  @numbers ~w(singular dual plural)a

  @definiteness ~w(definite indefinite construct unspecified)a

  @values %{
    grammatical_case: @cases,
    grammatical_gender: @genders,
    grammatical_number: @numbers,
    grammatical_definiteness: @definiteness
  }

  @by_name Map.new(@values, fn {feature, values} ->
             {feature, Map.new(values, &{Atom.to_string(&1), &1})}
           end)

  @type feature ::
          :grammatical_case
          | :grammatical_gender
          | :grammatical_number
          | :grammatical_definiteness

  # The grammatical options, in the order they are documented.
  @spec features() :: [feature(), ...]
  def features do
    [:grammatical_case, :grammatical_gender, :grammatical_number, :grammatical_definiteness]
  end

  # The values an option takes, as atoms.
  @spec values(feature()) :: [atom(), ...]
  def values(feature) do
    Map.fetch!(@values, feature)
  end

  # A caller's value for an option, as one of its atoms. `nil` is an
  # option not given and stays `nil`. A string is read by name; any other
  # value, or a name that is not one of the option's values, is an error.
  @spec cast(feature(), term()) :: {:ok, atom() | nil} | {:error, Exception.t()}
  def cast(_feature, nil) do
    {:ok, nil}
  end

  def cast(feature, value) when is_atom(value) do
    if value in values(feature) do
      {:ok, value}
    else
      invalid(feature, value)
    end
  end

  def cast(feature, value) when is_binary(value) do
    names = Map.fetch!(@by_name, feature)

    case Map.fetch(names, value) do
      {:ok, atom} -> {:ok, atom}
      :error -> invalid(feature, value)
    end
  end

  def cast(feature, value) do
    invalid(feature, value)
  end

  # The grammatical options in a keyword list, as a map of each one given
  # to its atom, or the error for the first that is not valid. Options
  # given as `nil` are left out.
  @spec from_options(Keyword.t()) ::
          {:ok, %{optional(feature()) => atom()}} | {:error, Exception.t()}
  def from_options(options) do
    Enum.reduce_while(features(), {:ok, %{}}, fn feature, {:ok, grammar} ->
      case cast(feature, Keyword.get(options, feature)) do
        {:ok, nil} -> {:cont, {:ok, grammar}}
        {:ok, value} -> {:cont, {:ok, Map.put(grammar, feature, value)}}
        {:error, _exception} = error -> {:halt, error}
      end
    end)
  end

  defp invalid(feature, value) do
    {:error,
     Localize.InvalidValueError.exception(
       value: value,
       expected: feature,
       allowed_values: values(feature)
     )}
  end
end
