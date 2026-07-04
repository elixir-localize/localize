defmodule Localize.Utils.Enum do
  # Enumerable utility functions not provided in the standard library.
  #
  # Provides reduce with lookahead and list combination operations.
  #
  @moduledoc false

  @doc """
  Reduces a list with lookahead by passing both the current
  element and the remaining tail to the reducing function.

  The reducing function receives three arguments: the current element,
  the remaining tail of the list, and the accumulator. It should return
  a tagged tuple following the `Enumerable` protocol conventions:
  `{:cont, acc}`, `{:halt, acc}`, or `{:suspend, acc}`.

  ### Arguments

  * `list` — the list to reduce.

  * `accumulator` — the initial accumulator value, or a tagged tuple.

  * `function` — a function of arity 3: `(element, tail, accumulator)`.

  ### Returns

  * The final accumulator value.

  ### Examples

      iex> Localize.Utils.Enum.reduce_peeking([1, 2, 3], [], fn head, tail, acc ->
      ...>   {:cont, [{head, length(tail)} | acc]}
      ...> end)
      [{3, 0}, {2, 1}, {1, 2}]

  """
  def reduce_peeking(_list, {:halt, accumulator}, _function),
    do: {:halted, accumulator}

  def reduce_peeking(list, {:suspend, accumulator}, function),
    do: {:suspended, accumulator, &reduce_peeking(list, &1, function)}

  def reduce_peeking([], {:cont, accumulator}, _function),
    do: {:done, accumulator}

  def reduce_peeking([head | tail], {:cont, accumulator}, function),
    do: reduce_peeking(tail, function.(head, tail, accumulator), function)

  def reduce_peeking(list, accumulator, function),
    do: reduce_peeking(list, {:cont, accumulator}, function) |> elem(1)

  @doc """
  Combines list elements into progressively concatenated prefix strings.

  Each element in the result is the concatenation of all preceding
  elements joined by underscores.

  ### Arguments

  * `list` — a list of elements that can be converted to strings.

  ### Returns

  * A list of progressively combined strings.

  ### Examples

      iex> Localize.Utils.Enum.combine_list([:a, :b, :c])
      ["a", "a_b", "a_b_c"]

      iex> Localize.Utils.Enum.combine_list([])
      []

  """
  def combine_list([]),
    do: []

  def combine_list([head]),
    do: [to_string(head)]

  def combine_list([head | [next | tail]]),
    do: [to_string(head) | combine_list(["#{head}_#{next}" | tail])]
end
