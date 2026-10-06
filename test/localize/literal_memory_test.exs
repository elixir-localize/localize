defmodule Localize.LiteralMemoryTest do
  @moduledoc """
  The VM keeps the terms of `:persistent_term` in its literal area, whose
  size is fixed when it starts, and stops when a term does not fit. Localize
  keeps each locale there, so it asks the VM for the room before it keeps
  anything whose size grows with the locales in use: a locale with no room
  is an error naming the VM's flag, and a parser's patterns are not kept.

  The room is the VM's own report, and what happens when it runs out is
  seen in a VM of its own, started with a literal area of 16 MB.
  """

  use ExUnit.Case, async: true

  alias Localize.LiteralMemory
  alias Localize.Locale.Provider.PersistentTerm

  @megabyte 1_048_576

  describe "in a VM with room" do
    # A 64-bit VM reserves its literal area when it starts, a gigabyte by
    # default, and reports how much of it its carriers hold.
    test "the VM reports the bytes free in its literal area" do
      assert :erlang.system_info(:wordsize) == 8
      assert {:ok, free} = LiteralMemory.free()
      assert free > 0
    end

    test "a term is kept, as data that is needed and as a cache" do
      term = Enum.to_list(1..1000)

      assert LiteralMemory.room_for(term) == :ok
      assert LiteralMemory.put({__MODULE__, :needed}, term, "a list") == :ok
      assert :persistent_term.get({__MODULE__, :needed}) == term

      assert LiteralMemory.cache({__MODULE__, :cache}, term) == :ok
      assert :persistent_term.get({__MODULE__, :cache}) == term
    after
      :persistent_term.erase({__MODULE__, :needed})
      :persistent_term.erase({__MODULE__, :cache})
    end

    test "the error says what did not fit, the bytes, and the VM's flag" do
      error =
        Localize.LiteralMemoryError.exception(what: "the locale :de", needed: 1200, free: 800)

      message = Exception.message(error)

      assert message =~ "the locale :de"
      assert message =~ "1200"
      assert message =~ "800"
      assert message =~ "+MIscs"
    end
  end

  describe "in a VM whose literal area is nearly full" do
    setup do
      paths = Enum.flat_map(:code.get_path(), &[~c"-pa", &1])
      arguments = [~c"+MIscs", ~c"16" | paths]
      {:ok, peer, _node} = :peer.start(%{connection: :standard_io, args: arguments})
      on_exit(fn -> if Process.alive?(peer), do: :peer.stop(peer) end)

      %{peer: peer}
    end

    # Two megabytes a term, as a large locale is: the area takes a
    # few, and the next is refused with the VM still running. Kept without
    # asking, it stopped the VM: "literal_alloc: Cannot allocate 2097216
    # bytes of memory (of type "literal")".
    test "a term with no room is an error, and the VM goes on", %{peer: peer} do
      term = two_megabytes()
      {kept, error} = fill(peer, term)

      assert kept in 2..7
      assert %Localize.LiteralMemoryError{what: "a test term", needed: needed, free: free} = error
      assert needed in (2 * @megabyte)..(3 * @megabyte)
      assert free < needed + 65_536

      assert :peer.call(peer, :erlang, :system_info, [:wordsize]) == 8
      assert :peer.call(peer, LiteralMemory, :free, []) == {:ok, free}
      assert :peer.call(peer, :persistent_term, :get, [{:fill, kept}, nil]) == term
      assert :peer.call(peer, :persistent_term, :get, [{:fill, kept + 1}, nil]) == nil
    end

    test "a locale with no room is an error naming it, and a cache is not kept", %{peer: peer} do
      term = two_megabytes()
      {_kept, _error} = fill(peer, term)
      locale = %{languages: %{"de" => "German"}, filler: term}

      assert {:error, %Localize.LiteralMemoryError{what: "the locale :de"} = error} =
               :peer.call(peer, PersistentTerm, :store, [:de, locale])

      assert Exception.message(error) =~ "+MIscs"
      assert :peer.call(peer, PersistentTerm, :loaded?, [:de]) == false

      assert :peer.call(peer, LiteralMemory, :cache, [{:cache, :de}, term]) == :ok
      assert :peer.call(peer, :persistent_term, :get, [{:cache, :de}, nil]) == nil

      # What still fits is still kept.
      small = Enum.to_list(1..100)
      assert :peer.call(peer, LiteralMemory, :cache, [{:cache, :small}, small]) == :ok
      assert :peer.call(peer, :persistent_term, :get, [{:cache, :small}, nil]) == small
    end
  end

  # A list of integers: two words a cell, so 131,072 cells are two megabytes
  # on the heap of a 64-bit VM.
  defp two_megabytes, do: Enum.to_list(1..div(2 * @megabyte, 16))

  defp fill(peer, term) do
    Enum.reduce_while(1..64, {0, nil}, fn index, {kept, _error} ->
      case :peer.call(peer, LiteralMemory, :put, [{:fill, index}, term, "a test term"]) do
        :ok -> {:cont, {index, nil}}
        {:error, error} -> {:halt, {kept, error}}
      end
    end)
  end
end
