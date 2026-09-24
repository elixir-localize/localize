defmodule Localize.Locale.PersistentTermTest do
  @moduledoc """
  Covers persistent-term locale provider lookup behaviour.

  These tests use generated locale data loaded through the normal locale
  loading path. They do not cover cache freshness, runtime downloads, or
  alternative locale providers.
  """

  use ExUnit.Case, async: true

  alias Localize.Locale

  # pt names Brasília's short zone names; pt-PT, whose parent it is, does not.
  @parent_only_key [:dates, :time_zone_names, :metazone, :brasilia, :short, :standard]
  @grandparent_only_key [:subdivisions, :twcyi]
  @locale_specific_key [:territories, :TC, :standard]
  @missing_key [:localize_test, :missing_key]

  describe "get/3" do
    test "does not search parent locales by default" do
      assert {:error, %Localize.ItemNotFoundError{locale: :"pt-PT", keys: @parent_only_key}} =
               Locale.get(:"pt-PT", @parent_only_key)
    end

    test "does not search parent locales when fallback is false" do
      assert {:error, %Localize.ItemNotFoundError{locale: :"pt-PT", keys: @parent_only_key}} =
               Locale.get(:"pt-PT", @parent_only_key, fallback: false)
    end

    test "searches the immediate parent locale when fallback is enabled" do
      assert {:ok, "BRT"} =
               Locale.get(:"pt-PT", @parent_only_key, fallback: true)
    end

    test "uses the requested locale before searching parents" do
      assert {:ok, "Turks and Caicos Islands"} =
               Locale.get(:"en-AU", @locale_specific_key, fallback: true)
    end

    test "continues past the immediate parent locale" do
      assert {:ok, "Chiayi County"} =
               Locale.get(:"en-AU", @grandparent_only_key, fallback: true)
    end

    test "keeps not-found errors tied to the requested locale" do
      assert {:error, %Localize.ItemNotFoundError{locale: :"en-AU", keys: @missing_key}} =
               Locale.get(:"en-AU", @missing_key, fallback: true)
    end
  end
end
