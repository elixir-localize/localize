defmodule Localize.Collation.Insensitive do
  # Case-insensitive string comparator for use with `Enum.sort/2`.
  #
  # Implements the `compare/2` callback so this module can be passed directly
  # to `Enum.sort/2` as a comparator:
  #
  #     Enum.sort(strings, Localize.Collation.Insensitive)
  #
  # Uses the NIF backend when available for maximum performance, otherwise
  # falls back to the pure Elixir implementation at secondary strength
  # (which ignores case distinctions).
  #
  @moduledoc false

  @doc """
  Compare two strings in a case-insensitive manner.

  ### Arguments

  * `string_a` - the first string to compare.

  * `string_b` - the second string to compare.

  ### Returns

  * `:lt` if `string_a` sorts before `string_b`.

  * `:eq` if `string_a` and `string_b` are collation-equal (ignoring case).

  * `:gt` if `string_a` sorts after `string_b`.

  ### Examples

      iex> Localize.Collation.Insensitive.compare("a", "A")
      :eq

      iex> Localize.Collation.Insensitive.compare("b", "a")
      :gt

  """
  @spec compare(String.t(), String.t()) :: :lt | :eq | :gt
  def compare(string_a, string_b) do
    if Localize.Collation.Nif.available?() do
      Localize.Collation.Nif.nif_compare(string_a, string_b, %Localize.Collation.Options{
        strength: :secondary
      })
    else
      Localize.Collation.compare(string_a, string_b, backend: :elixir, strength: :secondary)
    end
  end
end
