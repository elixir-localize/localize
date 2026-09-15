defmodule Localize.DateParseWeekTest do
  @moduledoc """
  Parsing dates written with CLDR's week-of-year and stand-alone month
  formats.

  A week date parses to the first day of that week under the locale's week
  rules (TR35 §Week Data). `en` (US) weeks start on Sunday and week 1 holds
  1 January, so week 27 of 2024 starts on 30 June; `de` follows ISO 8601,
  whose week 27 of 2024 starts on Monday 1 July, as Erlang's
  `:calendar.iso_week_number/1` confirms.

  `ru`'s `yMMMM` format is "LLLL y 'г'.", with the stand-alone month name:
  CLDR 49's stand-alone July is "июль" and its format July "июля". TR35
  §Parsing Dates and Times accepts either form. Input without a day has no
  `t:Date.t/0`, so it parses with `as: :map` and is an error otherwise, as
  the date and time formatting guide documents.

  """

  use ExUnit.Case, async: true

  test "a week of the year parses to the week's first day" do
    assert Localize.Date.parse("week 27 of 2024", locale: :en) == {:ok, ~D[2024-06-30]}

    assert :calendar.iso_week_number({2024, 7, 1}) == {2024, 27}
    assert :calendar.iso_week_number({2024, 6, 30}) == {2024, 26}
    assert Localize.Date.parse("Woche 27 des Jahres 2024", locale: :de) == {:ok, ~D[2024-07-01]}
  end

  test "a stand-alone or format month name parses as a month and year" do
    july = {:ok, %{calendar: Calendar.ISO, month: 7, year: 2024}}

    assert Localize.Date.parse("июль 2024 г.", locale: :ru, as: :map) == july
    assert Localize.Date.parse("июля 2024 г.", locale: :ru, as: :map) == july

    assert {:error, %Localize.DateParseError{}} =
             Localize.Date.parse("июль 2024 г.", locale: :ru)
  end
end
