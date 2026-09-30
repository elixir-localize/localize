defmodule Localize.Data.Normalize.NumberTest do
  @moduledoc """
  Covers which numbering systems' data the number normalizer keeps from
  the CLDR JSON, which carries every system in every locale, resolved.

  """

  use ExUnit.Case, async: true

  alias Localize.Data.Normalize.Number

  @latn_symbols %{"decimal" => ".", "group" => ",", "percent_sign" => "%"}
  @latn_decimal %{"standard" => "#,##0.###"}

  # A locale whose own systems are `latn` and `deva`: `thai` repeats its
  # `latn` data, as root's alias gives it; `arab` has root's own symbols
  # and the `latn` decimal pattern; `mong` has a percent sign of its own.
  defp content do
    %{
      "numbers" => %{
        "default_numbering_system" => "latn",
        "other_numbering_systems" => %{"native" => "deva"},
        "minimum_grouping_digits" => "1",
        "symbols_number_system_latn" => @latn_symbols,
        "decimal_formats_number_system_latn" => @latn_decimal,
        "symbols_number_system_deva" => @latn_symbols,
        "decimal_formats_number_system_deva" => @latn_decimal,
        "symbols_number_system_thai" => @latn_symbols,
        "decimal_formats_number_system_thai" => @latn_decimal,
        "symbols_number_system_arab" => %{@latn_symbols | "decimal" => "٫", "group" => "٬"},
        "decimal_formats_number_system_arab" => @latn_decimal,
        "symbols_number_system_mong" => %{@latn_symbols | "percent_sign" => "᠓"},
        "decimal_formats_number_system_mong" => @latn_decimal
      }
    }
  end

  test "keeps a system outside the locale's own only where it differs from latn" do
    normalized = Number.normalize(content(), "und")
    kept = [:arab, :deva, :latn, :mong]

    assert normalized["number_symbols"] |> Map.keys() |> Enum.sort() == kept
    assert normalized["number_formats"] |> Map.keys() |> Enum.sort() == kept
  end

  test "keeps each kind of data on its own" do
    normalized = Number.normalize(content(), "und")

    assert get_in(normalized, ["number_symbols", :arab, :decimal, :standard]) == "٫"
    assert get_in(normalized, ["number_formats", :arab, :standard]) == nil
    assert get_in(normalized, ["number_formats", :latn, :standard]) == "#,##0.###"
  end

  test "keeps the locale's own systems even where they repeat latn" do
    normalized = Number.normalize(content(), "und")

    assert get_in(normalized, ["number_formats", :deva, :standard]) == "#,##0.###"
    assert get_in(normalized, ["number_symbols", :deva, :decimal, :standard]) == "."
  end
end
