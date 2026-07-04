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
  end

  describe "decode!/2 with keys: :atoms" do
    test "decodes a charlist with atom keys" do
      assert Json.decode!(~c({"a": 1}), keys: :atoms) == %{a: 1}
    end

    test "decodes nested objects with atom keys" do
      assert Json.decode!(~s({"outer": {"inner": null}}), keys: :atoms) ==
               %{outer: %{inner: nil}}
    end

    test "raises ArgumentError on trailing garbage after a valid document" do
      assert_raise ArgumentError, ~r/unexpected trailing data/, fn ->
        Json.decode!(~s({"a": 1} trailing), keys: :atoms)
      end
    end
  end
end
