defmodule Localize.Locale.PersistentTermTest do
  @moduledoc """
  Covers persistent-term locale provider lookup behaviour.

  These tests use generated locale data loaded through the normal locale
  loading path. They do not cover cache freshness, runtime downloads, or
  alternative locale providers.
  """

  use ExUnit.Case, async: true

  alias Localize.Locale

  @parent_only_key [:dates, :calendars, :gregorian, :available_formats, :yMMdd]
  @grandparent_only_key [:subdivisions, :twcyi]
  @locale_specific_key [:territories, :TC, :standard]
  @missing_key [:localize_test, :missing_key]

  describe "get/3" do
    test "does not search parent locales by default" do
      assert {:error, %Localize.ItemNotFoundError{locale: :"en-AU", keys: @parent_only_key}} =
               Locale.get(:"en-AU", @parent_only_key)
    end

    test "does not search parent locales when fallback is false" do
      assert {:error, %Localize.ItemNotFoundError{locale: :"en-AU", keys: @parent_only_key}} =
               Locale.get(:"en-AU", @parent_only_key, fallback: false)
    end

    test "searches the immediate parent locale when fallback is enabled" do
      assert {:ok, "dd/MM/y"} =
               Locale.get(:"en-AU", @parent_only_key, fallback: true)
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

  describe "nest_unit_grammar_cases/1" do
    alias Localize.Locale.Provider.PersistentTerm

    test "nests flat grammar-case keys from pre-fix published locale data" do
      # Locale data published before all sixteen CLDR unit grammar
      # cases were normalized carries flat keys like
      # :prepositional_count_one; store/2 must nest them at load time.
      flat_data = %{
        units: %{
          long: %{
            length: %{
              kilometer: %{
                nominative: %{one: [0, " километр"], other: [0, " километра"]},
                prepositional_count_one: [0, " километре"],
                prepositional_count_other: [0, " километрах"],
                display_name: "километры"
              }
            }
          }
        }
      }

      %{units: units} = PersistentTerm.nest_unit_grammar_cases(flat_data)
      kilometer = units.long.length.kilometer

      assert kilometer.prepositional == %{
               one: [0, " километре"],
               other: [0, " километрах"]
             }

      refute Map.has_key?(kilometer, :prepositional_count_one)
      refute Map.has_key?(kilometer, :prepositional_count_other)
      assert kilometer.nominative == %{one: [0, " километр"], other: [0, " километра"]}
      assert kilometer.display_name == "километры"
    end

    test "already-nested locale data passes through unchanged" do
      nested_data = %{
        units: %{
          long: %{
            length: %{
              kilometer: %{
                nominative: %{one: [0, " kilometri"]},
                partitive: %{one: [0, " kilometriä"]}
              }
            }
          }
        }
      }

      assert PersistentTerm.nest_unit_grammar_cases(nested_data) == nested_data
    end

    test "locale data without a units key passes through unchanged" do
      assert PersistentTerm.nest_unit_grammar_cases(%{languages: %{}}) == %{languages: %{}}
    end
  end
end
