defmodule Localize.Unit.LocalizeTest do
  use ExUnit.Case, async: true

  # Parity tests ported from cldr_units (test/cldr_units_test.exs).
  # The originals call `Cldr.Unit.localize/3` and `Cldr.Unit.Format.to_string/3`;
  # this file ports them with three mechanical adaptations:
  #
  #   1. Module name: Cldr.Unit -> Localize.Unit, Cldr.Unit.Format -> Localize.Unit.
  #   2. Backend argument removed (Localize has no per-app backend module).
  #   3. Constructor signature: `Cldr.Unit.new!(:foot, 23, usage: :person_height)`
  #      -> `Localize.Unit.new!(23, "foot", usage: "person-height")` (value-first
  #      arg order, string unit names, hyphenated string usages — matching the
  #      Localize struct's storage shape).
  #
  # `Localize.Unit.localize/2` returns `{:ok, list}` where cldr_units returns
  # `list` directly; the assertion shape is updated accordingly. Decimal
  # values are preserved end-to-end (Conversion + decompose both run in
  # Decimal arithmetic when the input value is a Decimal). The trailing
  # digits of the decimal-unit assertion differ slightly from cldr_units'
  # because the conversion factors are stored as floats and coerced to
  # Decimal at the boundary via `Decimal.from_float/1`; cldr_units stores
  # rationals and avoids that quantisation.

  alias Localize.Unit

  describe "to_string/2 with a list (cldr_units parity)" do
    test "formatting a list" do
      list = [Unit.new!(23, "foot"), Unit.new!(5, "inch")]
      assert Unit.to_string(list) == {:ok, "23 feet and 5 inches"}
    end
  end

  describe "localize/2 (cldr_units parity)" do
    test "localize a unit" do
      unit = Unit.new!(100, "meter")

      assert Unit.localize(unit, usage: :person, territory: :US) ==
               {:ok, [Unit.new!(3937.007874015748, "inch", usage: "person")]}

      assert Unit.localize(unit, usage: :person_height, territory: :US) ==
               {:ok,
                [
                  Unit.new!(328, "foot", usage: "person-height"),
                  Unit.new!(1.0078740157478023, "inch", usage: "person-height")
                ]}
    end

    test "localize a decimal unit" do
      u = Unit.new!(Decimal.new(20), "meter")

      assert Unit.localize(u, territory: :US) ==
               {:ok, [Unit.new!(Decimal.new("65.61679790026246719160104986876640"), "foot")]}
    end

    test "localization with current process locales" do
      assert {:ok, _} = Unit.localize(Unit.new!(2, "meter", usage: "person-height"))
      assert {:ok, _} = Unit.localize(Unit.new!(2, "meter", usage: "person-height"), locale: "fr")
    end

    test "format_options from CLDR's preference skeleton flow through to_string" do
      # CLDR's road preferences for region 001 ship a `skeleton="precision-increment/50"`
      # for distances of 300m+. `localize/2` stamps that as `[round_nearest: 50]`
      # on the decomposed unit, and `to_string/2` honours it via the number
      # formatter — so 311m road comes out as "300 meters".
      unit = Unit.new!(311, "meter")
      {:ok, [meter]} = Unit.localize(unit, usage: :road, territory: :"001")
      assert meter.format_options == [round_nearest: 50]
      assert {:ok, "300 meters"} = Unit.to_string([meter], locale: "en")
    end

    test "preference without a skeleton leaves format_options empty" do
      # CLDR's person-height preferences carry no skeleton; output is unrounded.
      unit = Unit.new!(1.83, "meter")
      {:ok, parts} = Unit.localize(unit, usage: :person_height, territory: :US)
      assert Enum.all?(parts, &(&1.format_options == []))
      assert {:ok, "6 feet and 0.047 inches"} = Unit.to_string(parts, locale: "en")
    end

    # Behavioural divergence from cldr_units: cldr_units validates the usage
    # against the unit's category and raises Cldr.Unit.UnknownUsageError for
    # unknown values. Localize.Unit.Preference.preferred_units/2 walks the
    # usage chain and silently falls back to the :default preferences for the
    # category when no part of the chain matches. So `:unknown` for a length
    # unit resolves to the default length preference for the territory rather
    # than erroring.
    test "unknown usage falls through to default (vs cldr_units which raises)" do
      unit = Unit.new!(100, "meter")
      assert {:ok, [single]} = Unit.localize(unit, usage: :unknown, territory: :US)
      # Default length preference for :US at this magnitude is :foot.
      assert single.name == "foot"
    end
  end

  # `preferred_units/2` reports units as underscored atoms (`:cubic_inch`)
  # while the parser reads hyphenated CLDR identifiers (`"cubic-inch"`), so
  # `localize/2` has to convert between the two. Every test above uses a
  # length unit, whose preferences are all single words and so unaffected by
  # getting that wrong — which is how it went unnoticed.
  describe "localize/2 with multi-word preferred units" do
    test "a preference spelled with a hyphen resolves" do
      {:ok, litres} = Unit.new(2, "liter")

      assert {:ok, [cubic_inch]} = Unit.localize(litres, locale: "en-US")
      assert cubic_inch.name == "cubic-inch"
      assert_in_delta cubic_inch.value, 122.047488, 1.0e-6
    end

    test "across the categories whose default preference is multi-word" do
      cases = [
        {100, "kilometer-per-hour", [usage: :default, territory: :US], "mile-per-hour",
         62.1371192},
        {5000, "square-meter", [usage: :default, territory: :US], "acre", 1.2355269},
        # Below a cup, so the US fluid ladder falls through to fluid ounces.
        {0.1, "liter", [usage: :fluid, territory: :US], "fluid-ounce", 3.3814023},
        {1000, "pascal", [usage: :default, territory: :US], "pound-force-per-square-inch",
         0.1450377},
        {30, "year-person", [usage: :person_age, territory: :US], "year-person", 30.0}
      ]

      for {value, name, options, expected_name, expected_value} <- cases do
        assert {:ok, [part]} = Unit.localize(Unit.new!(value, name), options),
               "#{value} #{name} #{inspect(options)} did not localize"

        assert part.name == expected_name
        assert_in_delta part.value, expected_value, abs(expected_value) * 1.0e-6
      end
    end

    test "every preference CLDR ships resolves for every territory" do
      # A sweep rather than a list: 35 of the 90 preferred units are
      # multi-word, spread over 19 category/usage pairs, and naming them
      # individually would go stale on the next CLDR release.
      territories = [:US, :GB, :DE, :JP, :SE, :"001"]

      failures =
        for preference <- Localize.Unit.Data.unit_preferences(),
            territory <- territories,
            source = representative_unit(preference),
            source != nil,
            usage = String.to_atom(String.replace(preference.usage, "-", "_")),
            result = Unit.localize(Unit.new!(2, source), usage: usage, territory: territory),
            not match?({:ok, _units}, result),
            do: {preference.category, preference.usage, territory, result}

      assert failures == []
    end
  end

  # A unit in the right category to exercise this preference: the first unit
  # the preference itself names, which is convertible to the rest by
  # construction.
  defp representative_unit(preference) do
    case preference.preferences do
      [%{unit: unit} | _rest] -> unit |> String.split("-and-") |> List.first()
      [] -> nil
    end
  end
end
