defmodule Localize.TimeParseTest do
  @moduledoc """
  A time parses back as the formatter writes it, whatever order the
  locale's patterns arrive in.

  The expected times are ICU4C 78.3's readings of the same text with the
  pattern the locale writes it in, except where a test says otherwise.

  """

  use ExUnit.Case, async: true

  describe "a day period" do
    # `ms` writes its short time "h:mm a" and names its day periods "PG" and
    # "PTG", which a pattern with a zone would read as a zone.
    test "is read as a day period, not a zone" do
      assert Localize.Time.parse("11:59 PTG", locale: :ms) == {:ok, ~T[23:59:00]}
      assert Localize.Time.parse("12:30 PG", locale: :ms) == {:ok, ~T[00:30:00]}

      assert Localize.Time.parse("11:59 PTG", locale: :ms, as: :map) ==
               {:ok, %{hour: 23, minute: 59}}

      assert Localize.Time.parse("12:30:00 BN", locale: :ku) == {:ok, ~T[00:30:00]}
      assert Localize.Time.parse("11:59:59 UT", locale: :ebu) == {:ok, ~T[23:59:59]}
    end

    # `sd-Deva` names no flexible day periods, and its "h:mm:ss a" is read
    # before a pattern with one.
    test "is read by the pattern that writes it" do
      assert Localize.Time.parse("11:59:59 PM", locale: :"sd-Deva") == {:ok, ~T[23:59:59]}
    end
  end

  describe "a flexible day period" do
    # `fr` calls morning1 (04:00–12:00) and night1 (00:00–04:00) "matin"
    # alike, so the name is the period the hour falls in.
    test "is the period of that name its hour falls in" do
      assert Localize.Time.parse("9:05:00 matin", locale: :fr) == {:ok, ~T[09:05:00]}
      assert Localize.Time.parse("11:59:00 matin", locale: :fr) == {:ok, ~T[11:59:00]}
      assert Localize.Time.parse("2:00:00 du matin", locale: :fr) == {:ok, ~T[02:00:00]}
      assert Localize.Time.parse("1:45 mchana", locale: :sw) == {:ok, ~T[13:45:00]}
    end

    # `gl` calls midnight and night1 (21:00–24:00) "da noite".
    test "is midnight or noon at its hour" do
      assert Localize.Time.parse("12 da noite", locale: :gl) == {:ok, ~T[00:00:00]}
    end

    # TR35: where a locale gives a flexible day period no name, formatting
    # falls back to its AM and PM names. `oc` has no day-period rules, and
    # ICU4C writes 23:59 in its `Bhm` pattern "h:mm B" as "11:59 PM" but does
    # not read that back.
    test "is read as AM or PM where the locale names none" do
      assert Localize.Time.to_string(~T[23:59:00], locale: :oc, format: :Bhm) ==
               {:ok, "11:59 PM"}

      assert Localize.Time.parse("11:59 PM", locale: :oc) == {:ok, ~T[23:59:00]}
    end
  end
end
