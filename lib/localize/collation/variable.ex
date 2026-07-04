defmodule Localize.Collation.Variable do
  # Variable weight handling for the collation algorithm.
  #
  # In the UCA, "variable" collation elements are those for spaces, punctuation,
  # and optionally symbols and currency signs. The `alternate` setting controls
  # how these are handled:
  #
  # * `:non_ignorable` - Variable CEs keep all their weights (default for CLDR).
  #
  # * `:shifted` - Variable CEs have L1/L2/L3 zeroed, original L1 moves to L4.
  #
  @moduledoc false

  alias Localize.Collation.Element

  @doc """
  Process a list of collation elements according to the variable weight rules.

  ### Arguments

  * `elements` - a list of collation element tuples.

  * `alternate` - the variable handling mode: `:non_ignorable` or `:shifted`.

  * `max_variable_primary` - the maximum primary weight for variable elements.

  ### Returns

  A list of `{element, quaternary_weight}` tuples.

  ### Examples

      iex> elems = [{0x23EC, 0x0020, 0x0002, false}]
      iex> [{elem, q}] = Localize.Collation.Variable.process(elems, :non_ignorable, 0x0B61)
      iex> {Localize.Collation.Element.primary(elem), q}
      {0x23EC, 0}

  """
  @spec process([Element.t()], :non_ignorable | :shifted, non_neg_integer()) ::
          [{Element.t(), non_neg_integer()}]
  def process(elements, :non_ignorable, _max_variable_primary) do
    Enum.map(elements, fn elem -> {elem, 0} end)
  end

  def process(elements, :shifted, max_variable_primary) do
    {result, _after_variable} =
      Enum.reduce(elements, {[], false}, fn elem, {acc, after_variable} ->
        cond do
          Element.variable?(elem, max_variable_primary) ->
            shifted = Element.new(0, 0, 0)
            {[{shifted, Element.primary(elem)} | acc], true}

          after_variable and Element.primary_ignorable?(elem) ->
            zeroed = Element.new(0, 0, 0)
            {[{zeroed, 0} | acc], true}

          true ->
            {[{elem, default_quaternary(elem)} | acc], false}
        end
      end)

    Enum.reverse(result)
  end

  defp default_quaternary(elem) do
    if Element.primary(elem) > 0, do: 0xFFFF, else: 0
  end
end
