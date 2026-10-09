defmodule Localize.DateTime.ParseLengthTest do
  @moduledoc """
  Covers the bound on the length of text a parse function reads.

  Reading a date and time tries each place the text could divide into a date
  half and a time half, so the work grows with the square of the text: 8,000
  bytes of `"June "` took 232 ms where 500 bytes took 1.7 ms. The bound makes
  that constant, and these tests hold it to the text a locale can actually
  write.

  """

  use ExUnit.Case, async: false

  alias Localize.DateTime.ParseOptions

  doctest Localize.DateTime.ParseOptions, import: true

  # Swept over all 657 locales when the bound was chosen: the longest text any
  # of them writes is 666 bytes, a full Dzongkha interval of two zoned
  # date-times, and 329 bytes for one date and time. These stand for that
  # sweep, which must not be repeated here — loading every locale fills the
  # literal area and `Localize.LiteralMemory` then stops writing the caches
  # the rest of the suite relies on.
  @longest_writing_locales [:dz, :ccp, :bo, :as, :am]

  setup do
    on_exit(fn -> Application.delete_env(:localize, :max_parse_length) end)
    :ok
  end

  describe "the default bound" do
    test "is 1,024 bytes" do
      assert ParseOptions.max_parse_length() == 1_024
    end

    test "admits the longest text the longest-writing locales produce" do
      from = DateTime.new!(~D[2026-06-15], ~T[10:30:00], "Australia/Sydney", Tz.TimeZoneDatabase)
      to = DateTime.new!(~D[2027-08-20], ~T[14:45:00], "Australia/Sydney", Tz.TimeZoneDatabase)

      longest =
        @longest_writing_locales
        |> Enum.map(fn locale ->
          case Localize.Interval.to_string(from, to, locale: locale, format: :full) do
            {:ok, text} -> byte_size(text)
            _unwritten -> 0
          end
        end)
        |> Enum.max()

      assert longest >= 600, "expected one of these locales to write 600 bytes or more"

      assert longest <= ParseOptions.max_parse_length(),
             "the bound of #{ParseOptions.max_parse_length()} would refuse text of #{longest} bytes that a locale writes"
    end
  end

  describe "text past the bound" do
    test "is refused by every parse function" do
      text = String.duplicate("June ", 400)
      assert byte_size(text) > ParseOptions.max_parse_length()

      for {label, result} <- [
            {"Date.parse", Localize.Date.parse(text, locale: :en)},
            {"Time.parse", Localize.Time.parse(text, locale: :en)},
            {"DateTime.parse", Localize.DateTime.parse(text, locale: :en)},
            {"Interval.parse", Localize.Interval.parse(text, locale: :en)},
            {"DateTime.Parser.parse", Localize.DateTime.Parser.parse(text, locale: :en)}
          ] do
        assert {:error, %Localize.DateTimeParseLengthError{}} = result,
               "#{label} did not refuse #{byte_size(text)} bytes"
      end
    end

    test "names the length it was given and the bound it passed" do
      text = String.duplicate("a", 2_000)

      assert {:error, exception} = Localize.DateTime.parse(text, locale: :en)

      assert %Localize.DateTimeParseLengthError{input_length: 2_000, max_length: 1_024} =
               exception

      assert Exception.message(exception) =~ "2,000"
      assert Exception.message(exception) =~ "1,024"
    end

    test "is refused in constant time" do
      short = String.duplicate("June ", 205)
      long = String.duplicate("June ", 1_638)

      assert byte_size(short) > ParseOptions.max_parse_length()

      {short_time, _} = :timer.tc(fn -> Localize.DateTime.parse(short, locale: :en) end)
      {long_time, _} = :timer.tc(fn -> Localize.DateTime.parse(long, locale: :en) end)

      # Eight times the text, and the refusal is a length check either way.
      assert long_time < max(short_time * 4, 2_000),
             "refusing #{byte_size(long)} bytes took #{long_time}µs against #{short_time}µs for #{byte_size(short)}"
    end
  end

  describe "text within the bound" do
    test "is read as it was before" do
      assert {:ok, _} = Localize.DateTime.parse("Jun 15, 2026, 10:30:00 AM", locale: :en)
      assert {:ok, _} = Localize.DateTime.parse("2026-06-15T10:30:00Z", locale: :en)
      assert {:ok, _} = Localize.Date.parse("Jun 15, 2026", locale: :en)
      assert {:ok, _} = Localize.Time.parse("10:30:00 AM", locale: :en)
    end

    test "text that is not a date is still reported as unparseable, not as too long" do
      text = String.duplicate("June ", 200)
      assert byte_size(text) <= ParseOptions.max_parse_length()

      assert {:error, exception} = Localize.DateTime.parse(text, locale: :en)
      refute match?(%Localize.DateTimeParseLengthError{}, exception)
    end
  end

  describe ":max_parse_length" do
    test "raises the bound" do
      text = String.duplicate("a", 2_000)

      assert {:error, %Localize.DateTimeParseLengthError{}} =
               Localize.Date.parse(text, locale: :en)

      Application.put_env(:localize, :max_parse_length, 4_096)

      assert ParseOptions.max_parse_length() == 4_096
      assert {:error, exception} = Localize.Date.parse(text, locale: :en)
      refute match?(%Localize.DateTimeParseLengthError{}, exception)
    end

    test "lowers the bound" do
      Application.put_env(:localize, :max_parse_length, 8)

      assert {:error, %Localize.DateTimeParseLengthError{max_length: 8}} =
               Localize.DateTime.parse("Jun 15, 2026, 10:30:00 AM", locale: :en)
    end
  end
end
