defmodule Localize.DateTest do
  use ExUnit.Case, async: true

  doctest Localize.Date

  describe "to_string/2 with standard formats" do
    test "medium format (default)" do
      assert {:ok, "Jul 10, 2017"} = Localize.Date.to_string(~D[2017-07-10], locale: :en)
    end

    test "full format" do
      assert {:ok, "Monday, July 10, 2017"} =
               Localize.Date.to_string(~D[2017-07-10], format: :full, locale: :en)
    end

    test "short format" do
      assert {:ok, "7/10/17"} =
               Localize.Date.to_string(~D[2017-07-10], format: :short, locale: :en)
    end

    test "long format" do
      assert {:ok, "July 10, 2017"} =
               Localize.Date.to_string(~D[2017-07-10], format: :long, locale: :en)
    end
  end

  describe "to_string/2 with locales" do
    test "German locale" do
      assert {:ok, "12.06.2019"} = Localize.Date.to_string(~D[2019-06-12], locale: :de)
    end

    test "French short format" do
      assert {:ok, "10/07/2017"} =
               Localize.Date.to_string(~D[2017-07-10], format: :short, locale: :fr)
    end

    test "French medium format" do
      assert {:ok, "10 juil. 2017"} =
               Localize.Date.to_string(~D[2017-07-10], locale: :fr)
    end
  end

  describe "to_string/2 with format patterns" do
    test "custom format string" do
      assert {:ok, "2017/7/10"} = Localize.Date.to_string(~D[2017-07-10], format: "y/M/d")
    end

    test "era format" do
      assert {:ok, result} = Localize.Date.to_string(~D[2024-07-06], format: "y/M/d G")
      assert String.contains?(result, "2024/7/6")
      assert String.contains?(result, "AD")
    end

    test "era variant format" do
      assert {:ok, result} =
               Localize.Date.to_string(~D[2024-07-06], format: "y/M/d G", era: :variant)

      assert String.contains?(result, "CE")
    end
  end

  describe "to_string!/2" do
    test "returns string directly" do
      assert "Jul 10, 2017" = Localize.Date.to_string!(~D[2017-07-10], locale: :en)
    end
  end
end
