defmodule Localize.RomanNumeralMonthParseTest do
  @moduledoc """
  `haw`'s short date is "d/M/yy" with its month in lower-case Roman
  numerals (`numbers="M=romanlow"` in CLDR `common/main/haw.xml`), so 31
  December 2024 is "31/xii/24", and a month written so is read back.

  """

  use ExUnit.Case, async: true

  test "a month in Roman numerals is read" do
    assert Localize.Date.parse("31/xii/24", locale: :haw) == {:ok, ~D[2024-12-31]}
    assert Localize.Date.parse("5/i/24", locale: :haw) == {:ok, ~D[2024-01-05]}
    assert Localize.Date.parse("14/iv/25", locale: :haw) == {:ok, ~D[2025-04-14]}
  end

  test "a short date reads back as the formatter writes it" do
    for date <- [~D[2024-01-05], ~D[2024-09-30], ~D[2025-04-14], ~D[2025-12-31]] do
      {:ok, text} = Localize.Date.to_string(date, locale: :haw, format: :short)
      assert Localize.Date.parse(text, locale: :haw) == {:ok, date}, text
    end
  end
end
