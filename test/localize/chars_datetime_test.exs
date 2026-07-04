defmodule Localize.CharsDateTimeTest do
  use ExUnit.Case, async: true

  # Covers the `Localize.Chars` protocol implementation for
  # `DateTime` (and its `NaiveDateTime` sibling which shares the
  # same delegation target).

  @datetime DateTime.new!(~D[2026-07-04], ~T[11:30:15], "Etc/UTC")

  describe "Localize.Chars.to_string/1 for DateTime" do
    test "formats with the default locale and format" do
      assert Localize.Chars.to_string(@datetime) ==
               {:ok, "Jul 4, 2026, 11:30:15 AM"}
    end
  end

  describe "Localize.Chars.to_string/2 for DateTime" do
    test "honours the :locale option" do
      assert Localize.Chars.to_string(@datetime, locale: :fr) ==
               {:ok, "4 juil. 2026, 11:30:15"}
    end

    test "honours the :format option" do
      assert Localize.Chars.to_string(@datetime, format: :long) ==
               {:ok, "July 4, 2026, 11:30:15 AM GMT"}
    end

    test "combines :locale and :format options" do
      assert Localize.Chars.to_string(@datetime, locale: :de, format: :short) ==
               {:ok, "04.07.26, 11:30"}
    end

    test "returns an error tuple for an unresolvable format" do
      assert {:error, %Localize.DateTimeUnresolvedFormatError{format: :bogus}} =
               Localize.Chars.to_string(@datetime, format: :bogus)
    end
  end

  describe "Localize.Chars.to_string/1 for NaiveDateTime" do
    test "formats the same as the equivalent DateTime" do
      assert Localize.Chars.to_string(~N[2026-07-04 11:30:15]) ==
               {:ok, "Jul 4, 2026, 11:30:15 AM"}
    end
  end
end
