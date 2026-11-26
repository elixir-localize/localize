defmodule Localize.Number.Rbnf.ResolverTest do
  # Not async: the atom-count test needs no other test making atoms meanwhile.
  use ExUnit.Case, async: false

  alias Localize.Number.Rbnf
  alias Localize.Number.Rbnf.{Resolver, RuleSetName}

  describe "a family with an unmarked rule set" do
    test "takes it when no grammatical option is given, as CLDR intends" do
      # CLDR's Russian `digits-ordinal` writes the digits alone (issue 72).
      assert Rbnf.to_string(3, :ordinal, locale: :ru) == {:ok, "3"}
      assert Rbnf.to_string(3, :ordinal, locale: :de) == {:ok, "dritte"}
      assert Rbnf.to_string(3, :spellout, locale: :ru) == {:ok, "три"}
    end

    test "takes the gendered rule set a gender asks for" do
      assert Rbnf.to_string(3, :ordinal, locale: :ru, grammatical_gender: :masculine) ==
               {:ok, "3-й"}

      assert Rbnf.to_string(3, :ordinal, locale: :ru, grammatical_gender: :feminine) ==
               {:ok, "3-я"}

      assert Rbnf.to_string(3, :ordinal, locale: :ru, grammatical_gender: :neuter) ==
               {:ok, "3-е"}
    end

    test "takes gender and case together" do
      assert Rbnf.to_string(3, :ordinal,
               locale: :ru,
               grammatical_gender: :masculine,
               grammatical_case: :genitive
             ) == {:ok, "3-го"}

      assert Rbnf.to_string(3, :ordinal,
               locale: :de,
               grammatical_gender: :feminine,
               grammatical_case: :dative
             ) == {:ok, "dritter"}
    end

    test "chooses the masculine for a case given without a gender" do
      assert Rbnf.to_string(3, :ordinal, locale: :ru, grammatical_case: :genitive) ==
               {:ok, "3-го"}
    end

    test "ignores a feature the family does not vary on" do
      assert Rbnf.to_string(3, :ordinal, locale: :en, grammatical_gender: :feminine) ==
               {:ok, "3rd"}

      assert Rbnf.to_string(3, :ordinal, locale: :sv, grammatical_gender: :common) ==
               {:ok, "3:e"}
    end
  end

  describe "a family with no unmarked rule set" do
    test "chooses the masculine nominative, not the first name alphabetically" do
      assert Rbnf.to_string(3, :ordinal, locale: :pl) == {:ok, "trzeci"}
      assert Rbnf.to_string(3, :ordinal, locale: :hr) == {:ok, "treći"}
      assert Rbnf.to_string(3, :ordinal, locale: :"pt-PT") == {:ok, "terceiro"}
    end

    test "resolves a family's own name" do
      assert Rbnf.to_string(3, :spellout_ordinal, locale: :ru) == {:ok, "третий"}
      assert Rbnf.to_string(3, "spellout-cardinal", locale: :ru) == {:ok, "три"}

      assert Rbnf.to_string(1, :spellout_cardinal, locale: :ru, grammatical_gender: :feminine) ==
               {:ok, "одна"}
    end

    test "reads CLDR's animacy genders" do
      assert Rbnf.to_string(3, :ordinal, locale: :pl, grammatical_gender: :inanimate) ==
               {:ok, "trzeci"}

      assert Rbnf.to_string(3, :ordinal,
               locale: :pl,
               grammatical_gender: :animate,
               grammatical_case: :accusative
             ) == {:ok, "trzeciego"}

      assert Rbnf.to_string(3, :ordinal,
               locale: :pl,
               grammatical_gender: :inanimate,
               grammatical_case: :accusative
             ) == {:ok, "trzeci"}

      assert Rbnf.to_string(3, :ordinal,
               locale: :pl,
               grammatical_gender: :personal,
               grammatical_number: :plural
             ) == {:ok, "trzeci"}
    end
  end

  describe "option values" do
    test "are atoms or their names" do
      assert Rbnf.to_string(3, :ordinal, locale: :ru, grammatical_gender: "feminine") ==
               {:ok, "3-я"}

      assert Rbnf.to_string(3, :ordinal, locale: :ru, grammatical_case: "genitive") ==
               {:ok, "3-го"}
    end

    test "nil is an option not given" do
      assert Rbnf.to_string(3, :ordinal, locale: :ru, grammatical_gender: nil) == {:ok, "3"}
    end

    test "a value that is not one of the option's is an error" do
      for value <- ["bogus", "", :"", :plural, 3, %{}, [], "Genitive"] do
        assert {:error, %Localize.InvalidValueError{expected: :grammatical_case}} =
                 Rbnf.to_string(3, :ordinal, locale: :pl, grammatical_case: value)
      end
    end

    test "a value the locale does not have is an error naming the ones it has" do
      assert {:error, %Localize.InvalidValueError{} = error} =
               Rbnf.to_string(3, :ordinal, locale: :pl, grammatical_case: :prepositional)

      assert error.value == :prepositional
      assert error.expected == :grammatical_case
      assert :locative in error.allowed_values
      assert :nominative in error.allowed_values
    end

    test "with a name that is not a family is an error" do
      assert {:error, %Localize.InvalidValueError{}} =
               Rbnf.to_string(3, :roman_upper, locale: :pl, grammatical_case: :genitive)

      assert {:error, %Localize.InvalidValueError{}} =
               Rbnf.to_string(3, :digits_ordinal_masculine,
                 locale: :ru,
                 grammatical_case: :genitive
               )
    end

    test "make no atom" do
      strings = for index <- 1..1_000, do: "resolver-test-#{index}"
      before = :erlang.system_info(:atom_count)

      for string <- strings do
        assert {:error, _exception} =
                 Rbnf.to_string(3, :ordinal, locale: :ru, grammatical_gender: string)

        assert {:error, _exception} =
                 Rbnf.to_string(3, "spellout-ordinal-" <> string, locale: :ru)
      end

      assert :erlang.system_info(:atom_count) == before
    end
  end

  describe "through Localize.Number.to_string/2" do
    test "formats the gendered ordinal issue 72 asked for" do
      assert Localize.Number.to_string(3, format: :ordinal, locale: :ru) == {:ok, "3"}

      assert Localize.Number.to_string(3,
               format: :ordinal,
               locale: :ru,
               grammatical_gender: :masculine
             ) == {:ok, "3-й"}

      assert Localize.Number.to_string(3,
               format: :ordinal,
               locale: :ru,
               grammatical_gender: "masculine",
               grammatical_case: "genitive"
             ) == {:ok, "3-го"}
    end

    test "passes number and definiteness too" do
      assert Localize.Number.to_string(3,
               format: :ordinal,
               locale: :pl,
               grammatical_gender: :personal,
               grammatical_number: :plural
             ) == {:ok, "trzeci"}

      assert {:error, %Localize.InvalidValueError{expected: :grammatical_definiteness}} =
               Localize.Number.to_string(3,
                 format: :ordinal,
                 locale: :ru,
                 grammatical_definiteness: :bogus
               )
    end

    test "validates the options with a format that is not a family, and ignores them" do
      assert Localize.Number.to_string(1234.5, locale: :de, grammatical_case: :dative) ==
               {:ok, "1.234,5"}

      assert {:error, %Localize.InvalidValueError{expected: :grammatical_case}} =
               Localize.Number.to_string(1234.5, locale: :de, grammatical_case: "bogus")
    end

    test "a validated options struct holds each option as its atom" do
      {:ok, options} =
        Localize.Number.Format.Options.validate_options(0,
          format: :ordinal,
          locale: :ru,
          grammatical_gender: "feminine"
        )

      assert options.grammatical_gender == :feminine
      assert options.grammatical_case == nil
      assert Localize.Number.to_string(3, options) == {:ok, "3-я"}
    end
  end

  describe "every rule set CLDR names by its features" do
    # For each rule set whose name reads as a family and features, in every
    # RBNF locale, asking the family for those features chooses that rule
    # set: no two are confused, and none is out of reach.
    test "is the one its own features resolve to" do
      for locale <- Localize.SupplementalData.rbnf_locales(),
          names = public_names(locale),
          name <- names,
          {:ok, family, features} <- [RuleSetName.parse(name)] do
        assert Resolver.resolve(family, features, names, locale) == {:ok, name},
               "#{locale}: #{family} with #{inspect(features)} did not resolve to #{name}"
      end
    end

    test "formats as its own name does" do
      for locale <- Localize.SupplementalData.rbnf_locales(),
          name <- public_names(locale),
          {:ok, family, features} <- [RuleSetName.parse(name)] do
        options = [{:locale, locale} | Map.to_list(features)]

        assert Rbnf.to_string(21, family, options) == Rbnf.to_string(21, name, locale: locale),
               "#{locale}: #{family} with #{inspect(features)}"
      end
    end
  end

  defp public_names(locale) do
    {:ok, names} = Rbnf.rule_names_for_locale(locale)
    Enum.map(names, &String.replace(&1, "_", "-"))
  end
end
