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

  describe "to_string/2 with partial times" do
    test "hour and minute with skeleton" do
      assert {:ok, "2:30 PM"} =
               Localize.Time.to_string(%{hour: 14, minute: 30},
                 format: :hm,
                 locale: :en,
                 prefer: :ascii
               )
    end

    test "standard format rejected for partial time" do
      result = Localize.Time.to_string(%{hour: 14, minute: 30}, format: :medium, locale: :en)
      assert match?({:error, _}, result)
    end

    test "derive_format_id/1 produces canonical order" do
      assert :hm = Localize.Time.derive_format_id(%{hour: 14, minute: 30})
      assert :hms = Localize.Time.derive_format_id(%{hour: 14, minute: 30, second: 0})
      assert :ms = Localize.Time.derive_format_id(%{minute: 30, second: 0})
    end
  end

  describe "to_string/2 with skeleton formats" do
    test "hms skeleton" do
      assert {:ok, result} =
               Localize.Time.to_string(~T[14:30:45], format: :hms, locale: :en, prefer: :ascii)

      assert String.contains?(result, "2:30:45")
      assert String.contains?(result, "PM")
    end

    test "Hms skeleton (24-hour)" do
      assert {:ok, result} =
               Localize.Time.to_string(~T[14:30:45], format: :Hms, locale: :en)

      assert String.contains?(result, "14:30:45")
    end

    test "hm skeleton" do
      assert {:ok, result} =
               Localize.Time.to_string(~T[14:30:00], format: :hm, locale: :en, prefer: :ascii)

      assert String.contains?(result, "2:30")
      assert String.contains?(result, "PM")
    end
  end

  describe "to_string/2 with Unicode/ASCII preference" do
    test "ascii produces standard space before AM/PM" do
      {:ok, ascii_result} =
        Localize.Time.to_string(~T[14:30:00], locale: :en, prefer: :ascii)

      assert String.contains?(ascii_result, " PM")
    end

    test "unicode may use narrow no-break space" do
      {:ok, unicode_result} =
        Localize.Time.to_string(~T[14:30:00], locale: :en, prefer: :unicode)

      # Unicode version uses narrow no-break space (\u202F)
      assert String.contains?(unicode_result, "PM")
    end
  end

  describe "to_string/2 error handling" do
    test "non-time map returns error" do
      assert {:error, %Localize.DateTimeFormatError{}} =
               Localize.Time.to_string(%{foo: :bar})
    end

    test "string input returns error" do
      assert {:error, %Localize.DateTimeFormatError{}} =
               Localize.Time.to_string("not a time")
    end
  end

  describe "to_string!/2" do
    test "returns string directly" do
      result = Localize.Time.to_string!(~T[01:23:00], locale: :en, prefer: :ascii)
      assert result == "1:23:00 AM"
    end

    test "raises on error" do
      assert_raise Localize.DateTimeFormatError, fn ->
        Localize.Time.to_string!(%{foo: :bar})
      end
    end
  end
end
