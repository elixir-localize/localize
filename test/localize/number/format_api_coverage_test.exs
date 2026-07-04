defmodule Localize.Number.FormatApiCoverageTest do
  use ExUnit.Case, async: true

  alias Localize.Number.Format

  describe "Access behaviour on the Format struct" do
    test "fetch/2 reads a key" do
      {:ok, formats} = Format.formats_for("en")
      assert formats[:standard] == "#,##0.###"
    end

    test "get_and_update/3 returns the current value and updates" do
      {:ok, formats} = Format.formats_for("en")

      {current, updated} =
        Access.get_and_update(formats, :standard, fn value -> {value, "0"} end)

      assert current == "#,##0.###"
      assert updated.standard == "0"
    end

    test "get_and_update/3 supports :pop" do
      {:ok, formats} = Format.formats_for("en")
      {current, updated} = Access.get_and_update(formats, :standard, fn _value -> :pop end)

      assert current == "#,##0.###"
      refute Map.has_key?(updated, :standard)
    end

    test "pop/2 removes a key" do
      {:ok, formats} = Format.formats_for("en")
      {current, updated} = Access.pop(formats, :standard)

      assert current == "#,##0.###"
      refute Map.has_key?(updated, :standard)
    end
  end

  describe "formats_for/2 error paths" do
    test "an unknown number system returns an error" do
      assert {:error, %Localize.UnknownNumberSystemError{number_system: :bogus}} =
               Format.formats_for("en", :bogus)
    end
  end

  describe "bang variants" do
    test "formats_for!/2 returns the struct directly" do
      formats = Format.formats_for!("en")
      assert formats.standard == "#,##0.###"
    end

    test "formats_for!/2 raises on an unknown number system" do
      assert_raise Localize.UnknownNumberSystemError, fn ->
        Format.formats_for!("en", :bogus)
      end
    end

    test "all_formats_for!/1 raises on an invalid locale" do
      assert_raise Localize.InvalidLocaleError, fn ->
        Format.all_formats_for!("xx")
      end
    end

    test "minimum_grouping_digits_for!/1 returns the digits directly" do
      assert Format.minimum_grouping_digits_for!("en") == 1
    end

    test "minimum_grouping_digits_for!/1 raises on an invalid locale" do
      assert_raise Localize.InvalidLocaleError, fn ->
        Format.minimum_grouping_digits_for!("xx")
      end
    end

    test "default_grouping_for!/1 returns the grouping directly" do
      assert Format.default_grouping_for!("en") ==
               %{integer: %{first: 3, rest: 3}, fraction: %{first: 0, rest: 0}}
    end

    test "default_grouping_for!/1 raises on an invalid locale" do
      assert_raise Localize.InvalidLocaleError, fn ->
        Format.default_grouping_for!("xx")
      end
    end
  end

  describe "grouping extraction" do
    test "Indian-style grouping has a different first and rest size" do
      assert Format.default_grouping_for!("hi") ==
               %{integer: %{first: 3, rest: 2}, fraction: %{first: 0, rest: 0}}

      assert Format.default_grouping_for!("en-IN") ==
               %{integer: %{first: 3, rest: 2}, fraction: %{first: 0, rest: 0}}
    end
  end
end
