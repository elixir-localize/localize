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
    test "keeps verification enabled when unsafe HTTPS is unset or explicitly false" do
      assert Localize.Utils.Http.secure_ssl?(nil)
      assert Localize.Utils.Http.secure_ssl?("false")
      assert Localize.Utils.Http.secure_ssl?("NIL")
    end

    test "disables verification when unsafe HTTPS is set to a truthy value" do
      refute Localize.Utils.Http.secure_ssl?("true")
    end
  end
end
