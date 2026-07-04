defmodule Localize.Collation.Sensitive do
  # Case-sensitive string comparator for use with `Enum.sort/2`.
  #
  # Implements the `compare/2` callback so this module can be passed directly
  # to `Enum.sort/2` as a comparator:
  #
  #     Enum.sort(strings, Localize.Collation.Sensitive)
  #
  # Uses the NIF backend when available for maximum performance, otherwise
  # falls back to the pure Elixir implementation at tertiary strength.
  #
  @moduledoc false

  @doc """
  Compare two strings in a case-sensitive manner.

  ### Arguments

  * `string_a` - the first string to compare.

  * `string_b` - the second string to compare.

  ### Returns

  * `:lt` if `string_a` sorts before `string_b`.

  * `:eq` if `string_a` and `string_b` are collation-equal.

  * `:gt` if `string_a` sorts after `string_b`.

  ### Examples

      iex> Localize.Collation.Sensitive.compare("a", "A")
      :lt

      iex> Localize.Collation.Sensitive.compare("b", "a")
      :gt

  """
  @spec compare(String.t(), String.t()) :: :lt | :eq | :gt
  def compare(string_a, string_b) do
    if Localize.Collation.Nif.available?() do
      Localize.Collation.Nif.nif_compare(string_a, string_b, %Localize.Collation.Options{})
    else
      Localize.Collation.compare(string_a, string_b, backend: :elixir)
    end
  end
end
