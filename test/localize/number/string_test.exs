defmodule Localize.Number.StringTest do
  use ExUnit.Case, async: true

  alias Localize.Number.String, as: NString

  describe "pad_leading_zeros/2" do
    test "pads when shorter than count" do
      assert "00123" == NString.pad_leading_zeros("123", 5)
    end

    test "no padding when already at count" do
      assert "123" == NString.pad_leading_zeros("123", 3)
    end

    test "no padding when count is 0" do
      assert "123" == NString.pad_leading_zeros("123", 0)
    end
  end

  describe "pad_trailing_zeros/2" do
    test "pads when shorter than count" do
      assert "12300" == NString.pad_trailing_zeros("123", 5)
    end

    test "no padding when already at count" do
      assert "123" == NString.pad_trailing_zeros("123", 3)
    end
  end

  describe "chunk_string/3" do
    test "forward chunking" do
      assert ["Thi", "s i", "s a", " st", "rin", "g"] ==
               NString.chunk_string("This is a string", 3)
    end

    test "forward chunking with exact multiple" do
      assert ["1234"] == NString.chunk_string("1234", 4)
    end

    test "forward chunking with remainder" do
      assert ["123", "4"] == NString.chunk_string("1234", 3)
    end

    test "reverse chunking" do
      assert ["1", "234"] == NString.chunk_string("1234", 3, :reverse)
    end

    test "reverse chunking with exact multiple" do
      assert ["123", "456"] == NString.chunk_string("123456", 3, :reverse)
    end

    test "empty string" do
      assert [""] == NString.chunk_string("", 3)
    end

    test "zero chunk size" do
      assert ["1234"] == NString.chunk_string("1234", 0)
    end
  end

  describe "latin1/0 and not_latin1/0" do
    test "latin1 regex matches ASCII" do
      assert Regex.match?(NString.latin1(), "a")
    end

    test "not_latin1 regex matches non-ASCII" do
      assert Regex.match?(NString.not_latin1(), "é")
    end
  end
end
