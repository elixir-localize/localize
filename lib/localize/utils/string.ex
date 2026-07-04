defmodule Localize.Utils.String do
  # String manipulation functions not provided in the standard library.
  #
  # Provides utilities for hashing strings, converting between
  # naming conventions (camelCase to snake_case), and character
  # case conversion.
  #
  @moduledoc false

  @p 99_991
  @m trunc(1.0e9) + 9

  @doc """
  Hashes a string using a polynomial rolling hash function.

  See https://cp-algorithms.com/string/string-hashing.html for
  a description of the algorithm.

  ### Arguments

  * `string` — the string to hash.

  ### Returns

  * A non-negative integer hash value.

  ### Examples

      iex> Localize.Utils.String.hash("hello")
      61_454_117

  """
  @spec hash(String.t()) :: non_neg_integer()
  def hash(string) do
    {hash, _} =
      string
      |> String.to_charlist()
      |> Enum.reduce({0, 1}, fn char, {hash, p_pow} ->
        hash = rem(hash + char * p_pow, @m)
        p_pow = rem(p_pow * @p, @m)
        {hash, p_pow}
      end)

    hash
  end

  @doc """
  Replaces hyphens with underscores in a string.

  ### Arguments

  * `string` — the string to transform.

  ### Returns

  * A new string with all `"-"` characters replaced by `"_"`.

  ### Examples

      iex> Localize.Utils.String.to_underscore("this-one")
      "this_one"

  """
  @spec to_underscore(String.t()) :: String.t()
  def to_underscore(string) when is_binary(string) do
    String.replace(string, "-", "_")
  end

  @doc """
  Converts a CamelCase or PascalCase string or atom to snake_case.

  This is a modified version of `Macro.underscore/1` that correctly
  handles strings containing underscores between capitalized words
  (e.g., `"This_That"` becomes `"this_that"` instead of `"this__that"`).

  ### Arguments

  * `value` — an atom or string to convert.

  ### Returns

  * A snake_case string.

  ### Examples

      iex> Localize.Utils.String.underscore("HelloWorld")
      "hello_world"

      iex> Localize.Utils.String.underscore("This_That")
      "this_that"

  """
  @spec underscore(atom() | String.t()) :: String.t()
  def underscore(atom) when is_atom(atom) do
    "Elixir." <> rest = Atom.to_string(atom)
    underscore(rest)
  end

  def underscore(<<h, t::binary>>) do
    <<to_lower_char(h)>> <> do_underscore(t, h)
  end

  def underscore("") do
    ""
  end

  # h is upper case, next char is not uppercase, or a _ or .  => and prev != _
  defp do_underscore(<<h, t, rest::binary>>, prev)
       when h >= ?A and h <= ?Z and not (t >= ?A and t <= ?Z) and t != ?. and t != ?_ and
              prev != ?_ do
    <<?_, to_lower_char(h), t>> <> do_underscore(rest, t)
  end

  # h is uppercase, previous was not uppercase or _
  defp do_underscore(<<h, t::binary>>, prev)
       when h >= ?A and h <= ?Z and not (prev >= ?A and prev <= ?Z) and prev != ?_ do
    <<?_, to_lower_char(h)>> <> do_underscore(t, h)
  end

  # h is .
  defp do_underscore(<<?., t::binary>>, _) do
    <<?/>> <> underscore(t)
  end

  # Any other char
  defp do_underscore(<<h, t::binary>>, _) do
    <<to_lower_char(h)>> <> do_underscore(t, h)
  end

  defp do_underscore(<<>>, _) do
    <<>>
  end

  @doc """
  Converts a single character to its uppercase equivalent.

  Only operates on ASCII lowercase letters (a-z).

  ### Arguments

  * `char` — an integer codepoint.

  ### Returns

  * The uppercase codepoint if the input is a lowercase ASCII letter, otherwise the input unchanged.

  """
  @spec to_upper_char(integer()) :: integer()
  def to_upper_char(char) when char >= ?a and char <= ?z, do: char - 32
  def to_upper_char(char), do: char

  @doc """
  Converts a single character to its lowercase equivalent.

  Only operates on ASCII uppercase letters (A-Z).

  ### Arguments

  * `char` — an integer codepoint.

  ### Returns

  * The lowercase codepoint if the input is an uppercase ASCII letter, otherwise the input unchanged.

  """
  @spec to_lower_char(integer()) :: integer()
  def to_lower_char(char) when char >= ?A and char <= ?Z, do: char + 32
  def to_lower_char(char), do: char
end
