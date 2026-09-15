defmodule Localize.Inflection.PronounConformanceTest do
  use ExUnit.Case, async: false

  alias Localize.Inflection.PronounConformance

  suites = PronounConformance.suites()
  @suite_count length(suites)

  test "upstream pronoun conformance fixtures are present" do
    assert @suite_count > 0,
           "no pronoun conformance fixtures match #{PronounConformance.fixtures()}"
  end

  for {locale, path} <- suites do
    test "upstream #{locale} pronoun conformance suite" do
      locale = String.to_atom(unquote(locale))
      {passed, failures} = PronounConformance.run_file(locale, unquote(path))

      for {index, test_case, description} <- failures do
        IO.puts(
          "FAIL pronoun #{locale} ##{index} source=#{inspect(test_case.source)} " <>
            "constraints=#{inspect(test_case.constraints)}: " <> description
        )
      end

      total = passed + length(failures)
      IO.puts("#{locale} pronoun conformance: #{passed}/#{total} passed")
      assert failures == []
    end
  end
end
