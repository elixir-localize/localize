defmodule Localize.Number.RbnfDataTest do
  @moduledoc """
  Tests RBNF formatting against expected output from ICU reference data.
  Test data is in test/support/rbnf/<locale>/rbnf_test.json.
  """

  use ExUnit.Case, async: true

  alias Localize.Number.Rbnf

  @test_locales ["en", "de", "es", "fr"]
  @support_dir Path.join([__DIR__, "..", "..", "support", "rbnf"])

  for locale <- @test_locales do
    test_file = Path.join([@support_dir, locale, "rbnf_test.json"])

    if File.exists?(test_file) do
      test_data =
        test_file
        |> File.read!()
        |> :json.decode()

      locale_atom = String.to_atom(locale)

      for {group_name, rule_sets} <- test_data,
          {rule_set_name, test_cases} <- rule_sets do
        # Normalize rule name: "spellout-cardinal" → "spellout_cardinal"
        rule_name = String.replace(rule_set_name, "-", "_")

        # Take a representative sample to keep test time reasonable
        sampled_cases =
          test_cases
          |> Enum.to_list()
          |> Enum.take_every(max(div(Enum.count(test_cases), 20), 1))
          |> Enum.take(20)

        for {number_str, expected} <- sampled_cases do
          test "#{locale} #{group_name}/#{rule_set_name} #{number_str}" do
            locale = unquote(locale_atom)
            rule = unquote(rule_name)
            number = String.to_integer(unquote(number_str))
            expected = unquote(expected)

            case Rbnf.to_string(number, rule, locale: locale) do
              {:ok, result} ->
                assert result == expected,
                       "#{locale} #{rule}(#{number}): got #{inspect(result)}, expected #{inspect(expected)}"

              {:error, reason} ->
                flunk("#{locale} #{rule}(#{number}): error #{inspect(reason)}")
            end
          end
        end
      end
    end
  end
end
