defmodule Localize.Collation.Han do
  # Han character ordering using radical-stroke indexes.
  #
  # Implements the sorting algorithm from UAX #38, computing 64-bit
  # collation keys based on radical number, residual stroke count,
  # simplification level, Unicode block, and code point value.
  #
  # The radical data is pre-parsed from `FractionalUCA.txt`'s
  # `[radical N=...]` entries during the build pipeline and shipped
  # in `priv/localize/collation_table.etf`. At runtime it lives in
  # `:persistent_term` and is loaded alongside the main collation
  # table by `Localize.Collation.Table`.
  #
  @moduledoc false

  import Bitwise
  alias Localize.Collation.Element

  @han_radicals_key {:localize, :collation_han_radicals}

  @block_cjk_unified 0
  @block_ext_a 1
  @block_ext_b 2
  @block_ext_c 3
  @block_ext_d 4
  @block_ext_e 5
  @block_ext_f 6
  @block_ext_g 7
  @block_ext_h 8
  @block_compat 254

  @doc """
  Ensure the Han radical data is available.

  The data is loaded as a side-effect of `Localize.Collation.Table.ensure_loaded/0`
  because both share the same pre-generated ETF.

  ### Returns

  * `:ok` — the radical data is loaded and ready.

  """
  @spec ensure_loaded() :: :ok
  def ensure_loaded do
    Localize.Collation.Table.ensure_loaded()
  end

  @doc """
  Compute collation elements for a Han character using radical-stroke ordering.

  ### Arguments

  * `codepoint` — an integer codepoint for a CJK Unified Ideograph.

  ### Returns

  * `[element, element]` — two CEs encoding the radical-stroke key.

  * `nil` — if the character has no radical data.

  """
  @spec collation_elements(non_neg_integer()) :: [Element.t()] | nil
  def collation_elements(codepoint) do
    case :persistent_term.get(@han_radicals_key, nil) do
      nil ->
        nil

      radicals ->
        case Map.get(radicals, codepoint) do
          {radical, residual_strokes, simplification} ->
            block = block_index(codepoint)
            key = compute_key(radical, residual_strokes, simplification, block, codepoint)
            key_to_elements(key)

          nil ->
            nil
        end
    end
  end

  @doc """
  Compute the 64-bit sorting key per UAX #38.

  ### Arguments

  * `radical` — the Kangxi radical number (1-214).

  * `residual_strokes` — the residual stroke count after removing the radical.

  * `simplification` — the simplification level (0 for traditional).

  * `block` — the CJK block index.

  * `codepoint` — the Unicode codepoint.

  ### Returns

  A 64-bit integer encoding all components of the radical-stroke sort key.

  ### Examples

      iex> Localize.Collation.Han.compute_key(1, 0, 0, 0, 0x4E00)
      17592186064384

  """
  @spec compute_key(
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer()
        ) :: non_neg_integer()
  def compute_key(radical, residual_strokes, simplification, block, codepoint) do
    radical <<< 44 |||
      residual_strokes <<< 36 |||
      simplification <<< 28 |||
      block <<< 20 |||
      codepoint
  end

  @doc """
  Convert a 64-bit radical-stroke key to two collation elements.

  ### Arguments

  * `key` — a 64-bit integer radical-stroke key from `compute_key/5`.

  ### Returns

  A list of two element tuples.

  """
  @spec key_to_elements(non_neg_integer()) :: [Element.t()]
  def key_to_elements(key) do
    high = key >>> 16
    low = key &&& 0xFFFF

    [
      Element.new(0xFB40 + (high >>> 16), 0x0020, 0x0002),
      Element.new(low ||| 0x8000, 0x0000, 0x0000)
    ]
  end

  @doc """
  Get the CJK block index for a codepoint.

  ### Arguments

  * `cp` — an integer codepoint.

  ### Returns

  An integer block index.

  ### Examples

      iex> Localize.Collation.Han.block_index(0x4E00)
      0

      iex> Localize.Collation.Han.block_index(0x3400)
      1

  """
  @spec block_index(non_neg_integer()) :: non_neg_integer()
  # UTS #10 Han implicit weights: one cond branch per CJK Unicode block.
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  def block_index(cp) do
    cond do
      cp >= 0x4E00 and cp <= 0x9FFF -> @block_cjk_unified
      cp >= 0x3400 and cp <= 0x4DBF -> @block_ext_a
      cp >= 0x20000 and cp <= 0x2A6DF -> @block_ext_b
      cp >= 0x2A700 and cp <= 0x2B81D -> @block_ext_c
      cp >= 0x2B820 and cp <= 0x2CEAD -> @block_ext_d
      cp >= 0x2CEB0 and cp <= 0x2EBE0 -> @block_ext_e
      cp >= 0x2EBF0 and cp <= 0x2EE5D -> @block_ext_f
      cp >= 0x30000 and cp <= 0x3134A -> @block_ext_g
      cp >= 0x31350 and cp <= 0x33479 -> @block_ext_h
      cp >= 0xF900 and cp <= 0xFAFF -> @block_compat
      true -> @block_cjk_unified
    end
  end

  @doc """
  Parse a radical definition line from FractionalUCA.txt.

  This function is used by the build pipeline (`data/collation.ex`)
  to extract radical data from the CLDR source file. It is a pure
  parser and does no I/O.

  ### Arguments

  * `line` — a trimmed line from FractionalUCA.txt.

  ### Returns

  * `{:ok, radical_num, members}` — the radical number and member list.

  * `:skip` — the line is not a radical definition.

  """
  @spec parse_radical_line(String.t()) ::
          {:ok, pos_integer(), [{non_neg_integer(), non_neg_integer(), non_neg_integer()}]}
          | :skip
  def parse_radical_line(line) do
    case Regex.run(~r/^\[radical (\d+)=.+?:(.+)\]$/, line) do
      [_, num_str, members_str] ->
        radical_num = String.to_integer(num_str)
        members = parse_radical_members(members_str, radical_num)
        {:ok, radical_num, members}

      _ ->
        :skip
    end
  end

  # CLDR lists members within each `[radical N=R:members]` line in
  # UAX #38 radical-stroke order, so a member's 0-based position within
  # that list is a faithful sort rank: lower index = fewer residual
  # strokes. We use the index directly as the "residual_strokes" field
  # fed into `compute_key/5`, giving correct within-radical ordering.
  # (Across radicals, `radical` is the primary ranking factor, so exact
  # stroke counts aren't needed — just the relative order within a
  # radical, which is what the index provides.)
  defp parse_radical_members(str, _radical_num) do
    chars = String.to_charlist(str)
    members_no_rank = parse_member_chars(chars, [])
    # Assign rank by position (clamped to the field width available in
    # the compute_key encoding, which gives 8 bits for residual strokes).
    members_no_rank
    |> Enum.with_index()
    |> Enum.map(fn {{cp, simp}, idx} -> {cp, simp, min(idx, 0xFF)} end)
  end

  defp parse_member_chars([], acc) do
    Enum.reverse(acc)
  end

  defp parse_member_chars([cp | rest], acc) when cp == ?- do
    case {acc, rest} do
      {[{prev_cp, simp} | _acc_rest], [next_cp | rest2]} ->
        # Expand range (prev_cp+1..next_cp), preserving prev_cp already in acc.
        range_entries = for c <- (prev_cp + 1)..next_cp, do: {c, simp}
        parse_member_chars(rest2, Enum.reverse(range_entries) ++ acc)

      _ ->
        parse_member_chars(rest, acc)
    end
  end

  defp parse_member_chars([cp | rest], acc) do
    parse_member_chars(rest, [{cp, 0} | acc])
  end
end
