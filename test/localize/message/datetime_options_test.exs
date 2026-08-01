defmodule Localize.Message.DateTimeOptionsTest do
  use ExUnit.Case, async: true

  alias Localize.Message.{Interpreter, Parser}

  defp format(source, bindings), do: format_with_locale(source, bindings, "en-US")

  defp format_with_locale(source, bindings, locale) do
    {:ok, parsed} = Parser.parse(source)
    options = [locale: locale]

    case Interpreter.format_list(parsed, bindings, options) do
      {:ok, iolist, _, _} -> :erlang.iolist_to_binary(iolist)
      {:error, iolist, _, _} -> :erlang.iolist_to_binary(iolist)
    end
  end

  describe ":date function" do
    test "formats ISO 8601 date string" do
      result = format("{|2006-01-02| :date}", %{})
      assert result == "Jan 2, 2006"
    end

    test "formats date from datetime string" do
      result = format("{|2006-01-02T15:04:06| :date}", %{})
      assert result == "Jan 2, 2006"
    end

    test "formats with length=long" do
      result = format("{|2006-01-02| :date length=long}", %{})
      assert result == "January 2, 2006"
    end

    test "formats with style=short" do
      result = format("{|2006-01-02| :date style=short}", %{})
      assert result == "1/2/06"
    end

    test "formats Date struct from binding" do
      result = format("{$d :date}", %{"d" => ~D[2006-01-02]})
      assert result == "Jan 2, 2006"
    end

    test "formats NaiveDateTime as date from binding" do
      result = format("{$d :date}", %{"d" => ~N[2006-01-02 15:04:06]})
      assert result == "Jan 2, 2006"
    end

    test "local variable with date" do
      result = format(".local $d = {|2006-01-02| :date length=long} {{{$d}}}", %{})
      assert result == "January 2, 2006"
    end
  end

  describe ":time function" do
    test "formats time from datetime string" do
      result = format("{|2006-01-02T15:04:06| :time}", %{})
      assert String.contains?(result, "3:04")
    end

    test "formats with precision=second" do
      result = format("{|2006-01-02T15:04:06| :time precision=second}", %{})
      assert String.contains?(result, "3:04:06")
    end

    test "formats with style=short" do
      result = format("{|2006-01-02T15:04:06| :time style=short}", %{})
      assert String.contains?(result, "3:04")
    end

    test "formats NaiveDateTime from binding" do
      result = format("{$t :time}", %{"t" => ~N[2006-01-02 15:04:06]})
      assert String.contains?(result, "3:04")
    end

    test "local variable with time" do
      result =
        format(
          ".local $t = {|2006-01-02T15:04:06| :time precision=second} {{{$t}}}",
          %{}
        )

      assert String.contains?(result, "3:04:06")
    end
  end

  describe ":datetime function" do
    test "formats datetime from ISO string" do
      result = format("{|2006-01-02T15:04:06| :datetime}", %{})
      assert String.contains?(result, "2006")
      assert String.contains?(result, "3:04")
    end

    test "formats with dateStyle=long" do
      result = format("{|2006-01-02T15:04:06| :datetime dateStyle=long}", %{})
      assert String.contains?(result, "January 2, 2006")
    end

    test "formats with dateLength=long (alias)" do
      result = format("{|2006-01-02T15:04:06| :datetime dateLength=long}", %{})
      assert String.contains?(result, "January 2, 2006")
    end

    test "formats with timeStyle=short" do
      result = format("{|2006-01-02T15:04:06| :datetime timeStyle=short}", %{})
      assert String.contains?(result, "3:04")
      refute String.contains?(result, "3:04:06")
    end

    test "formats with timePrecision=second" do
      result = format("{|2006-01-02T15:04:06| :datetime timePrecision=second}", %{})
      assert String.contains?(result, "3:04:06")
    end

    test "formats with combined dateStyle and timeStyle" do
      result =
        format("{|2006-01-02T15:04:06| :datetime dateStyle=long timeStyle=short}", %{})

      assert String.contains?(result, "January 2, 2006")
    end

    test "formats with style=short (applies to both date and time)" do
      result = format("{|2006-01-02T15:04:06| :datetime style=short}", %{})
      assert String.contains?(result, "1/2/06")
    end

    test "formats NaiveDateTime from binding" do
      result = format("{$dt :datetime}", %{"dt" => ~N[2006-01-02 15:04:06]})
      assert String.contains?(result, "2006")
      assert String.contains?(result, "3:04")
    end

    test "formats DateTime from binding" do
      dt = DateTime.new!(~D[2006-01-02], ~T[15:04:06], "Etc/UTC")
      result = format("{$dt :datetime}", %{"dt" => dt})
      assert String.contains?(result, "2006")
    end

    test "formats Date from binding (adds midnight time)" do
      result = format("{$dt :datetime}", %{"dt" => ~D[2006-01-02]})
      assert String.contains?(result, "2006")
    end
  end

  describe "locale-specific formatting" do
    test "date with German locale" do
      result = format_with_locale("{|2006-01-02| :date}", %{}, "de")
      assert String.contains?(result, "2006")
    end

    test "datetime with French locale" do
      result = format_with_locale("{|2006-01-02T15:04:06| :datetime}", %{}, "fr")
      assert String.contains?(result, "2006")
    end
  end
end
