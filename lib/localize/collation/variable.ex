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
  alias Localize.Collation.Reorder

  # Fractional {lead, sub} byte at which each reorder group starts,
  # from the FDD1 group-marker lines of the vendored FractionalUCA.txt
  # (e.g. "FDD1 201C; [05 06 02, 05, 05] # PUNCTUATION first primary").
  # Group boundaries are not lead-byte aligned, and the marker lines
  # are not carried in the collation ETF, so the starts are pinned
  # here like default_script_ranges/0 in Reorder. The behaviour tests
  # in options_test.exs detect a shift when the collation data is
  # regenerated; at the next regeneration these belong in the ETF.
  @group_starts %{
    "SPACE" => {0x03, 0x02},
    "PUNCTUATION" => {0x05, 0x06},
    "SYMBOL" => {0x0C, 0x02},
    "CURRENCY" => {0x0D, 0xA3},
    "DIGIT" => {0x0F, 0x02}
  }

  # The group that bounds each max_variable setting from above.
  @group_after %{
    space: "PUNCTUATION",
    punct: "SYMBOL",
    symbol: "CURRENCY",
    currency: "DIGIT"
  }

  @doc """
  Process a list of collation elements according to the variable weight rules.

  ### Arguments

  * `elements` - a list of collation element tuples.

  * `alternate` - the variable handling mode: `:non_ignorable` or `:shifted`.

  * `primary_range` - the `{min, max}` primary weight range for
    variable elements, from `primary_range/1`.

  ### Returns

  A list of `{element, quaternary_weight}` tuples.

  ### Examples

      iex> elems = [{0x23EC, 0x0020, 0x0002, false}]
      iex> [{elem, q}] = Localize.Collation.Variable.process(elems, :non_ignorable, {0x0209, 0x0B61})
      iex> {Localize.Collation.Element.primary(elem), q}
      {0x23EC, 0}

  """
  @spec process([Element.t()], :non_ignorable | :shifted, {pos_integer(), non_neg_integer()}) ::
          [{Element.t(), non_neg_integer()}]
  def process(elements, :non_ignorable, _primary_range) do
    Enum.map(elements, fn elem -> {elem, 0} end)
  end

  def process(elements, :shifted, primary_range) do
    {result, _after_variable} =
      Enum.reduce(elements, {[], false}, fn elem, {acc, after_variable} ->
        cond do
          Element.variable?(elem, primary_range) ->
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

  @doc """
  Returns the `{min, max}` table-primary range of variable elements
  for a `max_variable` setting.

  The range covers the reorder groups included by the setting
  (`:space`, then `:punct`, `:symbol` and `:currency` each widening
  it), computed from the collation table's fractional lead-byte
  group ranges. The result is cached in `:persistent_term` per
  setting.

  ### Arguments

  * `max_variable` - `:space`, `:punct`, `:symbol` or `:currency`.

  ### Returns

  * `{min_primary, max_primary}` bounding the variable elements, or
    `{1, 0}` (matching nothing) if the table has no such groups.

  """
  @spec primary_range(:space | :punct | :symbol | :currency) ::
          {pos_integer(), non_neg_integer()}
  def primary_range(max_variable) do
    pt_key = {__MODULE__, :primary_range, max_variable}

    case :persistent_term.get(pt_key, :__not_loaded__) do
      :__not_loaded__ ->
        range = compute_primary_range(max_variable)
        :persistent_term.put(pt_key, range)
        range

      range ->
        range
    end
  end

  defp compute_primary_range(max_variable) do
    lower = Map.fetch!(@group_starts, "SPACE")
    upper = Map.fetch!(@group_starts, Map.fetch!(@group_after, max_variable))
    frac_map = Reorder.load_primary_to_fractional_lead()

    bounds =
      Enum.reduce(frac_map, nil, fn
        {{:sub, _primary}, _sub}, acc ->
          acc

        {primary, lead}, acc ->
          frac = {lead, Map.get(frac_map, {:sub, primary}, 0)}
          accumulate_in_range(primary, frac >= lower and frac < upper, acc)
      end)

    bounds || {1, 0}
  end

  defp accumulate_in_range(_primary, false, acc), do: acc
  defp accumulate_in_range(primary, true, nil), do: {primary, primary}

  defp accumulate_in_range(primary, true, {min_primary, max_primary}) do
    {min(min_primary, primary), max(max_primary, primary)}
  end

  defp default_quaternary(elem) do
    if Element.primary(elem) > 0, do: 0xFFFF, else: 0
  end
end
