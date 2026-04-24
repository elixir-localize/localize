defmodule Localize.RawLanguageTagResolutionTest do
  @moduledoc """
  Covers public formatting APIs when passed a raw parsed language tag.

  The test verifies locale resolution across representative date, time,
  interval, relative-time, and list APIs. It does not cover every locale
  or formatting option.
  """

  use ExUnit.Case, async: true

  test "formatting APIs resolve parsed tags whose CLDR locale is not populated" do
    {:ok, raw_fr} = Localize.LanguageTag.parse("fr")

    assert raw_fr.cldr_locale_id == nil
    assert {:ok, "22 mars 2025"} = Localize.Date.to_string(~D[2025-03-22], locale: raw_fr)
    assert {:ok, "14:30:00"} = Localize.Time.to_string(~T[14:30:00], locale: raw_fr)

    assert {:ok, "22 mars 2025, 14:30:00"} =
             Localize.DateTime.to_string(~N[2025-03-22 14:30:00], locale: raw_fr)

    assert {:ok, interval} =
             Localize.Interval.to_string(~D[2025-03-20], ~D[2025-03-22], locale: raw_fr)

    assert String.contains?(interval, "20")
    assert String.contains?(interval, "22 mars 2025")

    assert {:ok, "hier"} =
             Localize.DateTime.Relative.to_string(-1, unit: :day, locale: raw_fr)

    assert {:ok, "a, b et c"} = Localize.List.to_string(["a", "b", "c"], locale: raw_fr)
  end
end
