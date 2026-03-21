defmodule Localize.Utils.CodeTest do
  use ExUnit.Case, async: true

  doctest Localize.Utils.Code

  test "returns true for a loaded module" do
    assert Localize.Utils.Code.ensure_compiled?(Kernel) == true
  end

  test "returns false for a non-existent module" do
    assert Localize.Utils.Code.ensure_compiled?(NoSuchModule) == false
  end
end
