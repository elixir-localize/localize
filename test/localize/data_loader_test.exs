defmodule Localize.DataLoaderTest do
  use ExUnit.Case, async: true

  alias Localize.DataLoader

  # The DataLoader GenServer is started by the Localize supervision
  # tree, so these tests exercise the running server with private
  # probe keys and erase them afterwards.

  describe "load/2" do
    test "loads through the GenServer and caches in persistent_term" do
      key = {__MODULE__, :probe, :erlang.unique_integer()}
      on_exit(fn -> :persistent_term.erase(key) end)

      assert Process.whereis(DataLoader) != nil
      assert DataLoader.load(key, fn -> :loaded_value end) == :loaded_value
      assert :persistent_term.get(key) == :loaded_value
    end

    test "a cached key returns immediately without invoking the loader" do
      key = {__MODULE__, :cached, :erlang.unique_integer()}
      on_exit(fn -> :persistent_term.erase(key) end)

      assert DataLoader.load(key, fn -> :first end) == :first

      assert DataLoader.load(key, fn -> raise "loader must not be called" end) == :first
    end

    test "concurrent loads for the same key invoke the loader once" do
      key = {__MODULE__, :concurrent, :erlang.unique_integer()}
      counter = :counters.new(1, [])
      on_exit(fn -> :persistent_term.erase(key) end)

      load_function = fn ->
        :counters.add(counter, 1, 1)
        :loaded
      end

      results =
        1..8
        |> Enum.map(fn _index -> Task.async(fn -> DataLoader.load(key, load_function) end) end)
        |> Task.await_many()

      assert Enum.all?(results, &(&1 == :loaded))
      assert :counters.get(counter, 1) == 1
    end
  end

  describe "handle_call/3" do
    test "returns the cached value when the key was loaded between checks" do
      key = {__MODULE__, :race, :erlang.unique_integer()}
      on_exit(fn -> :persistent_term.erase(key) end)

      :persistent_term.put(key, :preexisting)

      assert GenServer.call(DataLoader, {:load, key, fn -> :ignored end}) == :preexisting
    end
  end

  describe "start_link/1" do
    test "returns already_started when the supervised server is running" do
      assert {:error, {:already_started, pid}} = DataLoader.start_link()
      assert Process.whereis(DataLoader) == pid
    end
  end
end
