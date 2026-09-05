defmodule Localize.MinimalPairsTest do
  use ExUnit.Case, async: true

  doctest Localize.MinimalPairs

  alias Localize.MinimalPairs

  describe "category accessors" do
    test "cardinal pairs are keyed by plural category" do
      assert {:ok, %{one: "{0} day", other: "{0} days"}} = MinimalPairs.cardinal(:en)
    end

    test "ordinal pairs cover the locale's ordinal categories" do
      assert {:ok, pairs} = MinimalPairs.ordinal(:en)
      assert Enum.sort(Map.keys(pairs)) == [:few, :one, :other, :two]
    end

    test "case and gender pairs are present for a locale that inflects" do
      assert {:ok, cases} = MinimalPairs.grammatical_case(:de)
      assert :genitive in Map.keys(cases)

      assert {:ok, genders} = MinimalPairs.grammatical_gender(:de)
      assert Enum.sort(Map.keys(genders)) == [:feminine, :masculine, :neuter]
    end

    test "an uninflected locale returns an empty map rather than an error" do
      assert {:ok, %{}} = MinimalPairs.grammatical_case(:en)
      assert {:ok, %{}} = MinimalPairs.grammatical_gender(:en)
    end

    test "a locale CLDR ships no pairs for returns an empty map" do
      assert {:ok, %{}} = MinimalPairs.cardinal(:und)
    end
  end

  describe "format/3" do
    test "selects the pair the number's plural category calls for" do
      assert {:ok, "1 day"} = MinimalPairs.format(1, :cardinal, locale: :en)
      assert {:ok, "0 days"} = MinimalPairs.format(0, :cardinal, locale: :en)
      assert {:ok, "3 days"} = MinimalPairs.format(3, :cardinal, locale: :en)
    end

    test "ordinals select on the ordinal rules, not the cardinal ones" do
      assert {:ok, "Take the 1st right."} = MinimalPairs.format(1, :ordinal, locale: :en)
      assert {:ok, "Take the 2nd right."} = MinimalPairs.format(2, :ordinal, locale: :en)
      assert {:ok, "Take the 3rd right."} = MinimalPairs.format(3, :ordinal, locale: :en)
      assert {:ok, "Take the 4th right."} = MinimalPairs.format(4, :ordinal, locale: :en)
    end

    test "a locale with more plural categories uses them" do
      # German separates the number from the noun with a no-break space.
      assert {:ok, "1\u00A0Tag"} = MinimalPairs.format(1, :cardinal, locale: :de)
      assert {:ok, "2\u00A0Tage"} = MinimalPairs.format(2, :cardinal, locale: :de)
    end

    test "defaults to cardinal" do
      assert MinimalPairs.format(2, locale: :en) == {:ok, "2 days"}
    end
  end

  describe "invalid input is returned, not raised" do
    test "an unknown category" do
      assert {:error, %Localize.InvalidValueError{}} =
               MinimalPairs.format(1, :bogus, locale: :en)
    end

    test "an unknown locale" do
      # "not-a-locale" is well-formed BCP-47 and resolves to root; these are
      # not parseable at all.
      assert {:error, %Localize.InvalidLocaleError{}} = MinimalPairs.cardinal("zz-Nope")

      assert {:error, %Localize.InvalidLocaleError{}} =
               MinimalPairs.format(1, :cardinal, locale: "!!!")
    end

    test "a locale with no pair for the selected category" do
      assert {:error, %Localize.NoMinimalPairError{}} =
               MinimalPairs.format(1, :ordinal, locale: :und)
    end
  end

  describe "categories/0" do
    test "lists the four CLDR categories" do
      assert MinimalPairs.categories() == [:cardinal, :ordinal, :case, :gender]
    end
  end
end
