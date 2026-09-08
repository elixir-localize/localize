defmodule Localize.Inflection.Lexicon do
  @moduledoc false

  # A packed, read-only lexicon: surface form to `{mask, pattern_indexes}`.
  #
  # The natural representation is a map, but a map of a million entries
  # costs roughly seven times its own data in BEAM structure — HAMT
  # nodes, binary headers, value tuples and list cells, paid once per
  # entry. German holds 1.28M entries in 123 MB while its key bytes
  # total 16 MB. Packing the same content into a handful of binaries
  # recovers that overhead: measured ~8.8x smaller across a spread of
  # locales (see plans/INFLECTION_LEXICON_PACKING.md).
  #
  # Three ideas do the work:
  #
  #   * Keys are sorted and front-coded — each key stores only the
  #     bytes it does not share with its predecessor. Inflected forms
  #     of a lemma sort adjacently and share long stems, so this
  #     compresses keys 2-5x.
  #
  #   * Values are interned. German has 6,836 distinct values across
  #     1.28M entries, so entries store a value number rather than the
  #     value. Where dedup is absent (Arabic, Hebrew — root-and-pattern
  #     morphology) this is a wash rather than a loss, so it is applied
  #     unconditionally and there is one code path.
  #
  #   * Everything is a binary. Binaries over ~64 bytes live off-heap
  #     and are shared, so the per-entry term overhead disappears.
  #
  # Lookup binary-searches a block index, then linearly decodes at most
  # `@block_size` front-coded keys within the block. That is O(log n)
  # plus a short scan rather than the map's near-O(1), which is an
  # acceptable trade at a few microseconds per call: inflection lookups
  # happen per word while formatting, not in a tight inner loop.

  import Bitwise

  defstruct keys: <<>>,
            blocks: <<>>,
            values: <<>>,
            value_offsets: <<>>,
            ord_to_value: <<>>,
            entry_count: 0,
            value_count: 0,
            mask_width: 1,
            index_width: 1,
            value_width: 1,
            block_size: 32

  # Keys per block. Larger blocks shrink the block index and improve
  # front-coding (fewer keys forced to store their full bytes at a
  # block boundary), at the cost of more linear decoding per lookup.
  @block_size 32

  @doc """
  Packs a `%{surface_form => {mask, pattern_indexes}}` map.

  """
  # Already packed — generated artifacts ship this form. Idempotent so
  # a caller cannot accidentally pack a struct (which is also a map,
  # and would otherwise fall into the clause below).
  def pack(%__MODULE__{} = lexicon), do: lexicon

  def pack(lexicon) when is_map(lexicon) do
    entries = Enum.sort_by(Map.to_list(lexicon), &elem(&1, 0))
    {value_list, value_numbers} = number_values(entries)

    value_count = length(value_list)
    mask_width = byte_width(Enum.reduce(value_list, 0, fn {mask, _}, acc -> max(acc, mask) end))

    index_width =
      byte_width(
        Enum.reduce(value_list, 0, fn {_, indexes}, acc ->
          Enum.reduce(indexes, acc, &max(&1, &2))
        end)
      )

    value_width = byte_width(max(value_count - 1, 0))
    {keys, blocks} = build_keys(entries)
    {values, value_offsets} = build_values(value_list, mask_width, index_width)

    %__MODULE__{
      keys: keys,
      blocks: blocks,
      values: values,
      value_offsets: value_offsets,
      ord_to_value: build_ord_to_value(entries, value_numbers, value_width),
      entry_count: map_size(lexicon),
      value_count: value_count,
      mask_width: mask_width,
      index_width: index_width,
      value_width: value_width,
      block_size: @block_size
    }
  end

  @doc """
  Returns the number of entries.

  """
  def size(%__MODULE__{entry_count: count}), do: count

  @doc """
  Returns every entry as a `{word, {mask, pattern_indexes}}` list, in
  sorted key order.

  Decodes the front-coded keys sequentially, which is a different path
  from the binary search `lookup/2` uses — the test suite plays the two
  against each other.

  """
  def to_list(%__MODULE__{entry_count: 0}), do: []

  def to_list(%__MODULE__{} = lexicon) do
    decode_all(lexicon.keys, <<>>, 0, lexicon, [])
  end

  defp decode_all(_rest, _previous, index, %{entry_count: count}, acc) when index >= count do
    Enum.reverse(acc)
  end

  defp decode_all(rest, previous, index, lexicon, acc) do
    {prefix, rest} = unvarint(rest)
    {length, rest} = unvarint(rest)
    <<suffix::binary-size(^length), rest::binary>> = rest
    key = binary_part(previous, 0, prefix) <> suffix

    decode_all(rest, key, index + 1, lexicon, [{key, value_at(lexicon, index)} | acc])
  end

  @doc """
  Looks up `word`, returning `{mask, pattern_indexes}` or nil.

  """
  def lookup(%__MODULE__{entry_count: 0}, _word), do: nil

  def lookup(%__MODULE__{} = lexicon, word) when is_binary(word) do
    case find_block(lexicon, word) do
      nil ->
        nil

      block ->
        case scan_block(lexicon, block, word) do
          nil -> nil
          ordinal -> value_at(lexicon, ordinal)
        end
    end
  end

  # The rightmost block whose first key sorts at or before `word`, or
  # nil when `word` sorts before every key.
  defp find_block(lexicon, word) do
    count = div(byte_size(lexicon.blocks), 4)

    if count == 0 or first_key(lexicon, 0) > word do
      nil
    else
      find_block(lexicon, word, 0, count - 1)
    end
  end

  defp find_block(_lexicon, _word, low, high) when low >= high, do: low

  defp find_block(lexicon, word, low, high) do
    # Upper midpoint: `low` is already known to satisfy the predicate,
    # so rounding down could revisit it forever.
    middle = div(low + high + 1, 2)

    if first_key(lexicon, middle) <= word do
      find_block(lexicon, word, middle, high)
    else
      find_block(lexicon, word, low, middle - 1)
    end
  end

  defp first_key(lexicon, block) do
    rest = from_offset(lexicon.keys, block_offset(lexicon, block))
    {_prefix, rest} = unvarint(rest)
    {length, rest} = unvarint(rest)
    binary_part(rest, 0, length)
  end

  defp block_offset(lexicon, block) do
    <<offset::unsigned-big-32>> = binary_part(lexicon.blocks, block * 4, 4)
    offset
  end

  # Decodes the block's keys in order, rebuilding each from the running
  # prefix, and stops as soon as a key sorts past `word`.
  defp scan_block(lexicon, block, word) do
    base = block * lexicon.block_size
    count = min(lexicon.block_size, lexicon.entry_count - base)
    rest = from_offset(lexicon.keys, block_offset(lexicon, block))

    scan_keys(rest, <<>>, 0, count, base, word)
  end

  defp scan_keys(_rest, _previous, index, count, _base, _word) when index >= count, do: nil

  defp scan_keys(rest, previous, index, count, base, word) do
    {prefix, rest} = unvarint(rest)
    {length, rest} = unvarint(rest)
    <<suffix::binary-size(^length), rest::binary>> = rest
    key = binary_part(previous, 0, prefix) <> suffix

    cond do
      key == word -> base + index
      key > word -> nil
      true -> scan_keys(rest, key, index + 1, count, base, word)
    end
  end

  defp value_at(lexicon, ordinal) do
    value_bits = lexicon.value_width * 8

    <<number::unsigned-big-size(^value_bits)>> =
      binary_part(lexicon.ord_to_value, ordinal * lexicon.value_width, lexicon.value_width)

    <<offset::unsigned-big-32>> = binary_part(lexicon.value_offsets, number * 4, 4)

    mask_bits = lexicon.mask_width * 8
    <<mask::unsigned-big-size(^mask_bits), rest::binary>> = from_offset(lexicon.values, offset)
    {count, rest} = unvarint(rest)

    {mask, decode_indexes(rest, count, lexicon.index_width, [])}
  end

  defp decode_indexes(_rest, 0, _width, acc), do: Enum.reverse(acc)

  defp decode_indexes(rest, count, width, acc) do
    bits = width * 8
    <<index::unsigned-big-size(^bits), rest::binary>> = rest
    decode_indexes(rest, count - 1, width, [index | acc])
  end

  # A sub-binary from `offset` to the end. Sub-binaries reference the
  # original rather than copying, so this is cheap.
  defp from_offset(binary, offset) do
    binary_part(binary, offset, byte_size(binary) - offset)
  end

  # Numbers the distinct values in order of first appearance, which is
  # deterministic because the entries are sorted by key.
  defp number_values(entries) do
    {reversed, numbers, _next} =
      Enum.reduce(entries, {[], %{}, 0}, fn {_key, value}, {list, numbers, next} ->
        case numbers do
          %{^value => _} -> {list, numbers, next}
          _ -> {[value | list], Map.put(numbers, value, next), next + 1}
        end
      end)

    {Enum.reverse(reversed), numbers}
  end

  # The first key of every block stores its full bytes (a zero shared
  # prefix) so decoding can start at any block boundary with no prior
  # context, which is what makes the binary search possible.
  defp build_keys(entries) do
    {keys, blocks, _previous, _offset} =
      entries
      |> Enum.with_index()
      |> Enum.reduce({[], [], <<>>, 0}, fn {{key, _value}, index}, acc ->
        {keys, blocks, previous, offset} = acc
        block_start? = rem(index, @block_size) == 0
        prefix = if block_start?, do: 0, else: common_prefix_length(previous, key)
        suffix = binary_part(key, prefix, byte_size(key) - prefix)
        encoded = [varint(prefix), varint(byte_size(suffix)), suffix]
        blocks = if block_start?, do: [<<offset::unsigned-big-32>> | blocks], else: blocks

        {[encoded | keys], blocks, key, offset + IO.iodata_length(encoded)}
      end)

    {keys |> Enum.reverse() |> IO.iodata_to_binary(),
     blocks |> Enum.reverse() |> IO.iodata_to_binary()}
  end

  defp build_values(value_list, mask_width, index_width) do
    mask_bits = mask_width * 8
    index_bits = index_width * 8

    {values, offsets, _offset} =
      Enum.reduce(value_list, {[], [], 0}, fn {mask, indexes}, {values, offsets, offset} ->
        encoded = [
          <<mask::unsigned-big-size(mask_bits)>>,
          varint(length(indexes)),
          for(index <- indexes, do: <<index::unsigned-big-size(index_bits)>>)
        ]

        {[encoded | values], [<<offset::unsigned-big-32>> | offsets],
         offset + IO.iodata_length(encoded)}
      end)

    {values |> Enum.reverse() |> IO.iodata_to_binary(),
     offsets |> Enum.reverse() |> IO.iodata_to_binary()}
  end

  defp build_ord_to_value(entries, value_numbers, value_width) do
    bits = value_width * 8

    entries
    |> Enum.map(fn {_key, value} ->
      <<Map.fetch!(value_numbers, value)::unsigned-big-size(bits)>>
    end)
    |> IO.iodata_to_binary()
  end

  defp common_prefix_length(<<byte, left::binary>>, <<byte, right::binary>>) do
    1 + common_prefix_length(left, right)
  end

  defp common_prefix_length(_left, _right), do: 0

  # Bytes needed to hold `max` as an unsigned big-endian integer.
  defp byte_width(max) when max <= 0, do: 1
  defp byte_width(max), do: byte_width(max, 1)

  defp byte_width(max, width) when max < 1 <<< (width * 8), do: width
  defp byte_width(max, width), do: byte_width(max, width + 1)

  # LEB128-style: seven bits per byte, high bit set while more follow.
  defp varint(value) when value < 128, do: <<0::1, value::7>>

  defp varint(value) do
    <<1::1, band(value, 0x7F)::7, varint(bsr(value, 7))::binary>>
  end

  defp unvarint(<<0::1, value::7, rest::binary>>), do: {value, rest}

  defp unvarint(<<1::1, low::7, rest::binary>>) do
    {high, rest} = unvarint(rest)
    {bor(low, bsl(high, 7)), rest}
  end
end
