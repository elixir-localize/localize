defmodule Localize.MacrosTest do
  use ExUnit.Case, async: true

  import Localize.Macros

  test "is_false/1 returns true for nil" do
    assert is_false(nil)
  end

  test "is_false/1 returns true for false" do
    assert is_false(false)
  end

  test "is_false/1 returns false for truthy values" do
    refute is_false(true)
    refute is_false(1)
    refute is_false("hello")
  end
end
