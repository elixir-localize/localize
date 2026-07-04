defmodule Localize.Collation.Normalizer do
  # Unicode NFD normalization for collation.
  # Delegates to Erlang's `:unicode` module.
  #
  @moduledoc false

  @doc """
  Normalize a string to NFD (Canonical Decomposition) form.

  Uses Erlang's `:unicode.characters_to_nfd_binary/1` followed by a canonical
  reordering pass using the `unicode` package's CCC data to correct ordering
  for newer Unicode codepoints.

  ### Arguments

  * `string` - a UTF-8 binary string.

  ### Returns

  The NFD-normalized string as a UTF-8 binary.

  ### Examples

      iex> "café" |> Localize.Collation.Normalizer.nfd() |> String.to_charlist() |> length()
      5

      iex> Localize.Collation.Normalizer.nfd("e\u0301")
      "e\u0301"

  """
  @spec nfd(String.t()) :: String.t()
  def nfd(string) when is_binary(string) do
    string
    |> :unicode.characters_to_nfd_binary()
    |> String.to_charlist()
    |> canonical_reorder()
    |> List.to_string()
  end

  @doc """
  Convert a string to a list of integer codepoints.

  ### Arguments

  * `string` - a UTF-8 binary string.

  ### Returns

  A list of integer codepoints.

  ### Examples

      iex> Localize.Collation.Normalizer.to_codepoints("abc")
      [97, 98, 99]

  """
  @spec to_codepoints(String.t()) :: [non_neg_integer(), ...]
  def to_codepoints(string) when is_binary(string) do
    String.to_charlist(string)
  end

  @doc """
  Optionally normalize a string and convert it to a list of integer codepoints.

  ### Arguments

  * `string` - a UTF-8 binary string.

  * `normalize?` - whether to apply NFD normalization first (default: `false`).

  ### Returns

  A list of integer codepoints, optionally NFD-normalized.

  ### Examples

      iex> Localize.Collation.Normalizer.normalize_to_codepoints("abc")
      [97, 98, 99]

      iex> Localize.Collation.Normalizer.normalize_to_codepoints("café", true)
      [99, 97, 102, 101, 769]

  """
  @spec normalize_to_codepoints(String.t(), boolean()) :: [non_neg_integer()]
  def normalize_to_codepoints(string, normalize? \\ false) do
    string
    |> then(fn s -> if normalize?, do: nfd(s), else: s end)
    |> to_codepoints()
  end

  defp canonical_reorder(codepoints) do
    case reorder_pass(codepoints, false) do
      {result, true} -> canonical_reorder(result)
      {result, false} -> result
    end
  end

  defp reorder_pass([a, b | rest], swapped) do
    ccc_a = combining_class(a)
    ccc_b = combining_class(b)

    if ccc_a > ccc_b and ccc_b > 0 do
      {tail, s} = reorder_pass([a | rest], true)
      {[b | tail], s}
    else
      {tail, s} = reorder_pass([b | rest], swapped)
      {[a | tail], s}
    end
  end

  defp reorder_pass([cp], swapped), do: {[cp], swapped}
  defp reorder_pass([], swapped), do: {[], swapped}

  defp combining_class(cp) do
    Localize.Collation.Unicode.combining_class(cp)
  end
end
