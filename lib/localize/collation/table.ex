defmodule Localize.Collation.Table do
  # Persistent-term-backed collation element table.
  #
  # Loads the pre-generated collation table from `priv/localize/collation_table.etf`
  # for fast concurrent lookups using `:persistent_term`, which provides
  # zero-copy reads for data that is written once and never modified.
  #
  # The ETF file is generated from `FractionalUCA.txt` during the build
  # pipeline by `Localize.Data.Collation.generate_collation_table/0`.
  #
  # Handles both single codepoint mappings and contractions
  # (multi-codepoint sequences).
  #
  @moduledoc false

  use GenServer

  alias Localize.Collation.Element
  alias Localize.Collation.Table.Parser

  @table_name {:localize, :collation_table}
  @contractions_table {:localize, :collation_contractions}
  @fast_latin_key {:localize, :collation_fast_latin}

  @collation_etf "collation_table.etf"

  @doc """
  Ensure the collation table is loaded.

  Loads the pre-generated collation table ETF on first call. Subsequent
  calls are no-ops.

  ### Returns

  * `:ok` - the table is loaded and ready for lookups.

  ### Examples

      iex> Localize.Collation.Table.ensure_loaded()
      :ok

  """
  @spec ensure_loaded() :: :ok
  def ensure_loaded do
    table_loaded? = :persistent_term.get(@table_name, nil) != nil
    contractions_loaded? = :persistent_term.get(@contractions_table, nil) != nil
    fast_latin_loaded? = :persistent_term.get(@fast_latin_key, nil) != nil

    if table_loaded? and contractions_loaded? and fast_latin_loaded? do
      :ok
    else
      GenServer.call(__MODULE__, :load, :infinity)
    end
  end

  @doc """
  Look up collation elements for a codepoint or codepoint sequence.

  ### Arguments

  * `codepoint` - a single integer codepoint, or a list of integer
    codepoints (contraction).

  ### Returns

  * `{:ok, [element]}` - the collation elements for the entry.

  * `:unmapped` - no entry found in the table.

  ### Examples

      iex> Localize.Collation.Table.ensure_loaded()
      iex> {:ok, elements} = Localize.Collation.Table.lookup(0x0041)
      iex> Localize.Collation.Element.primary(hd(elements)) > 0
      true

      iex> Localize.Collation.Table.ensure_loaded()
      iex> Localize.Collation.Table.lookup(0x10FFFF)
      :unmapped

  """
  @spec lookup(non_neg_integer() | [non_neg_integer()]) :: {:ok, [Element.t()]} | :unmapped
  def lookup(codepoint) when is_integer(codepoint) do
    table = :persistent_term.get(@table_name)

    case Map.get(table, codepoint) do
      nil -> :unmapped
      elements -> {:ok, elements}
    end
  end

  def lookup(codepoints) when is_list(codepoints) do
    table = :persistent_term.get(@table_name)
    key = Parser.codepoints_to_key(codepoints)

    case Map.get(table, key) do
      nil -> :unmapped
      elements -> {:ok, elements}
    end
  end

  @doc """
  Check if a codepoint begins any multi-codepoint contraction.

  ### Arguments

  * `codepoint` - an integer codepoint to check.

  ### Returns

  A list of contraction lengths that start with this codepoint, or `[]` if
  this codepoint does not begin any contractions.

  """
  @spec contraction_starters(non_neg_integer()) :: [pos_integer()]
  def contraction_starters(codepoint) do
    contractions = :persistent_term.get(@contractions_table)
    Map.get(contractions, codepoint, [])
  end

  @doc """
  Find the longest matching entry for the given codepoint sequence.

  Tries contractions from longest to shortest, falling back to a single
  codepoint lookup.

  ### Arguments

  * `codepoints` - a list of integer codepoints to match against.

  ### Returns

  * `{matched_cps, elements, remaining_cps}` - a successful match.

  * `{:unmapped, codepoint, remaining_cps}` - the first codepoint has no table entry.

  * `:done` - the input list is empty.

  """
  @spec longest_match([non_neg_integer()]) ::
          {[non_neg_integer()], [Element.t()], [non_neg_integer()]}
          | {:unmapped, non_neg_integer(), [non_neg_integer()]}
          | :done
  def longest_match([cp | rest] = _codepoints) do
    lengths = contraction_starters(cp)

    if lengths == [] do
      match_single_codepoint(cp, rest)
    else
      max_len = Enum.max(lengths)
      available = [cp | Enum.take(rest, max_len - 1)]

      result =
        max_len..2//-1
        |> Enum.reduce_while(nil, fn len, _acc ->
          match_contraction(len, available, cp, rest)
        end)

      case result do
        nil -> match_single_codepoint(cp, rest)
        match -> match
      end
    end
  end

  def longest_match([]), do: :done

  defp match_single_codepoint(cp, rest) do
    case lookup(cp) do
      {:ok, elements} -> {[cp], elements, rest}
      :unmapped -> {:unmapped, cp, rest}
    end
  end

  defp match_contraction(len, available, cp, rest) do
    if len <= length(available) do
      candidate = Enum.take(available, len)

      case lookup(candidate) do
        {:ok, elements} ->
          remaining = Enum.drop([cp | rest], len)
          {:halt, {candidate, elements, remaining}}

        :unmapped ->
          {:cont, nil}
      end
    else
      {:cont, nil}
    end
  end

  @doc """
  Look up collation elements with a tailoring overlay checked first.

  ### Arguments

  * `codepoints` - a single integer codepoint, or a list of integer codepoints.

  * `overlay` - a map of tailoring entries, or `nil` for root-only lookups.

  ### Returns

  Same as `lookup/1`, but checks the overlay map before falling back
  to the root table.

  """
  @spec lookup_with_overlay(non_neg_integer() | [non_neg_integer()], map() | nil) ::
          {:ok, [Element.t()]} | :unmapped
  def lookup_with_overlay(codepoint, overlay) when is_integer(codepoint) do
    lookup_with_overlay_key(codepoint, overlay)
  end

  def lookup_with_overlay(codepoints, overlay) when is_list(codepoints) do
    key = Parser.codepoints_to_key(codepoints)
    lookup_with_overlay_key(key, overlay)
  end

  defp lookup_with_overlay_key(key, nil) do
    table = :persistent_term.get(@table_name)

    case Map.get(table, key) do
      nil -> :unmapped
      elements -> {:ok, elements}
    end
  end

  defp lookup_with_overlay_key(key, overlay) when is_map(overlay) do
    case Map.get(overlay, key) do
      nil ->
        table = :persistent_term.get(@table_name)

        case Map.get(table, key) do
          nil -> :unmapped
          elements -> {:ok, elements}
        end

      elements ->
        {:ok, elements}
    end
  end

  @doc """
  Find the longest matching entry, checking a tailoring overlay first.

  ### Arguments

  * `codepoints` - a list of integer codepoints to match.

  * `overlay` - a tailoring overlay map, or `nil` for root-only lookups.

  ### Returns

  Same as `longest_match/1`.

  """
  @spec longest_match_with_overlay([non_neg_integer()], map() | nil) ::
          {[non_neg_integer()], [Element.t()], [non_neg_integer()]}
          | {:unmapped, non_neg_integer(), [non_neg_integer()]}
          | :done
  def longest_match_with_overlay(codepoints, nil), do: longest_match(codepoints)

  def longest_match_with_overlay([cp | rest] = _codepoints, overlay) when is_map(overlay) do
    overlay_max_len = overlay_max_contraction_length(cp, overlay)

    overlay_result =
      if overlay_max_len > 0 do
        available = [cp | Enum.take(rest, overlay_max_len - 1)]

        overlay_max_len..1//-1
        |> Enum.reduce_while(nil, fn len, _acc ->
          match_overlay_contraction(len, available, cp, rest, overlay)
        end)
      else
        nil
      end

    case overlay_result do
      nil ->
        longest_match([cp | rest])

      match ->
        match
    end
  end

  def longest_match_with_overlay([], _overlay), do: :done

  defp match_overlay_contraction(len, available, cp, rest, overlay) do
    if len <= length(available) do
      candidate = Enum.take(available, len)
      key = Parser.codepoints_to_key(candidate)

      case Map.get(overlay, key) do
        nil ->
          {:cont, nil}

        elements ->
          remaining = Enum.drop([cp | rest], len)
          {:halt, {candidate, elements, remaining}}
      end
    else
      {:cont, nil}
    end
  end

  defp overlay_max_contraction_length(cp, overlay) do
    overlay
    |> Map.keys()
    |> Enum.reduce(0, fn
      ^cp, acc -> max(acc, 1)
      key, acc when is_tuple(key) and elem(key, 0) == cp -> max(acc, tuple_size(key))
      _, acc -> acc
    end)
  end

  # GenServer

  def start_link(options \\ []) do
    GenServer.start_link(__MODULE__, options, name: __MODULE__)
  end

  @impl true
  def init(_options) do
    {:ok, %{loaded: false}, {:continue, :load}}
  end

  @impl true
  def handle_continue(:load, state) do
    load_table()
    {:noreply, %{state | loaded: true}}
  end

  @impl true
  def handle_call(:load, _from, state) do
    # Always verify the persistent_term keys are actually present
    # before short-circuiting. The `state.loaded` flag is not
    # authoritative: callers (or hot reloads) may have erased
    # individual keys since the last load.
    if fully_loaded?() do
      {:reply, :ok, %{state | loaded: true}}
    else
      load_table()
      {:reply, :ok, %{state | loaded: true}}
    end
  end

  defp fully_loaded? do
    :persistent_term.get(@table_name, nil) != nil and
      :persistent_term.get(@contractions_table, nil) != nil and
      :persistent_term.get(@fast_latin_key, nil) != nil
  end

  defp load_table do
    etf_path = Application.app_dir(:localize, ["priv", "localize", @collation_etf])

    case File.read(etf_path) do
      {:ok, binary} ->
        data = :erlang.binary_to_term(binary)

        :persistent_term.put(@table_name, data.entries)
        :persistent_term.put(@contractions_table, data.contractions)
        :persistent_term.put(@fast_latin_key, data.fast_latin)

        # Store reorder data for Localize.Collation.Reorder
        :persistent_term.put({:localize, :collation_primary_to_frac}, data.primary_to_frac)
        :persistent_term.put({:localize, :collation_script_ranges}, data.script_ranges)

        # Store Han radical data for Localize.Collation.Han
        :persistent_term.put({:localize, :collation_han_radicals}, data.han_radicals)

      {:error, :enoent} ->
        require Logger

        Logger.warning(
          "Collation table ETF not found at #{etf_path}. " <>
            "Run Localize.Data.Collation.generate_collation_table/0 to generate it.",
          domain: [:localize]
        )
    end
  end
end
