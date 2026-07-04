defmodule Localize.Collation.Numeric do
  # Numeric collation support (kn=true / numeric=true).
  #
  # When enabled, sequences of decimal digits are treated as numeric values
  # for primary sorting, ensuring "file2" sorts before "file10".
  #
  # The numeric value is encoded as a length-prefixed big-endian number
  # in the primary weight.
  @moduledoc false

  alias Localize.Collation.Element
  alias Localize.Collation.Unicode

  @doc """
  Process codepoint/element pairs, replacing digit sequence CEs with
  numeric-value-based CEs.

  ### Arguments

  * `ce_pairs` - a list of `{codepoints, [element]}` pairs.

  ### Returns

  A flat list of element structs with digit sequences replaced
  by numeric collation elements.

  ### Examples

      iex> pairs = [{[0x31], [{0x21E7, 0x0020, 0x0002, false}]}, {[0x30], [{0x21E6, 0x0020, 0x0002, false}]}]
      iex> result = Localize.Collation.Numeric.process_elements(pairs)
      iex> length(result)
      3

  """
  @spec process_elements([{[non_neg_integer()], [Element.t()]}]) :: [Element.t()]
  def process_elements(ce_pairs) do
    ce_pairs
    |> group_digit_runs()
    |> Enum.flat_map(fn
      {:digits, codepoints} ->
        encode_numeric_value(codepoints)

      {:other, elements} ->
        elements
    end)
  end

  defp group_digit_runs(ce_pairs) do
    {groups, current} =
      Enum.reduce(ce_pairs, {[], nil}, fn {cps, elements}, {groups, current} ->
        if digit_codepoints?(cps) do
          add_digit_run(current, cps, groups)
        else
          add_other_run(current, elements, groups)
        end
      end)

    result = if current, do: [current | groups], else: groups
    Enum.reverse(result)
  end

  defp add_digit_run({:digits, acc_cps}, cps, groups), do: {groups, {:digits, acc_cps ++ cps}}
  defp add_digit_run(nil, cps, groups), do: {groups, {:digits, cps}}
  defp add_digit_run(other, cps, groups), do: {[other | groups], {:digits, cps}}

  defp add_other_run(nil, elements, groups), do: {groups, {:other, elements}}

  defp add_other_run({:other, acc_elems}, elements, groups),
    do: {groups, {:other, acc_elems ++ elements}}

  defp add_other_run(digit_group, elements, groups),
    do: {[digit_group | groups], {:other, elements}}

  defp digit_codepoints?(cps) do
    Enum.all?(cps, fn cp ->
      (cp >= 0x0030 and cp <= 0x0039) or
        Unicode.decimal_digit?(cp)
    end)
  end

  @doc """
  Encode a sequence of digit codepoints as numeric collation elements.

  ### Arguments

  * `codepoints` - a list of integer codepoints representing decimal digits.

  ### Returns

  A list of elements: one length-prefix CE followed by one CE per significant digit.

  ### Examples

      iex> result = Localize.Collation.Numeric.encode_numeric_value([0x31, 0x30])
      iex> length(result)
      3

  """
  def encode_numeric_value(codepoints) do
    digits =
      Enum.map(codepoints, fn cp ->
        if cp >= 0x0030 and cp <= 0x0039 do
          cp - 0x0030
        else
          numeric_digit_value(cp)
        end
      end)

    digits = strip_leading_zeros(digits)
    len = length(digits)
    digit_base = 0x21E6

    length_ce = Element.new(digit_base + len, 0x0020, 0x0002)

    digit_ces =
      Enum.map(digits, fn d ->
        Element.new(digit_base + d, 0x0020, 0x0002)
      end)

    [length_ce | digit_ces]
  end

  defp strip_leading_zeros([0]), do: [0]
  defp strip_leading_zeros([0 | rest]), do: strip_leading_zeros(rest)
  defp strip_leading_zeros(digits), do: digits

  defp numeric_digit_value(cp) when cp >= 0x0030 and cp <= 0x0039, do: cp - 0x0030

  # Non-ASCII decimal digits take their value from the offset within
  # their Unicode decimal digit block, which always starts at the digit
  # zero. `rem(cp, 10)` would be wrong: the blocks are not aligned
  # modulo 10 (Arabic-Indic zero is U+0660, which is 2 mod 10).
  defp numeric_digit_value(cp) do
    Unicode.decimal_digit_value(cp) || 0
  end
end
