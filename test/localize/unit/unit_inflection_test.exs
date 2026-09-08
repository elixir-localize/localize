defmodule Localize.Unit.InflectionTest do
  use ExUnit.Case, async: false

  # The `:inflect` option: engine-backed grammatical-case fallback
  # for unit patterns the CLDR data does not provide. Requires the
  # generated inflection data (provisioned in CI alongside the
  # conformance suites).

  defp format!(value, unit, options) do
    {:ok, formatted} = Localize.Unit.to_string(Localize.Unit.new!(value, unit), options)
    formatted
  end

  describe "golden invariance with :inflect off" do
    test "omitting :inflect and inflect: false are identical" do
      for locale <- [:ru, :de, :fi, :pl, :uk, :en],
          grammatical_case <- [:nominative, :genitive, :dative, :instrumental, :prepositional],
          value <- [1, 2, 5, 21] do
        options = [locale: locale, grammatical_case: grammatical_case]
        without = Localize.Unit.to_string(Localize.Unit.new!(value, "kilometer"), options)

        with_false =
          Localize.Unit.to_string(
            Localize.Unit.new!(value, "kilometer"),
            options ++ [inflect: false]
          )

        assert without == with_false
      end
    end

    test "existing outputs are unchanged" do
      assert format!(2, "kilometer", locale: :ru, grammatical_case: :instrumental) ==
               "2 километрами"

      assert format!(2, "kilometer", locale: :de, grammatical_case: :dative) == "2 Kilometern"
      assert format!(3, "kilometer", locale: :fi) == "3 kilometriä"

      assert format!(5, "kilometer", locale: :ru, grammatical_case: :prepositional) ==
               "5 километрах"
    end
  end

  describe "engine fallback for cases absent from CLDR data" do
    test "russian prepositional (absent from the case-keyed data)" do
      options = [locale: :ru, grammatical_case: :prepositional, inflect: :safe]

      assert format!(1, "kilometer", options) == "1 километре"
      assert format!(2, "kilometer", options) == "2 километрах"
      assert format!(5, "kilometer", options) == "5 километрах"
    end

    test "ukrainian instrumental for a unit without the case key" do
      assert format!(5, "hour", locale: :uk, grammatical_case: :instrumental, inflect: :safe) ==
               "5 годинами"
    end

    test "turkish dative through rule-based suffixing" do
      assert format!(2, "kilometer", locale: :tr, grammatical_case: :dative, inflect: :safe) ==
               "2 kilometreye"
    end

    test "finnish inessive inflects only under :always (compound lemma)" do
      safe = [locale: :fi, grammatical_case: :inessive, inflect: :safe]
      always = [locale: :fi, grammatical_case: :inessive, inflect: :always]

      assert format!(3, "kilometer", safe) == "3 kilometriä"
      assert format!(3, "kilometer", always) == "3 kilometrissä"
    end
  end

  describe "CLDR patterns stay authoritative" do
    test "a case present in the data is never re-inflected" do
      for mode <- [:safe, :always] do
        assert format!(2, "kilometer",
                 locale: :ru,
                 grammatical_case: :instrumental,
                 inflect: mode
               ) == "2 километрами"

        assert format!(2, "kilometer", locale: :de, grammatical_case: :dative, inflect: mode) ==
                 "2 Kilometern"
      end
    end
  end

  describe ":safe never emits unattested forms" do
    test "dictionary-unknown polish nouns fall back unchanged" do
      for unit <- ["fathom", "furlong", "light-year"] do
        off = format!(3, unit, locale: :pl, grammatical_case: :genitive)
        safe = format!(3, unit, locale: :pl, grammatical_case: :genitive, inflect: :safe)

        assert safe == off
      end
    end
  end

  describe "grammatical_gender/2" do
    test "the CLDR gender field is authoritative" do
      assert Localize.Unit.grammatical_gender(Localize.Unit.new!(1, "kilometer"), locale: :de) ==
               {:ok, :masculine}

      assert Localize.Unit.grammatical_gender(Localize.Unit.new!(1, "second"), locale: :ru) ==
               {:ok, :feminine}
    end

    test "the engine derives gender when the data has none" do
      assert Localize.Unit.grammatical_gender(Localize.Unit.new!(1, "hour"), locale: :es) ==
               {:ok, :feminine}

      assert Localize.Unit.grammatical_gender(Localize.Unit.new!(1, "hour"), locale: :it) ==
               {:ok, :feminine}
    end

    test "genderless locales and unknown nouns are structured errors" do
      assert {:error, %Localize.ItemNotFoundError{}} =
               Localize.Unit.grammatical_gender(Localize.Unit.new!(1, "kilometer"), locale: :en)

      assert {:error, %Localize.ItemNotFoundError{}} =
               Localize.Unit.grammatical_gender(Localize.Unit.new!(1, "fathom"), locale: :pl)
    end
  end

  describe "custom units" do
    setup do
      on_exit(fn -> Localize.Unit.CustomRegistry.clear() end)
    end

    test "case-keyed display patterns resolve by :grammatical_case" do
      :ok =
        Localize.Unit.CustomRegistry.register("verst", %{
          base_unit: "meter",
          factor: 1066.8,
          category: "length",
          display: %{
            ru: %{
              long: %{
                nominative: %{one: "{0} верста", few: "{0} версты", other: "{0} версты"},
                dative: %{one: "{0} версте", few: "{0} верстам", other: "{0} версты"}
              }
            }
          }
        })

      unit = Localize.Unit.new!(2, "verst")

      assert Localize.Unit.to_string(unit, locale: :ru) == {:ok, "2 версты"}

      assert Localize.Unit.to_string(unit, locale: :ru, grammatical_case: :dative) ==
               {:ok, "2 верстам"}
    end

    test "the engine inflects a flat display pattern under :inflect" do
      :ok =
        Localize.Unit.CustomRegistry.register("arshin", %{
          base_unit: "meter",
          factor: 0.7112,
          category: "length",
          display: %{
            ru: %{
              long: %{one: "{0} аршин", few: "{0} аршина", many: "{0} аршин", other: "{0} аршина"}
            }
          }
        })

      unit = Localize.Unit.new!(2, "arshin")

      assert Localize.Unit.to_string(unit, locale: :ru, grammatical_case: :dative) ==
               {:ok, "2 аршина"}

      assert Localize.Unit.to_string(unit,
               locale: :ru,
               grammatical_case: :dative,
               inflect: :safe
             ) == {:ok, "2 аршинам"}
    end
  end

  describe "MF2 :unit grammar options" do
    test "grammaticalCase maps onto the CLDR case-keyed patterns" do
      assert Localize.Message.format(
               "{$d :unit unit=kilometer grammaticalCase=instrumental}",
               %{d: 2},
               locale: :ru
             ) == {:ok, "2 километрами"}
    end

    test "inflect enables the engine fallback" do
      assert Localize.Message.format(
               "{$d :unit unit=kilometer grammaticalCase=prepositional inflect=safe}",
               %{d: 2},
               locale: :ru
             ) == {:ok, "2 километрах"}
    end

    test "unknown grammaticalCase values are ignored" do
      assert Localize.Message.format(
               "{$d :unit unit=kilometer grammaticalCase=bogus}",
               %{d: 2},
               locale: :ru
             ) == {:ok, "2 километра"}
    end

    test "options apply to Localize.Unit operands too" do
      {:ok, unit} = Localize.Unit.new(2, "kilometer")

      assert Localize.Message.format("{$u :unit grammaticalCase=instrumental}", %{u: unit},
               locale: :ru
             ) == {:ok, "2 километрами"}
    end
  end

  describe "option validation and parts" do
    test "an invalid :inflect value is a structured error" do
      assert {:error, %Localize.InvalidValueError{value: :yes}} =
               Localize.Unit.to_string(
                 Localize.Unit.new!(2, "kilometer"),
                 locale: :ru,
                 grammatical_case: :prepositional,
                 inflect: :yes
               )
    end

    test "to_parts applies the same fallback" do
      assert {:ok,
              [
                %{type: :integer, value: "2"},
                %{type: :literal, value: " "},
                %{type: :unit, value: "километрах"}
              ]} =
               Localize.Unit.to_parts(
                 Localize.Unit.new!(2, "kilometer"),
                 locale: :ru,
                 grammatical_case: :prepositional,
                 inflect: :safe
               )
    end
  end
end
