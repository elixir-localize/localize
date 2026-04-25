defmodule Localize.RawLanguageTagResolutionTest do
  @moduledoc """
  Covers public formatting APIs when passed a raw parsed language tag.

  `Localize.LanguageTag.parse/1` is a parser; it does not populate
  `:cldr_locale_id`. That field is populated by
  `Localize.validate_locale/1`. Formatters route any input through
  `Localize.Locale.cldr_locale_id_from/1`, which validates parsed
  tags transparently while taking a fast path for already-validated
  tags. This test verifies that fast path covers all the public
  formatter modules.
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

    # `Localize.Calendar` had the same nil-cldr_locale_id bug as the
    # other formatters but was not in the original PR; ensure it now
    # also resolves parsed tags.
    assert {:ok, "janvier"} = Localize.Calendar.display_name(:month, 1, locale: raw_fr)
  end
end
