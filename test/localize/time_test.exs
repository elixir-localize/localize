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

    test "standard format on partial time derives a skeleton from present fields" do
      # Hour + minute under `:medium` should render as the `:hm` skeleton
      # (`h:mm a` in English), not error with DateTimeUnresolvedFormatError
      # and not include an empty `ss` slot.
      assert {:ok, "2:30\u202FPM"} =
               Localize.Time.to_string(%{hour: 14, minute: 30},
                 format: :medium,
                 locale: :en,
                 prefer: :unicode
               )

      assert {:ok, "2:30 PM"} =
               Localize.Time.to_string(%{hour: 14, minute: 30},
                 format: :medium,
                 locale: :en,
                 prefer: :ascii
               )
    end

    test "standard format on hour-only partial time derives :h skeleton" do
      # Hour alone under `:medium` should render as the `:h` skeleton
      # (`h a` in English). Previously returned
      # DateTimeUnresolvedFormatError{format: :medium}.
      assert {:ok, "2 PM"} =
               Localize.Time.to_string(%{hour: 14},
                 format: :medium,
                 locale: :en,
                 prefer: :ascii
               )
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
      assert {:error, %Localize.DateTimeInvalidInputError{}} =
               Localize.Time.to_string(%{foo: :bar})
    end

    test "string input returns error" do
      assert {:error, %Localize.DateTimeInvalidInputError{}} =
               Localize.Time.to_string("not a time")
    end
  end

  describe "to_string!/2" do
    test "returns string directly" do
      result = Localize.Time.to_string!(~T[01:23:00], locale: :en, prefer: :ascii)
      assert result == "1:23:00 AM"
    end

    test "raises on error" do
      assert_raise Localize.DateTimeInvalidInputError, fn ->
        Localize.Time.to_string!(%{foo: :bar})
      end
    end
  end

  describe "hour_format_from_locale/1" do
    test "24-hour locales return :h23" do
      assert {:ok, :h23} = Localize.Time.hour_format_from_locale(:ja)
      assert {:ok, :h23} = Localize.Time.hour_format_from_locale(:de)
      assert {:ok, :h23} = Localize.Time.hour_format_from_locale(:fr)
    end

    test "12-hour locales return :h12" do
      assert {:ok, :h12} = Localize.Time.hour_format_from_locale(:en)
      assert {:ok, :h12} = Localize.Time.hour_format_from_locale("en-AU")
    end

    test "honours -u-hc-h12 override on a 24-hour locale" do
      assert {:ok, :h12} = Localize.Time.hour_format_from_locale("fr-u-hc-h12")
    end

    test "honours -u-hc-h23 override on a 12-hour locale" do
      assert {:ok, :h23} = Localize.Time.hour_format_from_locale("en-u-hc-h23")
    end

    test "honours -u-hc-h11 override" do
      assert {:ok, :h11} = Localize.Time.hour_format_from_locale("ja-u-hc-h11")
    end

    test "accepts a LanguageTag struct directly" do
      {:ok, language_tag} = Localize.validate_locale("fr-u-hc-h12")
      assert {:ok, :h12} = Localize.Time.hour_format_from_locale(language_tag)
    end

    test "bang variant returns the bare cycle atom" do
      assert :h23 == Localize.Time.hour_format_from_locale!(:ja)
    end
  end

  describe "to_string/2 honours -u-hc- on standard formats" do
    # Reported by @woylie as a follow-up to #22. Standard formats
    # (`:short`/`:medium`/`:long`/`:full`) used to read the locale's
    # static `time_formats[:style]` skeleton with no awareness of any
    # `-u-hc-` Unicode-extension override, so e.g. `"fr-u-hc-h12"`
    # silently produced 24-hour output. The fix remaps the standard
    # format to the locale's cycle-appropriate `:hm`/`:hms`/`:hmsv`
    # (12-hour) or `:Hm`/`:Hms`/`:Hmsv` (24-hour) skeleton.

    test "fr-u-hc-h12 flips :short/:medium to 12-hour with AM/PM" do
      assert {:ok, "9:00 PM"} =
               Localize.Time.to_string(~T[21:00:00], format: :short, locale: "fr-u-hc-h12")

      assert {:ok, "9:00:00 PM"} =
               Localize.Time.to_string(~T[21:00:00], format: :medium, locale: "fr-u-hc-h12")
    end

    test "en-u-hc-h23 flips :short/:medium to 24-hour, no AM/PM" do
      assert {:ok, "21:00"} =
               Localize.Time.to_string(~T[21:00:00], format: :short, locale: "en-u-hc-h23")

      assert {:ok, "21:00:00"} =
               Localize.Time.to_string(~T[21:00:00], format: :medium, locale: "en-u-hc-h23")
    end

    test "ja-u-hc-h12 emits Japanese AM/PM marker before the time" do
      {:ok, short} =
        Localize.Time.to_string(~T[21:00:00], format: :short, locale: "ja-u-hc-h12")

      assert short =~ "午後"
      assert short =~ "9"
      refute short =~ "21"
    end

    test "no override: ja keeps its native 24-hour cycle" do
      assert {:ok, "21:00"} = Localize.Time.to_string(~T[21:00:00], format: :short, locale: :ja)

      assert {:ok, "21:00:00"} =
               Localize.Time.to_string(~T[21:00:00], format: :medium, locale: :ja)
    end

    test "no override: en keeps its native 12-hour cycle" do
      assert {:ok, "9:00 PM"} =
               Localize.Time.to_string(~T[21:00:00], format: :short, locale: :en, prefer: :ascii)
    end

    test "non-standard format atom (skeleton) is not remapped by hc override" do
      # Skeleton-style formats are not touched — the user explicitly
      # asked for `:Hms`, the cycle is implicit in the symbol.
      assert {:ok, "21:00:00"} =
               Localize.Time.to_string(~T[21:00:00], format: :Hms, locale: "fr-u-hc-h12")
    end
  end
end
