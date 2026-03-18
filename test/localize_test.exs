defmodule LocalizeTest do
  use ExUnit.Case
  doctest Localize

  test "greets the world" do
    assert Localize.hello() == :world
  end
end
