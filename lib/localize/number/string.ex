defmodule Localize.Number.String do
  @moduledoc false

  # String utilities for number formatting.
  # Provides padding, chunking, and character classification
  # functions used by the number formatters.

  # # latin1/0
  # Returns a regex matching all Latin-1 characters.
  @latin1 "([\\x00-\\x7F])"
  def latin1, do: ~r/#{@latin1}/

  # # not_latin1/0
  # Returns a regex matching all non-Latin-1 characters.
  @not_latin1 "([^\\x00-\\x7F])"
  def not_latin1, do: ~r/#{@not_latin1}/

  # # hex_string/1
  # Converts a string to hex escape representation.
  #
  # ### Arguments
  # * `string` is any string.
  #
  # ### Returns
  # * A string of hex escape sequences.
  def hex_string(string) do
    String.to_charlist(string)
    |> Enum.map_join(&("\\x" <> Integer.to_string(&1)))
  end

  # # pad_leading_zeros/2
  # Pads a number string with leading "0"s to the specified length.
  #
  # ### Arguments
  # * `number_string` is a string representation of a number.
  # * `count` is the final length required.
  #
  # ### Returns
  # * The padded string.
  @spec pad_leading_zeros(String.t(), integer()) :: String.t()
  def pad_leading_zeros(number_string, count) when count <= 0 do
    number_string
  end

  def pad_leading_zeros(number_string, count) do
    :binary.copy("0", count - byte_size(number_string)) <> number_string
  end

  # # pad_trailing_zeros/2
  # Pads a number string with trailing "0"s to the specified length.
  #
  # ### Arguments
  # * `number_string` is a string representation of a number.
  # * `count` is the final length required.
  #
  # ### Returns
  # * The padded string.
  @spec pad_trailing_zeros(String.t(), integer()) :: String.t()
  def pad_trailing_zeros(number_string, count) when count <= 0 do
    number_string
  end

  def pad_trailing_zeros(number_string, count) do
    number_string <> :binary.copy("0", count - byte_size(number_string))
  end

  # # chunk_string/3
  # Splits a string into fixed-size chunks.
  #
  # ### Arguments
  # * `string` is the string to split.
  # * `size` is the chunk size.
  # * `direction` is `:forward` (default) or `:reverse`.
  #
  # ### Returns
  # * A list of string chunks.
  #
  # ### Examples
  #     iex> Localize.Number.String.chunk_string("This is a string", 3)
  #     ["Thi", "s i", "s a", " st", "rin", "g"]
  #
  #     iex> Localize.Number.String.chunk_string("1234", 3, :reverse)
  #     ["1", "234"]
  @spec chunk_string(String.t(), integer(), :forward | :reverse) :: [String.t()]
  def chunk_string(string, size, direction \\ :forward)

  def chunk_string(string, 0, _direction), do: [string]
  def chunk_string("", _size, _direction), do: [""]

  def chunk_string(string, size, :forward) do
    string
    |> String.to_charlist()
    |> Enum.chunk_every(size, size, [])
    |> Enum.map(&List.to_string/1)
  end

  def chunk_string(string, size, :reverse) do
    length = String.length(string)
    remainder = rem(length, size)

    if remainder > 0 do
      {head, last} = String.split_at(string, remainder)
      [head | do_chunk_string(last, size)]
    else
      do_chunk_string(string, size)
    end
  end

  defp do_chunk_string("", _size), do: []

  defp do_chunk_string(string, size) do
    {chunk, rest} = String.split_at(string, size)
    [chunk | do_chunk_string(rest, size)]
  end
end
