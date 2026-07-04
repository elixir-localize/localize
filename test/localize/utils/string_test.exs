defmodule Localize.Utils.StringTest do
  use ExUnit.Case, async: true

  alias Localize.Utils.String, as: StringUtils

  doctest Localize.Utils.String

  describe "hash/1" do
    test "hashes the empty string to zero" do
      assert StringUtils.hash("") == 0
    end

    test "is deterministic for the same input" do
      assert StringUtils.hash("hello") == 61_454_117
      assert StringUtils.hash("hello") == StringUtils.hash("hello")
    end

    test "different strings produce different hashes" do
      refute StringUtils.hash("hello") == StringUtils.hash("world")
    end
  end

  describe "to_underscore/1" do
    test "replaces every hyphen with an underscore" do
      assert StringUtils.to_underscore("a-b-c") == "a_b_c"
    end

    test "returns a hyphen-free string unchanged" do
      assert StringUtils.to_underscore("already_done") == "already_done"
    end
  end

  describe "underscore/1" do
    test "converts a module atom without the Elixir prefix" do
      assert StringUtils.underscore(Localize.Utils.Map) == "localize/utils/map"
    end

    test "converts a dotted string using a path separator" do
      assert StringUtils.underscore("Foo.Bar") == "foo/bar"
    end

    test "handles consecutive capitals" do
      assert StringUtils.underscore("ABCdef") == "ab_cdef"
    end

    test "returns the empty string unchanged" do
      assert StringUtils.underscore("") == ""
    end
  end

  describe "to_upper_char/1 and to_lower_char/1" do
    test "to_upper_char upcases ASCII lowercase letters only" do
      assert StringUtils.to_upper_char(?a) == ?A
      assert StringUtils.to_upper_char(?z) == ?Z
      assert StringUtils.to_upper_char(?A) == ?A
      assert StringUtils.to_upper_char(?1) == ?1
    end

    test "to_lower_char downcases ASCII uppercase letters only" do
      assert StringUtils.to_lower_char(?A) == ?a
      assert StringUtils.to_lower_char(?Z) == ?z
      assert StringUtils.to_lower_char(?a) == ?a
      assert StringUtils.to_lower_char(?1) == ?1
    end
  end
end
