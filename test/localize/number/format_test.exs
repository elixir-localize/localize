defmodule Localize.Number.FormatTest do
  use ExUnit.Case, async: true

  doctest Localize.Number.Format

  alias Localize.Number.Format

  describe "all_formats_for/1" do
    test "returns formats keyed by number system" do
      {:ok, formats} = Format.all_formats_for(:en)
      assert is_map(formats)
      assert Map.has_key?(formats, :latn)
      assert %Format{} = formats[:latn]
    end

    test "format struct has standard field" do
      {:ok, formats} = Format.all_formats_for(:en)
      latn = formats[:latn]
      assert is_binary(latn.standard)
    end
  end

  describe "formats_for/2" do
    test "returns formats for default number system" do
      {:ok, format} = Format.formats_for(:en, :default)
      assert %Format{} = format
      assert is_binary(format.standard)
    end

    test "returns formats for latn" do
      {:ok, format} = Format.formats_for(:en, :latn)
      assert %Format{} = format
    end
  end

  describe "minimum_grouping_digits_for/1" do
    test "returns minimum grouping digits for English" do
      {:ok, digits} = Format.minimum_grouping_digits_for(:en)
      assert is_integer(digits)
      assert digits >= 1
    end
  end

  describe "default_grouping_for/1" do
    test "returns grouping for English" do
      {:ok, grouping} = Format.default_grouping_for(:en)
      assert %{integer: %{first: 3, rest: 3}} = grouping
      assert %{fraction: %{first: 0, rest: 0}} = grouping
    end
  end

  describe "format_styles_for/2" do
    test "returns available format styles" do
      {:ok, styles} = Format.format_styles_for(:en, :latn)
      assert :standard in styles
      assert :currency in styles
      assert :percent in styles
    end
  end

  describe "format_system_types_for/1" do
    test "returns system types for a locale" do
      {:ok, types} = Format.format_system_types_for(:en)
      assert :default in types
      assert :native in types
    end
  end
end
