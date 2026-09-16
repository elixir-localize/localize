defmodule Localize.Utils.Helpers do
  # General purpose helper functions for Localize.
  #
  # Provides utility functions for checking empty data structures
  # and wrapping `:persistent_term` operations.
  #
  @moduledoc false

  @doc """
  Returns a boolean indicating if a data structure is semantically empty.

  ### Arguments

  * `value` — the value to check. Supported types are lists, maps, and `nil`.

  ### Returns

  * `true` if the value is an empty list, an empty map, or `nil`.

  * `false` otherwise.

  ### Examples

      iex> Localize.Utils.Helpers.empty?([])
      true

      iex> Localize.Utils.Helpers.empty?(%{})
      true

      iex> Localize.Utils.Helpers.empty?(nil)
      true

      iex> Localize.Utils.Helpers.empty?([1, 2])
      false

      iex> Localize.Utils.Helpers.empty?(%{a: 1})
      false

  """
  def empty?([]), do: true
  def empty?(%{} = map) when map == %{}, do: true
  def empty?(nil), do: true
  def empty?(_), do: false

  @doc false
  def get_term(key, default) do
    :persistent_term.get(key, default)
  end

  @doc false
  def put_term(key, value) do
    :persistent_term.put(key, value)
  end

  @doc """
  Converts a string to an existing atom, returning `nil` if the atom
  does not already exist in the atom table.

  This is the safe alternative to `String.to_existing_atom/1` that
  avoids using `try/rescue` as control flow.

  ### Arguments

  * `string` is a binary string.

  ### Returns

  * The atom if it exists, or `nil` otherwise.

  """
  @spec existing_atom(String.t()) :: atom() | nil
  def existing_atom(string) when is_binary(string) do
    :erlang.binary_to_existing_atom(string, :utf8)
  rescue
    ArgumentError -> nil
  end

  def existing_atom(_), do: nil

  @doc false
  # The error for options that are not a keyword list, as `Localize.Number`
  # reports it.
  @spec invalid_options(term()) :: Exception.t()
  def invalid_options(options) do
    Localize.InvalidValueError.exception(value: options, expected: "a keyword list of options")
  end

  @doc false
  # The error for an argument of the wrong type, naming the type expected.
  @spec invalid_value(term(), String.t()) :: Exception.t()
  def invalid_value(value, expected) do
    Localize.InvalidValueError.exception(value: value, expected: expected)
  end

  @doc false
  # Guards for a keyword list as a function head matches one,
  # `[{key, _value} | _rest] when is_atom(key)`, and also admits the empty
  # list, so a function whose options default to `[]` needs one clause.
  defguard is_keyword_list(options)
           when options == [] or
                  (is_list(options) and is_tuple(hd(options)) and tuple_size(hd(options)) == 2 and
                     is_atom(elem(hd(options), 0)))
end
