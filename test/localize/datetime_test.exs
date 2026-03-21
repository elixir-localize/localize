defmodule Localize.DateTimeTest do
  use ExUnit.Case, async: true

  doctest Localize.DateTime

  describe "to_string/2 with standard formats" do
    test "medium format (default)" do
      assert {:ok, result} = Localize.DateTime.to_string(~N[2017-07-10 14:30:00], locale: :en)
      assert String.contains?(result, "Jul 10, 2017")
      assert String.contains?(result, "2:30:00")
      assert String.contains?(result, "PM")
    end

    test "short format" do
      assert {:ok, result} =
               Localize.DateTime.to_string(~N[2017-07-10 14:30:00], format: :short, locale: :en)

      assert String.contains?(result, "7/10/17")
      assert String.contains?(result, "2:30")
    end

    test "full format" do
      assert {:ok, result} =
               Localize.DateTime.to_string(~N[2017-07-10 14:30:00], format: :full, locale: :en)

      assert String.contains?(result, "Monday, July 10, 2017")
    end
  end

  describe "to_string/2 with separate date and time formats" do
    test "different date and time formats" do
      assert {:ok, result} =
               Localize.DateTime.to_string(~N[2024-07-07 21:36:00],
                 date_format: :short,
                 time_format: :medium,
                 locale: :en
               )

      assert String.contains?(result, "7/7/24")
      assert String.contains?(result, "9:36:00")
    end
  end

  describe "to_string/2 with locales" do
    test "French locale" do
      assert {:ok, result} = Localize.DateTime.to_string(~N[2017-07-10 14:30:00], locale: :fr)
      assert String.contains?(result, "juil.")
      assert String.contains?(result, "14:30:00")
    end
  end

  describe "to_string!/2" do
    test "returns string directly" do
      result = Localize.DateTime.to_string!(~N[2024-01-15 09:00:00], locale: :en)
      assert String.contains?(result, "Jan 15, 2024")
    end
  end
end
