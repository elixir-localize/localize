defmodule Localize.IntervalSkeletonTest do
  @moduledoc """
  `Localize.Interval.to_string/3` selects an interval format by its skeleton,
  as CLDR keys interval formats: a date interval takes a skeleton or a
  pattern, and a datetime interval splits a skeleton into its date and time
  fields, as TR35's interval algorithm does (step 3.2).

  The expected values are ICU4C 78.3's `DateIntervalFormat` for the same
  skeletons, except where a test says otherwise.

  """

  use ExUnit.Case, async: true

  @thin " "
  @narrow " "

  defp interval(from, to, options), do: Localize.Interval.to_string(from, to, options)

  describe "a date interval" do
    test "takes a skeleton" do
      for {skeleton, {from, to}, expected} <- [
            {:yMMMd, {~D[2026-06-15], ~D[2026-06-18]}, "Jun 15#{@thin}–#{@thin}18, 2026"},
            {:yMMMEd, {~D[2026-06-15], ~D[2026-06-18]},
             "Mon, Jun 15#{@thin}–#{@thin}Thu, Jun 18, 2026"},
            {:yMMMd, {~D[2026-06-15], ~D[2026-06-15]}, "Jun 15, 2026"},
            {:MMMd, {~D[2026-06-15], ~D[2026-08-18]}, "Jun 15#{@thin}–#{@thin}Aug 18"},
            {:yMd, {~D[2026-06-15], ~D[2026-08-18]}, "6/15/2026#{@thin}–#{@thin}8/18/2026"},
            {:MMMd, {~D[2026-12-30], ~D[2027-01-02]}, "Dec 30, 2026#{@thin}–#{@thin}Jan 2, 2027"}
          ] do
        assert interval(from, to, format: skeleton, locale: :en) == {:ok, expected}
        assert interval(from, to, date_format: skeleton, locale: :en) == {:ok, expected}
      end
    end

    test "takes a skeleton in other locales" do
      assert interval(~D[2026-06-15], ~D[2026-06-18], format: :yMMMEd, locale: :ja) ==
               {:ok, "2026年6月15日(月)～18日(木)"}

      assert interval(~D[2026-06-15], ~D[2026-06-18], format: :yMMMEd, locale: :fr) ==
               {:ok, "lun. 15#{@thin}–#{@thin}jeu. 18 juin 2026"}

      assert interval(~D[2026-06-15], ~D[2026-06-18], format: :yMd, locale: :de) ==
               {:ok, "15.–18.06.2026"}
    end

    # ICU takes no pattern, so these follow TR35's last step: both dates in
    # the pattern around `en`'s fallback "{0} – {1}", or one date when they
    # differ in no field the pattern shows.
    test "takes a pattern" do
      assert interval(~D[2026-06-15], ~D[2026-06-18], format: "d MMM y", locale: :en) ==
               {:ok, "15 Jun 2026#{@thin}–#{@thin}18 Jun 2026"}

      assert interval(~D[2026-06-15], ~D[2026-06-18], date_format: "d MMM y", locale: :en) ==
               {:ok, "15 Jun 2026#{@thin}–#{@thin}18 Jun 2026"}

      assert interval(~D[2026-06-15], ~D[2026-06-18], format: "MMM y", locale: :en) ==
               {:ok, "Jun 2026"}

      assert interval(~D[2026-06-15], ~D[2026-06-15], format: "d MMM y", locale: :en) ==
               {:ok, "15 Jun 2026"}
    end

    test "with a skeleton no format resolves is an error" do
      assert {:error, %Localize.DateTimeUnresolvedFormatError{}} =
               interval(~D[2026-06-15], ~D[2026-06-18], format: :bogus, locale: :en)
    end
  end

  describe "a datetime interval" do
    test "splits a skeleton into its date and time fields" do
      from = ~N[2026-06-15 10:00:00]
      same_day = ~N[2026-06-15 14:30:00]

      for {skeleton, expected} <- [
            {:yMMMdHm, "Jun 15, 2026, 10:00#{@thin}–#{@thin}14:30"},
            {:yMMMdHms, "Jun 15, 2026, 10:00:00#{@thin}–#{@thin}14:30:00"},
            {:yMMMEdhm, "Mon, Jun 15, 2026, 10:00#{@narrow}AM#{@thin}–#{@thin}2:30#{@narrow}PM"},
            {:yMMMdjm, "Jun 15, 2026, 10:00#{@narrow}AM#{@thin}–#{@thin}2:30#{@narrow}PM"}
          ] do
        assert interval(from, same_day, format: skeleton, locale: :en) == {:ok, expected}
      end

      assert interval(from, same_day, format: :yMMMdjm, locale: "en-u-hc-h23") ==
               {:ok, "Jun 15, 2026, 10:00#{@thin}–#{@thin}14:30"}

      assert interval(from, ~N[2026-06-16 14:30:00], format: :yMMMdHm, locale: :en) ==
               {:ok, "Jun 15, 2026, 10:00#{@thin}–#{@thin}Jun 16, 2026, 14:30"}
    end

    test "with a skeleton of time fields writes the times alone" do
      assert interval(~N[2026-06-15 10:00:00], ~N[2026-06-15 14:30:00], format: :Hm, locale: :en) ==
               {:ok, "10:00#{@thin}–#{@thin}14:30"}

      assert {:ok, parts} =
               Localize.Interval.to_parts(~N[2026-06-15 10:00:00], ~N[2026-06-15 14:30:00],
                 format: :Hm,
                 locale: :en
               )

      assert Enum.map_join(parts, & &1.value) == "10:00#{@thin}–#{@thin}14:30"
    end

    # TR35's algorithm read as it is written, as the user chose (2026-10-01):
    # no `Hm` item has a day difference, so both values are formatted with
    # the skeleton around the fallback pattern. ICU4C 78.3 adds the locale's
    # `yMd` date, "6/15/2026, 10:00 – 6/16/2026, 14:30".
    test "with a skeleton of time fields across days writes the times alone" do
      assert interval(~N[2026-06-15 10:00:00], ~N[2026-06-16 14:30:00], format: :Hm, locale: :en) ==
               {:ok, "10:00#{@thin}–#{@thin}14:30"}
    end

    test "with a skeleton of date fields is a date interval" do
      assert interval(~N[2026-06-15 10:00:00], ~N[2026-06-16 14:30:00],
               format: :yMMMd,
               locale: :en
             ) == {:ok, "Jun 15#{@thin}–#{@thin}16, 2026"}

      assert interval(~N[2026-06-15 10:00:00], ~N[2026-06-15 14:30:00],
               format: :yMMMd,
               locale: :en
             ) == {:ok, "Jun 15, 2026"}
    end

    test "joins its parts to the same text" do
      for format <- [:yMMMdHm, :yMMMEdhm, :Hm, :yMMMd] do
        from = ~N[2026-06-15 10:00:00]
        to = ~N[2026-06-15 14:30:00]
        assert {:ok, text} = interval(from, to, format: format, locale: :en)
        assert {:ok, parts} = Localize.Interval.to_parts(from, to, format: format, locale: :en)
        assert Enum.map_join(parts, & &1.value) == text
      end
    end
  end
end
