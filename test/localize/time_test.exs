defmodule Localize.TimeTest do
  use ExUnit.Case, async: true

  doctest Localize.Time

  describe "to_string/2 with standard formats" do
    test "medium format (default)" do
      assert {:ok, "2:30:45 PM"} =
               Localize.Time.to_string(~T[14:30:45], locale: :en, prefer: :ascii)
    end

    test "short format" do
      assert {:ok, "2:30 PM"} =
               Localize.Time.to_string(~T[14:30:00], format: :short, locale: :en, prefer: :ascii)
    end

    test "AM time" do
      assert {:ok, "9:15:00 AM"} =
               Localize.Time.to_string(~T[09:15:00], locale: :en, prefer: :ascii)
    end
  end

  describe "to_string/2 with locales" do
    test "German locale uses 24-hour format" do
      assert {:ok, result} = Localize.Time.to_string(~T[14:30:00], locale: :de)
      assert String.contains?(result, "14:30:00")
    end
  end

  describe "to_string/2 with format patterns" do
    test "24-hour format pattern" do
      assert {:ok, "14:30:45"} = Localize.Time.to_string(~T[14:30:45], format: "HH:mm:ss")
    end

    test "12-hour format pattern" do
      assert {:ok, result} = Localize.Time.to_string(~T[14:30:45], format: "h:mm:ss a")
      assert String.contains?(result, "2:30:45")
    end
  end

  describe "to_string!/2" do
    test "returns string directly" do
      result = Localize.Time.to_string!(~T[01:23:00], locale: :en, prefer: :ascii)
      assert result == "1:23:00 AM"
    end
  end
end
