defmodule Localize.Utils.Helpers do
  @moduledoc """
  General purpose helper functions for Localize.

  Provides utility functions for checking empty data structures
  and wrapping `:persistent_term` operations.

  """

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
end
