defmodule Localize.DateParseCombiningMarkTest do
  @moduledoc """
  `nnh`'s long date is "'lyɛ'̌ʼ d 'na' MMMM, y" (CLDR `common/main/nnh.xml`):
  a quoted "lyɛ", then a combining caron after the closing quote, so the
  date reads "lyɛ̌ʼ 4 na …, 2024". The caron belongs to the literal text,
  and the quote still closes before it.

  """

  use ExUnit.Case, async: true

  test "a long and full date with a combining mark after a quote reads back" do
    for date <- [~D[2024-03-04], ~D[2024-12-31], ~D[2025-07-15]],
        format <- [:long, :full] do
      {:ok, text} = Localize.Date.to_string(date, locale: :nnh, format: format)
      assert Localize.Date.parse(text, locale: :nnh) == {:ok, date}, text
    end
  end

  test "the long date's literal text is the pattern's, caron and all" do
    {:ok, text} = Localize.Date.to_string(~D[2024-03-04], locale: :nnh, format: :long)
    assert String.starts_with?(text, "lyɛ̌ʼ 4 na ")
    assert String.ends_with?(text, ", 2024")
  end
end
