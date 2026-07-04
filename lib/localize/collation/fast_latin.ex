defmodule Localize.Collation.FastLatin do
  # Fast lookup table for Basic Latin and Latin Extended-A codepoints.
  #
  # Provides O(1) collation element lookup for codepoints U+0000..U+017F
  # by pre-computing a tuple indexed by codepoint value. This bypasses
  # the full contraction-checking path in `Localize.Collation.Table` for the
  # most commonly encountered characters.
  #
  # Codepoints that are contraction starters (e.g., `L` and `l` for Catalan
  # l·l) or combining marks (CCC > 0) are excluded from the fast table and
  # fall back to the normal lookup path.
  #
  @moduledoc false

  @table_name {:localize, :collation_fast_latin}
  @latin_limit 0x0180

  @doc """
  Build the fast Latin lookup table from the loaded collation table.

  Reads the collation table and contraction starters from `:persistent_term`,
  and constructs a tuple of `@latin_limit` entries. Each entry is either a
  list of collation element tuples (for direct lookup) or `nil` (indicating
  the codepoint must use the full lookup path).

  Called automatically during table loading.

  ### Returns

  * `:ok`.

  """
  @spec build() :: :ok
  def build do
    table = :persistent_term.get({:localize, :collation_table})
    contractions = :persistent_term.get({:localize, :collation_contractions})

    entries =
      for cp <- 0..(@latin_limit - 1) do
        cond do
          Map.has_key?(contractions, cp) ->
            nil

          combining_mark?(cp) ->
            nil

          true ->
            Map.get(table, cp)
        end
      end

    tuple = List.to_tuple(entries)
    :persistent_term.put(@table_name, tuple)
    :ok
  end

  @doc """
  Look up collation elements for a Latin codepoint.

  ### Arguments

  * `cp` - an integer codepoint less than `0x0180`.

  ### Returns

  * A list of collation element tuples - the codepoint has a direct mapping.

  * `nil` - the codepoint is a contraction starter, combining mark, or unmapped;
    use the full lookup path.

  """
  @spec lookup(non_neg_integer()) :: [Localize.Collation.Element.t()] | nil
  def lookup(cp) when cp < @latin_limit do
    elem(table(), cp)
  end

  defp table do
    case :persistent_term.get(@table_name, :not_loaded) do
      :not_loaded ->
        # The fast-latin table is normally built when
        # `Localize.Collation.Table` loads. If it is missing — for
        # example because the collation table was loaded directly
        # into `:persistent_term` without running `build/0`, or
        # because the fast-latin term was erased — rebuild it by
        # routing through `Table.ensure_loaded/0`, which runs the
        # full load path and invokes `build/0`.
        Localize.Collation.Table.ensure_loaded()
        :persistent_term.get(@table_name)

      tuple ->
        tuple
    end
  end

  defp combining_mark?(cp) do
    Localize.Collation.Unicode.combining_class(cp) > 0
  end
end
