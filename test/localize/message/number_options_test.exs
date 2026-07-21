if Code.ensure_loaded?(Localize.Number) do
  defmodule Localize.Message.NumberOptionsTest do
    use ExUnit.Case, async: true

    alias Localize.Message.{Interpreter, Parser}

    defp format(source, bindings), do: format_with_locale(source, bindings, "en-US")

    defp format_with_locale(source, bindings, locale) do
      {:ok, parsed} = Parser.parse(source)
      options = [locale: locale]

      case Interpreter.format_list(parsed, bindings, options) do
        {:ok, iolist, _, _} ->
          :erlang.iolist_to_binary(iolist)

        {:error, iolist, _, _} ->
          :erlang.iolist_to_binary(iolist)

        {:format_error, payload} ->
          # Don't crash with `CaseClauseError` on unexpected formatter
          # failures — that hides the real diagnosis. Flunk with the
          # payload visible so the cause is obvious in CI output.
          flunk("MF2 interpreter returned :format_error → #{inspect(payload)}")
      end
    end

    describe "useGrouping option" do
      test "useGrouping=auto uses locale default (grouped)" do
        assert format("{{The total is {$n :number useGrouping=auto}}}", %{"n" => 12_345}) ==
                 "The total is 12,345"
      end

      test "useGrouping=always uses locale default (grouped)" do
        assert format("{{The total is {$n :number useGrouping=always}}}", %{"n" => 12_345}) ==
                 "The total is 12,345"
      end

      test "useGrouping=never suppresses grouping separators" do
        assert format("{{The total is {$n :number useGrouping=never}}}", %{"n" => 12_345}) ==
                 "The total is 12345"
      end

      test "useGrouping=never with large number" do
        assert format("{{{$n :number useGrouping=never}}}", %{"n" => 1_234_567}) ==
                 "1234567"
      end

      test "useGrouping=never with small number (no effect)" do
        assert format("{{{$n :number useGrouping=never}}}", %{"n" => 42}) ==
                 "42"
      end

      test "useGrouping=min2 groups only when 2+ digits in group" do
        assert format("{{{$n :number useGrouping=min2}}}", %{"n" => 1000}) ==
                 "1000"
      end

      test "useGrouping=min2 groups when 2+ digits in highest group" do
        assert format("{{{$n :number useGrouping=min2}}}", %{"n" => 10_000}) ==
                 "10,000"
      end

      test "useGrouping=min2 with large number" do
        assert format("{{{$n :number useGrouping=min2}}}", %{"n" => 1_234_567}) ==
                 "1,234,567"
      end

      test "useGrouping with :integer function" do
        assert format("{{{$n :integer useGrouping=never}}}", %{"n" => 12_345}) ==
                 "12345"
      end

      test "useGrouping=never combined with minimumFractionDigits" do
        assert format("{{{$n :number useGrouping=never minimumFractionDigits=2}}}", %{
                 "n" => 1234
               }) ==
                 "1234.00"
      end
    end

    describe "maximumFractionDigits option" do
      test "truncates to specified number of decimal places" do
        assert format("{{{$n :number maximumFractionDigits=2}}}", %{"n" => 3.14159}) ==
                 "3.14"
      end

      test "does not pad when fewer digits" do
        assert format("{{{$n :number maximumFractionDigits=2}}}", %{"n" => 3.1}) ==
                 "3.1"
      end

      test "no decimal for whole number" do
        assert format("{{{$n :number maximumFractionDigits=2}}}", %{"n" => 3.0}) ==
                 "3"
      end

      test "maximumFractionDigits=0 removes all decimals" do
        assert format("{{{$n :number maximumFractionDigits=0}}}", %{"n" => 3.14}) ==
                 "3"
      end

      test "maximumFractionDigits=4 allows up to 4 places" do
        assert format("{{{$n :number maximumFractionDigits=4}}}", %{"n" => 3.14159}) ==
                 "3.1416"
      end

      test "preserves grouping separators" do
        assert format("{{{$n :number maximumFractionDigits=2}}}", %{"n" => 12_345.6789}) ==
                 "12,345.68"
      end

      test "combined with minimumFractionDigits" do
        assert format(
                 "{{{$n :number minimumFractionDigits=1 maximumFractionDigits=4}}}",
                 %{"n" => 3.14159}
               ) == "3.1416"
      end

      test "combined min/max pads to minimum" do
        assert format(
                 "{{{$n :number minimumFractionDigits=1 maximumFractionDigits=4}}}",
                 %{"n" => 3.0}
               ) == "3.0"
      end

      test "combined with useGrouping=never" do
        assert format(
                 "{{{$n :number maximumFractionDigits=2 useGrouping=never}}}",
                 %{"n" => 12_345.6789}
               ) == "12345.68"
      end
    end

    describe "numberingSystem option" do
      test "numberingSystem=arab formats with Arabic-Indic digits" do
        assert format_with_locale(
                 "{{{$n :number numberingSystem=arab}}}",
                 %{"n" => 12_345},
                 "ar"
               ) ==
                 "\u{0661}\u{0662}\u{066C}\u{0663}\u{0664}\u{0665}"
      end

      test "numberingSystem=latn overrides native system" do
        assert format_with_locale(
                 "{{{$n :number numberingSystem=latn}}}",
                 %{"n" => 12_345},
                 "ar"
               ) ==
                 "12,345"
      end

      test "numberingSystem with :integer function" do
        assert format_with_locale(
                 "{{{$n :integer numberingSystem=arab}}}",
                 %{"n" => 99},
                 "ar"
               ) ==
                 "\u{0669}\u{0669}"
      end

      test "numberingSystem combined with useGrouping=never" do
        result =
          format_with_locale(
            "{{{$n :number numberingSystem=arab useGrouping=never}}}",
            %{"n" => 12_345},
            "ar"
          )

        # Should use Arabic digits without grouping separator
        refute String.contains?(result, ",")
        refute String.contains?(result, "\u{066C}")
      end

      test "numberingSystem=thai renders Thai digits in an en locale (Intl/ICU semantics)" do
        assert Localize.Message.format(
                 "{$n :number numberingSystem=thai}",
                 %{"n" => 5},
                 locale: :en
               ) == {:ok, "\u{0E55}"}
      end

      test "a foreign numberingSystem keeps the locale's symbols" do
        assert Localize.Message.format(
                 "{$n :number numberingSystem=arab}",
                 %{"n" => 1234.5},
                 locale: :en
               ) == {:ok, "\u{0661},\u{0662}\u{0663}\u{0664}.\u{0665}"}
      end

      test "a foreign numberingSystem works with :currency" do
        assert Localize.Message.format(
                 "{$n :currency currency=USD numberingSystem=thai}",
                 %{"n" => 2},
                 locale: :en
               ) == {:ok, "$\u{0E52}.\u{0E50}\u{0E50}"}
      end

      test "a numeric numberingSystem transliterates digits with the locale's grouping" do
        assert Localize.Message.format(
                 "{$n :number numberingSystem=thai}",
                 %{"n" => 1234.5},
                 locale: :en
               ) == {:ok, "\u{0E51},\u{0E52}\u{0E53}\u{0E54}.\u{0E55}"}
      end

      test "an algorithmic numberingSystem formats via RBNF (hans)" do
        assert Localize.Message.format(
                 "{$n :number numberingSystem=hans}",
                 %{"n" => 1234},
                 locale: :en
               ) == {:ok, "一千二百三十四"}
      end

      test "an algorithmic numberingSystem formats via RBNF (roman)" do
        assert Localize.Message.format(
                 "{$n :number numberingSystem=roman}",
                 %{"n" => 1234},
                 locale: :en
               ) == {:ok, "MCCXXXIV"}
      end

      test "an algorithmic numberingSystem works with :integer" do
        assert Localize.Message.format(
                 "{$n :integer numberingSystem=roman}",
                 %{"n" => 42},
                 locale: :en
               ) == {:ok, "XLII"}
      end

      test "an algorithmic numberingSystem matches Localize.Number.to_string/2" do
        assert Localize.Message.format(
                 "{$n :number numberingSystem=hans}",
                 %{"n" => 1234},
                 locale: :en
               ) == Localize.Number.to_string(1234, number_system: :hans, locale: :en)
      end

      test "an algorithmic numberingSystem formats negative numbers via RBNF" do
        assert Localize.Message.format(
                 "{$n :number numberingSystem=hans}",
                 %{"n" => -1234},
                 locale: :en
               ) == {:ok, "负一千二百三十四"}
      end

      test "useGrouping is ignored for an algorithmic numberingSystem" do
        assert Localize.Message.format(
                 "{$n :number numberingSystem=hans useGrouping=never}",
                 %{"n" => 1234},
                 locale: :en
               ) == {:ok, "一千二百三十四"}
      end

      test ":percent with an algorithmic numberingSystem degrades to the default system's pattern" do
        assert Localize.Message.format(
                 "{$n :percent numberingSystem=hans}",
                 %{"n" => 0.5},
                 locale: :en
               ) == {:ok, "50%"}
      end

      test "an unknown numberingSystem name is still an error" do
        assert {:error, %Localize.FormatError{}} =
                 Localize.Message.format(
                   "{$n :number numberingSystem=bogus}",
                   %{"n" => 5},
                   locale: :en
                 )
      end
    end

    # The MF2 `signDisplay` option delegates to the `:sign_display`
    # option of `Localize.Number.to_string/2` — the interpreter does
    # no sign handling of its own.
    describe "signDisplay option" do
      test "auto shows only the negative sign" do
        assert format("{{{$n :number signDisplay=auto}}}", %{"n" => -1234.5}) == "-1,234.5"
        assert format("{{{$n :number signDisplay=auto}}}", %{"n" => 1234.5}) == "1,234.5"
      end

      test "always shows a sign on every value including zero" do
        assert format("{{{$n :number signDisplay=always}}}", %{"n" => 1234.5}) == "+1,234.5"
        assert format("{{{$n :number signDisplay=always}}}", %{"n" => -1234.5}) == "-1,234.5"
        assert format("{{{$n :number signDisplay=always}}}", %{"n" => 0}) == "+0"
      end

      test "exceptZero shows a sign except on zero" do
        assert format("{{{$n :number signDisplay=exceptZero}}}", %{"n" => 1234.5}) == "+1,234.5"
        assert format("{{{$n :number signDisplay=exceptZero}}}", %{"n" => -1234.5}) == "-1,234.5"
        assert format("{{{$n :number signDisplay=exceptZero}}}", %{"n" => 0}) == "0"
      end

      test "negative shows a sign only on negative non-zero values" do
        assert format("{{{$n :number signDisplay=negative}}}", %{"n" => -1234.5}) == "-1,234.5"
        assert format("{{{$n :number signDisplay=negative}}}", %{"n" => 1234.5}) == "1,234.5"
        assert format("{{{$n :number signDisplay=negative}}}", %{"n" => 0}) == "0"
      end

      test "never suppresses the sign entirely" do
        assert format("{{{$n :number signDisplay=never}}}", %{"n" => -1234.5}) == "1,234.5"
        assert format("{{{$n :number signDisplay=never}}}", %{"n" => 1234.5}) == "1,234.5"
      end

      test "signDisplay composes with numberingSystem" do
        assert Localize.Message.format(
                 "{$n :number signDisplay=always numberingSystem=thai}",
                 %{"n" => 1234.5},
                 locale: :en
               ) == {:ok, "+๑,๒๓๔.๕"}
      end

      test "signDisplay matches Localize.Number.to_string/2" do
        assert Localize.Message.format(
                 "{$n :number signDisplay=exceptZero}",
                 %{"n" => 1234.5},
                 locale: :en
               ) == Localize.Number.to_string(1234.5, locale: :en, sign_display: :except_zero)
      end

      test "an invalid signDisplay value is an error" do
        assert {:error, %Localize.FormatError{}} =
                 Localize.Message.format(
                   "{$n :number signDisplay=sometimes}",
                   %{"n" => 5},
                   locale: :en
                 )
      end
    end
  end
end
