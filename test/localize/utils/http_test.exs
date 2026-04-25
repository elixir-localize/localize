defmodule Localize.Utils.HttpTest do
  @moduledoc """
  Covers HTTP utility helpers that can be tested without opening network
  connections.

  These tests do not exercise the Erlang httpc transport or external
  certificate stores.
  """

  use ExUnit.Case, async: true

  doctest Localize.Utils.Http

  describe "secure_ssl?/1" do
    test "keeps verification enabled when unsafe HTTPS is unset" do
      assert Localize.Utils.Http.secure_ssl?(nil)
    end

    test "treats an empty string as unset (verification stays on)" do
      assert Localize.Utils.Http.secure_ssl?("")
    end

    test "keeps verification enabled for explicit false-ish tokens" do
      for value <- ~w(FALSE false nil NIL) do
        assert Localize.Utils.Http.secure_ssl?(value),
               "expected secure_ssl?(#{inspect(value)}) to be true"
      end
    end

    test "disables verification when set to a truthy value" do
      refute Localize.Utils.Http.secure_ssl?("true")
      refute Localize.Utils.Http.secure_ssl?("1")
      refute Localize.Utils.Http.secure_ssl?("yes")
    end
  end
end
