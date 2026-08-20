defmodule Localize.Options do
  @moduledoc """
  Validation of option keys for the public formatting and parsing functions.

  An option key that a function does not recognise is almost always a typo.
  Ignoring it silently turns the typo into a wrong-looking result with nothing
  to trace it to — `currancy: :USD` returns a bare number and reports success.
  These functions turn that into an error naming the key, and the nearest
  known option where there is one.

  Only *keys* are checked here. Option values are validated by the function
  that uses them, which knows what a valid value is.

  """

  # Below this, two option names are not plausibly the same word mistyped.
  @suggestion_threshold 0.8

  @doc """
  Checks that every key in `options` is one of `known`.

  ### Arguments

  * `options` is a keyword list of options.

  * `known` is a `MapSet` of the option keys the caller accepts. Build it once
    at compile time with `MapSet.new/1`, not per call.

  ### Returns

  * `{:ok, options}` with the options unchanged, or

  * `{:error, exception}` naming the first unrecognised key.

  ### Examples

      iex> known = MapSet.new([:locale, :currency])
      iex> Localize.Options.validate_keys([locale: :en], known)
      {:ok, [locale: :en]}

      iex> known = MapSet.new([:locale, :currency])
      iex> {:error, exception} = Localize.Options.validate_keys([currancy: :USD], known)
      iex> Exception.message(exception)
      ":currancy is not a known option. Did you mean :currency?"

  """
  @spec validate_keys(keyword(), MapSet.t(atom())) ::
          {:ok, keyword()} | {:error, Localize.UnknownOptionError.t()}

  # The overwhelmingly common call passes no options at all, and pays nothing.
  def validate_keys([] = options, _known), do: {:ok, options}

  def validate_keys(options, known) when is_list(options) do
    case Enum.find(options, &unknown_key?(&1, known)) do
      nil ->
        {:ok, options}

      {key, _value} ->
        {:error,
         Localize.UnknownOptionError.exception(
           option: key,
           suggestion: suggestion(key, known),
           known: known |> MapSet.to_list() |> Enum.sort()
         )}
    end
  end

  defp unknown_key?({key, _value}, known), do: not MapSet.member?(known, key)
  defp unknown_key?(_other, _known), do: false

  # `String.jaro_distance/2` is the right shape for a typo: it scores
  # transpositions and near-misses highly, which is what a mistyped option is.
  defp suggestion(key, known) do
    typed = Atom.to_string(key)

    known
    |> Enum.map(fn candidate ->
      {candidate, String.jaro_distance(typed, Atom.to_string(candidate))}
    end)
    |> Enum.filter(fn {_candidate, score} -> score >= @suggestion_threshold end)
    |> Enum.max_by(fn {_candidate, score} -> score end, fn -> nil end)
    |> case do
      nil -> nil
      {candidate, _score} -> candidate
    end
  end
end
