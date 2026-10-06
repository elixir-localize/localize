defmodule Localize.LiteralMemory do
  @moduledoc false

  # The VM keeps every term of `:persistent_term` in its literal area, a
  # region whose size is fixed when the VM starts: a gigabyte by default on
  # a 64-bit VM, set with `+MIscs` and a size in megabytes. A term the area
  # has no room for stops the VM ("literal_alloc: Cannot allocate ... bytes
  # of memory"), which no process can catch. A loaded locale is about 1.2
  # MB, so all of CLDR's take most of the default area, and a VM that then
  # read dates in them stopped.
  #
  # So nothing whose size grows with the locales and calendars in use is put
  # there unless the VM reports room for it. The VM reports the area's size
  # and how much of it its carriers hold
  # (`:erlang.system_info({:allocator, :erts_mmap})`), and a term's size on
  # the heap is the size of the block it is copied into. Measured on OTP 29
  # by filling a 32 MB area: a term is kept while that many bytes are free,
  # and the VM stops at the first one larger than what is free. The check is
  # conservative, since a term may still fit in a block freed inside a
  # carrier the area already holds, and it is not atomic: two processes that
  # ask at once may both be told there is room.
  #
  # The report's shape is the VM's own, "highly implementation-dependent",
  # and a 32-bit VM has no literal area of its own. Where it is not the
  # shape read here nothing is known, and a term is kept as it always was.

  # Room for the header of the block a term is copied into and for the area
  # to grow by whole pages, of at most 64 KB.
  @margin 65_536

  @doc false
  # Keeps `term` under `key` in `:persistent_term`, or returns an error
  # naming `what` where the VM reports no room for it: for data a caller
  # cannot do without, a locale.
  @spec put(term(), term(), String.t()) :: :ok | {:error, Exception.t()}
  def put(key, term, what) do
    case room_for(term) do
      :ok ->
        :persistent_term.put(key, term)

      {:lacking, needed, free} ->
        {:error, Localize.LiteralMemoryError.exception(what: what, needed: needed, free: free)}
    end
  end

  @doc false
  # Keeps `term` under `key` in `:persistent_term` where the VM reports room
  # for it, and otherwise not at all: for what is worked out again when it
  # is not found, a parser's compiled patterns.
  @spec cache(term(), term()) :: :ok
  def cache(key, term) do
    case room_for(term) do
      :ok -> :persistent_term.put(key, term)
      {:lacking, _needed, _free} -> :ok
    end
  end

  @doc false
  # Whether the literal area has room for `term`: `:ok` where it has, or
  # where the VM does not say, and else the bytes the term needs and the
  # bytes free.
  @spec room_for(term()) :: :ok | {:lacking, non_neg_integer(), non_neg_integer()}
  def room_for(term) do
    with {:ok, free} <- free(),
         {:ok, needed} <- size(term),
         true <- needed + @margin > free do
      {:lacking, needed, free}
    else
      _room_or_unknown -> :ok
    end
  end

  @doc false
  # The bytes of the literal area no carrier holds yet, as the VM reports
  # them, or `:unknown`.
  @spec free() :: {:ok, non_neg_integer()} | :unknown
  def free do
    sizes =
      {:allocator, :erts_mmap}
      |> :erlang.system_info()
      |> reported([:literal_mmap, :supercarrier, :sizes])

    with total when is_integer(total) <- reported(sizes, [:total]),
         used when is_integer(used) <- reported(sizes, [:used]) do
      {:ok, max(total - used, 0)}
    else
      _unreported -> :unknown
    end
  end

  # A value of the VM's report, a list of pairs within lists of pairs, or
  # `nil` where it has another shape.
  defp reported(value, []), do: value

  defp reported(pairs, [key | rest]) when is_list(pairs) do
    case Enum.find(pairs, &match?({^key, _value}, &1)) do
      {^key, value} -> reported(value, rest)
      nil -> nil
    end
  end

  defp reported(_other, _keys), do: nil

  # A term's size on the heap, in bytes, which is what `:persistent_term`
  # copies into the literal area.
  defp size(term) do
    if Code.ensure_loaded?(:erts_debug) and function_exported?(:erts_debug, :flat_size, 1),
      do: {:ok, :erts_debug.flat_size(term) * :erlang.system_info(:wordsize)},
      else: :unknown
  end
end
