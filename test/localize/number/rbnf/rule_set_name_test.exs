defmodule Localize.Number.Rbnf.RuleSetNameTest do
  # Not async: the atom-count test needs no other test making atoms meanwhile.
  use ExUnit.Case, async: false

  alias Localize.Number.Rbnf.RuleSetName

  # Segments CLDR's rule-set names use for a style rather than a
  # grammatical feature. A name carrying one is reachable by its exact
  # name only.
  @style_segments ~w(
    financial verbose sinokorean native count attributive adjective connective
    standalone stressed alternate2 before consonant class o n r s m year days latn
  )

  describe "parse/1" do
    test "an unmarked family name has no features" do
      assert RuleSetName.parse(:digits_ordinal) == {:ok, :digits_ordinal, %{}}
      assert RuleSetName.parse("spellout-ordinal") == {:ok, :spellout_ordinal, %{}}
      assert RuleSetName.parse(:spellout_cardinal) == {:ok, :spellout_cardinal, %{}}
      assert RuleSetName.parse(:spellout_numbering) == {:ok, :spellout_numbering, %{}}
    end

    test "reads gender, case, number and definiteness" do
      assert RuleSetName.parse(:digits_ordinal_masculine_genitive) ==
               {:ok, :digits_ordinal,
                %{grammatical_gender: :masculine, grammatical_case: :genitive}}

      assert RuleSetName.parse("spellout-ordinal-plural-dative") ==
               {:ok, :spellout_ordinal, %{grammatical_number: :plural, grammatical_case: :dative}}

      assert RuleSetName.parse(:spellout_ordinal_neuter_accusative_definite) ==
               {:ok, :spellout_ordinal,
                %{
                  grammatical_gender: :neuter,
                  grammatical_case: :accusative,
                  grammatical_definiteness: :definite
                }}
    end

    test "reads masculine animacy as CLDR's gender, in either order" do
      expected =
        {:ok, :spellout_cardinal, %{grammatical_gender: :animate, grammatical_case: :accusative}}

      assert RuleSetName.parse("spellout-cardinal-masculine-animate-accusative") == expected
      assert RuleSetName.parse("spellout-cardinal-masculine-accusative-animate") == expected
      assert RuleSetName.parse("spellout-cardinal-animate-masculine-accusative") == expected
    end

    test "reads a bare animate, personal and Slovak human" do
      assert RuleSetName.parse(:spellout_ordinal_plural_animate_accusative) ==
               {:ok, :spellout_ordinal,
                %{
                  grammatical_gender: :animate,
                  grammatical_number: :plural,
                  grammatical_case: :accusative
                }}

      assert RuleSetName.parse(:spellout_ordinal_masculine_personal_plural) ==
               {:ok, :spellout_ordinal,
                %{grammatical_gender: :personal, grammatical_number: :plural}}

      assert RuleSetName.parse(:spellout_ordinal_masculine_human_plural) ==
               {:ok, :spellout_ordinal,
                %{grammatical_gender: :personal, grammatical_number: :plural}}
    end

    test "reads Swedish reale as common" do
      assert RuleSetName.parse(:digits_ordinal_reale) ==
               {:ok, :digits_ordinal, %{grammatical_gender: :common}}
    end

    test "a style segment makes the name unreadable" do
      for name <- [
            :spellout_ordinal_r,
            :spellout_cardinal_financial,
            :spellout_numbering_year,
            :spellout_numbering_verbose,
            "spellout-cardinal-masculine-personal-financial"
          ] do
        assert RuleSetName.parse(name) == :error
      end
    end

    test "two values for one feature make the name unreadable" do
      for name <- [
            "spellout-ordinal-feminine-masculine",
            "spellout-ordinal-feminine-animate",
            "spellout-ordinal-animate-personal",
            "spellout-ordinal-genitive-dative",
            "spellout-ordinal-plural-dual",
            "spellout-ordinal-masculine-masculine"
          ] do
        assert RuleSetName.parse(name) == :error
      end
    end

    test "a name outside the families, or garbage, is unreadable" do
      for name <- [:roman_upper, "spellout", "digits", "ordinal", "", :"", nil, 1, [], %{}] do
        assert RuleSetName.parse(name) == :error
      end
    end

    test "makes no atom from a name" do
      names = for index <- 1..2_000, do: "spellout-ordinal-masculine-x#{index}"
      before = :erlang.system_info(:atom_count)

      for name <- names do
        assert RuleSetName.parse(name) == :error
      end

      assert :erlang.system_info(:atom_count) == before
    end
  end

  describe "every CLDR rule-set name" do
    test "in a family either reads, or carries a style segment" do
      for locale <- Localize.SupplementalData.rbnf_locales(),
          name <- family_names(locale),
          RuleSetName.parse(name) == :error do
        segments = String.split(name, "_")

        assert Enum.any?(segments, &(&1 in @style_segments)),
               "#{locale}: #{name} neither reads nor carries a style segment"
      end
    end

    test "reads to features no other name in its locale and family has" do
      for locale <- Localize.SupplementalData.rbnf_locales() do
        read =
          for name <- family_names(locale),
              {:ok, family, features} <- [RuleSetName.parse(name)],
              do: {{family, features}, name}

        duplicates =
          read
          |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
          |> Enum.filter(&match?({_key, [_, _ | _]}, &1))

        assert duplicates == [], "#{locale}: #{inspect(duplicates)}"
      end
    end
  end

  defp family_names(locale) do
    {:ok, names} = Localize.Number.Rbnf.rule_names_for_locale(locale)

    Enum.filter(names, fn name ->
      String.starts_with?(name, ["digits_ordinal", "spellout_ordinal", "spellout_cardinal"]) or
        String.starts_with?(name, "spellout_numbering")
    end)
  end
end
