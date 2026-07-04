defmodule Localize.Utils.HelpersTest do
  use ExUnit.Case, async: true

  alias Localize.Utils.Helpers

  doctest Localize.Utils.Helpers

  describe "existing_atom/1" do
    test "returns the atom when it already exists" do
      assert Helpers.existing_atom("ok") == :ok
    end

    test "returns nil when the atom does not exist" do
      assert Helpers.existing_atom("localize_helpers_test_never_interned") == nil
    end

    test "returns nil for non-binary input" do
      assert Helpers.existing_atom(123) == nil
      assert Helpers.existing_atom(nil) == nil
    end
  end

  describe "get_term/2 and put_term/2" do
    test "round-trips a value through persistent_term" do
      key = {__MODULE__, :probe}

      on_exit(fn -> :persistent_term.erase(key) end)

      assert Helpers.get_term(key, :default) == :default
      assert Helpers.put_term(key, :stored) == :ok
      assert Helpers.get_term(key, :default) == :stored
    end
  end
end
