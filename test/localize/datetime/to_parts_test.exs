defmodule Localize.DateTime.ToPartsTest do
  use ExUnit.Case, async: true

  @naive ~N[2017-07-10 14:30:05]

  describe "Date.to_parts/2" do
    test "medium date decomposes" do
      assert {:ok,
              [
                %{type: :month, value: "Jul"},
                %{type: :literal, value: " "},
                %{type: :day, value: "10"},
                %{type: :literal, value: ", "},
                %{type: :year, value: "2017"}
              ]} = Localize.Date.to_parts(~D[2017-07-10], locale: :en)
    end

    test "full date includes the weekday" do
      {:ok, parts} = Localize.Date.to_parts(~D[2017-07-10], locale: :en, format: :full)
      assert %{type: :weekday, value: "Monday"} in parts
    end

    test "parts concatenate to the string across formats and locales" do
      for locale <- [:en, :de, :fr], format <- [:short, :medium, :long, :full] do
        {:ok, parts} = Localize.Date.to_parts(~D[2017-07-10], locale: locale, format: format)
        {:ok, string} = Localize.Date.to_string(~D[2017-07-10], locale: locale, format: format)

        assert Enum.map_join(parts, & &1.value) == string
      end
    end

    test "partial date maps decompose" do
      {:ok, parts} = Localize.Date.to_parts(%{year: 2024, month: 6}, format: :yMMM, locale: :fr)
      assert Enum.map_join(parts, & &1.value) == "juin 2024"
    end
  end

  describe "Time.to_parts/2" do
    test "pattern fields are tagged" do
      assert {:ok,
              [
                %{type: :hour, value: "14"},
                %{type: :literal, value: ":"},
                %{type: :minute, value: "30"}
              ]} = Localize.Time.to_parts(~T[14:30:05], locale: :en, format: "HH:mm")
    end

    test "parts concatenate to the string" do
      {:ok, parts} = Localize.Time.to_parts(~T[14:30:05], locale: :en)
      {:ok, string} = Localize.Time.to_string(~T[14:30:05], locale: :en)

      assert Enum.map_join(parts, & &1.value) == string
    end
  end

  describe "DateTime.to_parts/2" do
    test "standard formats decompose through the wrapper" do
      for format <- [:short, :medium, :long, :full] do
        {:ok, parts} = Localize.DateTime.to_parts(@naive, locale: :en, format: format)
        {:ok, string} = Localize.DateTime.to_string(@naive, locale: :en, format: format)

        assert Enum.map_join(parts, & &1.value) == string
      end
    end

    test "skeleton formats decompose" do
      assert {:ok,
              [
                %{type: :month, value: "7"},
                %{type: :literal, value: "/"},
                %{type: :day, value: "10"},
                %{type: :literal, value: "/"},
                %{type: :year, value: "2017"},
                %{type: :literal, value: ", "},
                %{type: :hour, value: "14"},
                %{type: :literal, value: ":"},
                %{type: :minute, value: "30"}
              ]} = Localize.DateTime.to_parts(@naive, locale: :en, format: :yMdHm)
    end

    test "explicit pattern strings decompose" do
      {:ok, parts} = Localize.DateTime.to_parts(@naive, locale: :en, format: "y-MM-dd HH:mm")
      assert Enum.map_join(parts, & &1.value) == "2017-07-10 14:30"
    end

    test "zoned datetimes tag the zone name" do
      utc = DateTime.from_naive!(@naive, "Etc/UTC")
      {:ok, parts} = Localize.DateTime.to_parts(utc, locale: :en, format: :full)
      assert Enum.any?(parts, &(&1.type == :time_zone_name))
    end

    test "partial datetime maps compose date and time parts" do
      partial = %{year: 2025, month: 3, day: 15, hour: 14, minute: 30}
      {:ok, parts} = Localize.DateTime.to_parts(partial, locale: :en)
      {:ok, string} = Localize.DateTime.to_string(partial, locale: :en)

      assert Enum.map_join(parts, & &1.value) == string
    end

    test "fractional-second skeletons tag the fraction" do
      {:ok, parts} =
        Localize.Time.to_parts(~T[09:30:12.345], locale: :en, format: :hmsSS)

      assert %{type: :fractional_second, value: "34"} in parts
      assert %{type: :literal, value: "."} in parts
    end
  end
end
