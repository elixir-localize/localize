defmodule Localize.Unit.Canonical do
  @moduledoc """
  Canonicalises CLDR unit identifier ASTs and names.

  Provides functions to sort unit components into CLDR canonical order
  (as defined by the `unitQuantity` simple base unit ordering in the
  supplemental units data), consolidate repeated terms, cross-cancel
  matching terms between numerator and denominator, and format the
  result as a canonical unit identifier string.

  """

  alias Localize.Unit.Data

  # ── Public API ──────────────────────────────────────────────────────

  @doc """
  Returns the canonical name and normalised AST for a parsed unit.

  The AST is normalised by sorting numerator and denominator
  components into CLDR canonical order.

  ### Arguments

  * `parsed` is a `{:unit, keyword}` AST as returned by the parser.

  ### Returns

  * `{canonical_name, normalised_ast}` where `canonical_name` is a
    string and `normalised_ast` has canonically ordered components.

  """
  @spec canonicalize(tuple()) :: {String.t(), tuple()}
  def canonicalize({:unit, kw}) do
    type = Keyword.get(kw, :type)
    numerator = Keyword.get(kw, :numerator, [])
    denominator = Keyword.get(kw, :denominator, [])

    sorted_num = canonical_sort(numerator)
    sorted_den = canonical_sort(denominator)

    canonical_name = format_name(sorted_num, sorted_den)

    normalised_ast =
      {:unit, type: type, numerator: sorted_num, denominator: sorted_den}

    {canonical_name, normalised_ast}
  end

  def canonicalize({:mixed_unit, units}) do
    # Mixed units keep their order (larger unit first per CLDR spec).
    # Each component is formatted individually and joined with "-and-".
    canonical_name =
      units
      |> Enum.map(&format_single_unit/1)
      |> Enum.join("-and-")

    {canonical_name, {:mixed_unit, units}}
  end

  @doc """
  Builds a canonical name and normalised AST from raw numerator and
  denominator component lists.

  Applies consolidation of duplicate terms, cross-cancellation of
  matching terms, and canonical sorting before formatting.

  ### Arguments

  * `numerator` is a list of single_unit or constant AST tuples.

  * `denominator` is a list of single_unit or constant AST tuples.

  ### Returns

  * `{canonical_name, normalised_ast}` or `{:dimensionless, nil}`
    when all units cancel.

  """
  @spec from_components(list(), list()) :: {:dimensionless, nil} | {String.t(), tuple()}
  def from_components(numerator, denominator) do
    consolidated_num = consolidate_units(numerator)
    consolidated_den = consolidate_units(denominator)

    {cancelled_num, cancelled_den} = cross_cancel(consolidated_num, consolidated_den)

    sorted_num = canonical_sort(cancelled_num)
    sorted_den = canonical_sort(cancelled_den)

    name = format_name(sorted_num, sorted_den)

    if name == "" do
      {:dimensionless, nil}
    else
      ast = {:unit, type: nil, numerator: sorted_num, denominator: sorted_den}
      {name, ast}
    end
  end

  # ── Formatting ─────────────────────────────────────────────────────

  @doc false
  def format_name(numerator, denominator) do
    num_str = format_unit_list(numerator)
    den_str = format_unit_list(denominator)

    case {num_str, den_str} do
      {"", ""} -> ""
      {num, ""} -> num
      {"", den} -> "per-" <> den
      {num, den} -> num <> "-per-" <> den
    end
  end

  defp format_unit_list([]), do: ""

  defp format_unit_list(units) do
    units
    |> Enum.map(&format_single_unit/1)
    |> Enum.join("-")
  end

  defp format_single_unit({:single_unit, opts}) do
    power = Keyword.get(opts, :power)
    prefix = Keyword.get(opts, :prefix)
    base = Keyword.get(opts, :base)

    power_str =
      case power do
        nil -> ""
        :square -> "square-"
        :cubic -> "cubic-"
        {:pow, n} -> "pow#{n}-"
      end

    prefix_str =
      case prefix do
        nil -> ""
        atom -> Atom.to_string(atom)
      end

    "#{power_str}#{prefix_str}#{base}"
  end

  defp format_single_unit({:constant, value}), do: value

  # ── Canonical sorting ──────────────────────────────────────────────

  # The canonical order of simple base units from CLDR unitQuantities.
  # Units are sorted by the position of their base in this list.
  # Units not in this list sort to the end, using base name as tiebreaker.
  @canonical_order Data.simple_base_units()
                   |> Enum.with_index()
                   |> Map.new()

  defp canonical_sort(units) do
    Enum.sort_by(units, fn
      {:single_unit, opts} ->
        base = Keyword.get(opts, :base)
        {Map.get(@canonical_order, base, map_size(@canonical_order)), base}

      {:constant, _} ->
        {map_size(@canonical_order) + 1, ""}
    end)
  end

  # ── Consolidation ──────────────────────────────────────────────────

  # Consolidate duplicate single_units by summing their powers.
  # Units are identified by their {prefix, base} pair.
  # Constants pass through unchanged.
  defp consolidate_units(units) do
    {constants, single_units} =
      Enum.split_with(units, fn
        {:constant, _} -> true
        _ -> false
      end)

    consolidated =
      single_units
      |> Enum.reduce([], fn {:single_unit, opts}, acc ->
        key = {Keyword.get(opts, :prefix), Keyword.get(opts, :base)}
        power = power_to_integer(Keyword.get(opts, :power))

        case List.keyfind(acc, key, 0) do
          nil ->
            [{key, power, opts} | acc]

          {^key, existing_power, existing_opts} ->
            updated = {key, existing_power + power, existing_opts}
            List.keyreplace(acc, key, 0, updated)
        end
      end)
      |> Enum.reverse()
      |> Enum.map(fn {_key, total_power, opts} ->
        {:single_unit, Keyword.put(opts, :power, integer_to_power(total_power))}
      end)

    consolidated ++ constants
  end

  # ── Cross-cancellation ─────────────────────────────────────────────

  # Cross-cancel matching single_units between numerator and denominator.
  # For each {prefix, base} that appears in both lists, subtract the
  # denominator power from the numerator power:
  #   - positive remainder stays in the numerator
  #   - negative remainder (abs value) stays in the denominator
  #   - zero means complete cancellation (removed from both)
  # Preserves the original order of units from the input lists.
  # Constants are never cancelled.
  defp cross_cancel(numerator, denominator) do
    {num_constants, num_singles} = split_constants(numerator)
    {den_constants, den_singles} = split_constants(denominator)

    den_map = units_to_power_map(den_singles)

    # Walk numerator in order, cancelling against denominator powers
    {final_num, remaining_den_map} =
      Enum.reduce(num_singles, {[], den_map}, fn {:single_unit, opts}, {num_acc, d_map} ->
        key = {Keyword.get(opts, :prefix), Keyword.get(opts, :base)}
        num_power = power_to_integer(Keyword.get(opts, :power))

        case Map.get(d_map, key) do
          nil ->
            {[{:single_unit, opts} | num_acc], d_map}

          {den_power, _den_opts} ->
            net = num_power - den_power
            updated_d_map = Map.delete(d_map, key)

            cond do
              net > 0 ->
                unit = {:single_unit, Keyword.put(opts, :power, integer_to_power(net))}
                {[unit | num_acc], updated_d_map}

              net < 0 ->
                # Remainder goes back to denominator map with updated power
                {num_acc, Map.put(updated_d_map, key, {abs(net), opts})}

              true ->
                {num_acc, updated_d_map}
            end
        end
      end)

    # Remaining denominator entries that were not cancelled, in original order
    final_den =
      den_singles
      |> Enum.filter(fn {:single_unit, opts} ->
        key = {Keyword.get(opts, :prefix), Keyword.get(opts, :base)}
        Map.has_key?(remaining_den_map, key)
      end)
      |> Enum.map(fn {:single_unit, opts} ->
        key = {Keyword.get(opts, :prefix), Keyword.get(opts, :base)}
        {power, _opts} = Map.get(remaining_den_map, key)
        {:single_unit, Keyword.put(opts, :power, integer_to_power(power))}
      end)

    {Enum.reverse(final_num) ++ num_constants, final_den ++ den_constants}
  end

  defp split_constants(units) do
    Enum.split_with(units, fn
      {:constant, _} -> true
      _ -> false
    end)
  end

  defp units_to_power_map(single_units) do
    Map.new(single_units, fn {:single_unit, opts} ->
      key = {Keyword.get(opts, :prefix), Keyword.get(opts, :base)}
      power = power_to_integer(Keyword.get(opts, :power))
      {key, {power, opts}}
    end)
  end

  # ── Power helpers ──────────────────────────────────────────────────

  defp power_to_integer(nil), do: 1
  defp power_to_integer(:square), do: 2
  defp power_to_integer(:cubic), do: 3
  defp power_to_integer({:pow, n}), do: n

  defp integer_to_power(1), do: nil
  defp integer_to_power(2), do: :square
  defp integer_to_power(3), do: :cubic
  defp integer_to_power(n), do: {:pow, n}
end
