defmodule Localize.Message.RelativeTimeFunctionTest do
  use ExUnit.Case, async: true

  alias Localize.DateTime.Relative

  defp format(message, bindings, options \\ []) do
    Localize.Message.format(message, bindings, Keyword.merge([bidi: :none, locale: :en], options))
  end

  describe ":relativeTime with a number" do
    test "formats as Localize.DateTime.Relative does, for each unit, style, numeric and locale" do
      for locale <- [:en, :de, :fa, :ar, :ja],
          unit <- Relative.known_units(),
          number <- [-2, -1, 0, 1, 3, 1.5],
          {style, format} <- [{"long", :standard}, {"short", :short}, {"narrow", :narrow}],
          {numeric, numeric_option} <- [{"auto", :auto}, {"always", :always}] do
        message = "{{{$n :relativeTime unit=#{unit} style=#{style} numeric=#{numeric}}}}"

        expected =
          Relative.to_string(number,
            locale: locale,
            unit: unit,
            format: format,
            numeric: numeric_option
          )

        assert {locale, message, number, format(message, %{"n" => number}, locale: locale)} ==
                 {locale, message, number, expected}
      end
    end

    test "names a near offset unless numeric=always" do
      assert format("{{{$n :relativeTime unit=day}}}", %{"n" => -1}) == {:ok, "yesterday"}
      assert format("{{{$n :relativeTime unit=day}}}", %{"n" => 1}) == {:ok, "tomorrow"}

      assert format("{{{$n :relativeTime unit=day numeric=always}}}", %{"n" => -1}) ==
               {:ok, "1 day ago"}
    end

    test "counts seconds with no unit, in the largest unit reached" do
      assert format("{{{$n :relativeTime}}}", %{"n" => 7200}) == {:ok, "in 2 hours"}
      assert format("{{{$n :relativeTime}}}", %{"n" => -90}) == {:ok, "2 minutes ago"}
    end

    test "takes a Decimal, a number-literal string and a literal operand" do
      assert format("{{{$n :relativeTime unit=hour}}}", %{"n" => Decimal.new("2.5")}) ==
               {:ok, "in 2.5 hours"}

      assert format("{{{$n :relativeTime unit=week}}}", %{"n" => "-3"}) == {:ok, "3 weeks ago"}
      assert format("{{{4 :relativeTime unit=year}}}", %{}) == {:ok, "in 4 years"}
    end

    test "writes the locale's digits" do
      assert format("{{{$n :relativeTime unit=day}}}", %{"n" => 3}, locale: :fa) ==
               Relative.to_string(3, unit: :day, locale: :fa)

      assert {:ok, persian} = format("{{{$n :relativeTime unit=day}}}", %{"n" => 3}, locale: :fa)
      assert persian =~ "۳"
    end
  end

  describe ":relativeTime with a date or time" do
    test "formats the difference from relativeTo, as a variable or a literal" do
      bindings = %{"published" => ~D[2026-11-22], "today" => ~D[2026-11-25]}

      assert format("{{Published {$published :relativeTime relativeTo=$today}}}", bindings) ==
               {:ok, "Published 3 days ago"}

      assert format("{{{$d :relativeTime relativeTo=|2026-11-25|}}}", %{"d" => ~D[2026-11-26]}) ==
               {:ok, "tomorrow"}

      assert format("{{{$d :relativeTime relativeTo=|2026-11-25| unit=week}}}", %{
               "d" => ~D[2026-12-09]
             }) ==
               {:ok, "in 2 weeks"}
    end

    test "takes ISO 8601 operands, datetimes and times" do
      assert format("{{{$d :relativeTime relativeTo=$now}}}", %{
               "d" => "2026-11-24",
               "now" => ~D[2026-11-25]
             }) == {:ok, "yesterday"}

      assert format("{{{$d :relativeTime relativeTo=$now}}}", %{
               "d" => ~U[2026-11-25 09:00:00Z],
               "now" => ~U[2026-11-25 12:00:00Z]
             }) == {:ok, "3 hours ago"}

      assert format("{{{$t :relativeTime relativeTo=$now}}}", %{
               "t" => ~T[10:30:00],
               "now" => ~T[10:00:00]
             }) ==
               {:ok, "in 30 minutes"}
    end

    test "measures against the current time with no relativeTo" do
      tomorrow = Date.add(Date.utc_today(), 1)
      assert format("{{{$d :relativeTime unit=day}}}", %{"d" => tomorrow}) == {:ok, "tomorrow"}
    end
  end

  describe ":relativeTime errors" do
    test "returns an error, never raises, for an option value or operand it cannot use" do
      for {message, bindings} <- [
            {"{{{$n :relativeTime unit=fortnight}}}", %{"n" => 1}},
            {"{{{$n :relativeTime unit=$u}}}", %{"n" => 1, "u" => %{}}},
            {"{{{$n :relativeTime style=wide}}}", %{"n" => 1}},
            {"{{{$n :relativeTime numeric=sometimes}}}", %{"n" => 1}},
            {"{{{$n :relativeTime relativeTo=|yesterday|}}}", %{"n" => ~D[2026-11-25]}},
            {"{{{$n :relativeTime relativeTo=$x}}}", %{"n" => ~D[2026-11-25], "x" => 42}},
            {"{{{$n :relativeTime}}}", %{"n" => "abc"}},
            {"{{{$n :relativeTime}}}", %{"n" => %{}}},
            {"{{{$n :relativeTime relativeTo=$now}}}",
             %{"n" => ~T[10:00:00], "now" => ~D[2026-11-25]}}
          ] do
        assert {:error, %{__exception__: true}} = format(message, bindings),
               inspect({message, bindings})
      end
    end

    test "reports an unbound relativeTo variable" do
      assert {:error, %Localize.BindError{}} =
               format("{{{$d :relativeTime relativeTo=$now}}}", %{"d" => ~D[2026-11-25]})
    end
  end

  describe "the ICU backend" do
    test "leaves a message with a function ICU does not format to the interpreter" do
      for message <- [
            "{{x {$n :relativeTime unit=day}}}",
            "{{x {$n :percent}}}",
            "{{x {$n :currency currency=EUR}}}",
            "{{x {$n :offset add=1}}}",
            "{{x {$n :unit unit=meter}}}",
            "{{x {$n :i:numeral}}}",
            ".input {$n :relativeTime unit=day}\n{{x {$n}}}",
            ".local $m = {$n :percent}\n{{x {$m}}}"
          ],
          locale <- [:en, :de] do
        options = [locale: locale, bidi: :none]

        assert {message, locale,
                Localize.Message.format(message, %{"n" => 3}, [backend: :nif] ++ options)} ==
                 {message, locale,
                  Localize.Message.format(message, %{"n" => 3}, [backend: :elixir] ++ options)}
      end
    end

    test "does so for a parsed message too" do
      {:ok, parsed} = Localize.Message.parse("{{x {$n :relativeTime unit=day}}}")

      assert Localize.Message.format(parsed, %{"n" => 2}, backend: :nif, bidi: :none) ==
               {:ok, "x in 2 days"}
    end
  end
end
