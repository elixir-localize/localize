defmodule Localize.DateParseCommaTest do
  @moduledoc """
  A comma in a date pattern may be left out of the input where the pattern
  also has a space there ("May 5 2026" for `en`'s "MMM d, y"), but not where
  the comma is the only thing between two fields: `en-ZW`'s `yMMMdd` is
  "dd MMM,y" (CLDR `common/main/en_ZW.xml`), and "May 2019", its `yMMM`
  "MMM y", is May 2019, not 20 May 2019 with the day and year run together.

  """

  use ExUnit.Case, async: true

  test "a month and year is read as a month and year" do
    assert Localize.Date.parse("May 2019", locale: "en-ZW", as: :map) ==
             {:ok, %{calendar: Calendar.ISO, month: 5, year: 2019}}

    assert Localize.Date.parse("May 2019", locale: :en, as: :map) ==
             {:ok, %{calendar: Calendar.ISO, month: 5, year: 2019}}
  end

  test "a comma that is its literal's only separator is kept" do
    assert Localize.Date.parse("20 May,2019", locale: "en-ZW") == {:ok, ~D[2019-05-20]}
  end

  test "a comma beside a space may be left out" do
    assert Localize.Date.parse("May 5 2026", locale: :en) == {:ok, ~D[2026-05-05]}
    assert Localize.Date.parse("May 5, 2026", locale: :en) == {:ok, ~D[2026-05-05]}
    assert Localize.Date.parse("20 May, 2019", locale: "en-ZW") == {:ok, ~D[2019-05-20]}
  end
end
