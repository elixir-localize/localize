defmodule Localize.Utils.JsonTest do
  use ExUnit.Case, async: true

  alias Localize.Utils.Json

  doctest Localize.Utils.Json

  describe "decode!/1" do
    test "decodes a charlist" do
      assert Json.decode!(~c({"a": [1, 2.5, true, null]})) ==
               %{"a" => [1, 2.5, true, nil]}
    end

    test "decodes nested structures" do
      assert Json.decode!(~s({"a": {"b": [1, "two"]}})) == %{"a" => %{"b" => [1, "two"]}}
    end

    test "raises on invalid JSON" do
      assert_raise ErlangError, fn ->
        Json.decode!("not json")
      end
    end

    test "raises ArgumentError on trailing garbage after a valid document" do
      # Regression: trailing data raised a bare MatchError from the
      # unpinned `{json, :ok, ""}` match instead of a meaningful error.
      assert_raise ArgumentError, ~r/unexpected trailing data/, fn ->
        Json.decode!(~s({"a": 1} trailing))
      end
    end

    # Keys stay strings whatever the input: there is no way to ask for
    # atoms, so a key from untrusted JSON never becomes one.
    test "has no atom-key form" do
      refute function_exported?(Json, :decode!, 2)
      probe = "json_key_probe_#{System.unique_integer([:positive])}"

      assert Json.decode!(~s({"#{probe}": 1})) == %{probe => 1}
      assert_raise ArgumentError, fn -> String.to_existing_atom(probe) end
    end
  end
end
