defmodule Localize.ApplicationTest do
  use ExUnit.Case, async: true

  describe "start/2" do
    test "returns an already-started error when the supervisor is running" do
      # The :localize application is started by the test suite, so a
      # second start reports the running supervisor rather than
      # spawning a duplicate tree.
      assert {:error, {:already_started, pid}} = Localize.Application.start(:normal, [])
      assert pid == Process.whereis(Localize.Supervisor)
    end
  end
end
