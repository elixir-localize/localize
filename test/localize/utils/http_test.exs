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

  describe "max_http_body_bytes/0" do
    test "returns the default cap (50 MB) when unconfigured" do
      original = Application.get_env(:localize, :max_http_body_bytes)
      Application.delete_env(:localize, :max_http_body_bytes)

      try do
        assert Localize.Utils.Http.max_http_body_bytes() == 50 * 1024 * 1024
      after
        if original do
          Application.put_env(:localize, :max_http_body_bytes, original)
        else
          Application.delete_env(:localize, :max_http_body_bytes)
        end
      end
    end

    test "honours an app-env override" do
      original = Application.get_env(:localize, :max_http_body_bytes)
      Application.put_env(:localize, :max_http_body_bytes, 1_024)

      try do
        assert Localize.Utils.Http.max_http_body_bytes() == 1_024
      after
        if original do
          Application.put_env(:localize, :max_http_body_bytes, original)
        else
          Application.delete_env(:localize, :max_http_body_bytes)
        end
      end
    end
  end
end
