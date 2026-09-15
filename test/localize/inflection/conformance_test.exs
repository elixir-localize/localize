defmodule Localize.Inflection.ConformanceTest do
  use ExUnit.Case, async: false

  alias Localize.Inflection.Conformance

  # Locales whose synthesizer wave has not landed yet; their suites
  # run but are excluded from `mix test` (run with
  # `mix test --include pending` to see progress).
  @pending ~w()

  # One suite per fixture whether or not its inflection data is on disk.
  # Filtering on the data here made a suite without data vanish from the
  # run instead of failing; test_helper.exs downloads it from the CDN.
  suites = Conformance.suites()
  @suite_count length(suites)

  test "upstream inflection conformance fixtures are present" do
    assert @suite_count > 0, "no inflection conformance fixtures match #{Conformance.fixtures()}"
  end

  for {locale, path} <- suites do
    if locale in @pending do
      @tag :pending
    end

    test "upstream #{locale} inflection conformance suite" do
      case Localize.Inflection.Locale.resolve(unquote(locale)) do
        {:ok, _data_locale} -> :ok
        {:error, exception} -> flunk(Exception.message(exception))
      end

      locale = String.to_atom(unquote(locale))
      {passed, failures} = Conformance.run_file(locale, unquote(path))

      for {index, test_case, description} <- failures do
        IO.puts(
          "FAIL #{locale} ##{index} source=#{inspect(test_case.source)} " <>
            "constraints=#{inspect(test_case.constraints)} " <>
            "initial=#{inspect(test_case.initial)}: " <> description
        )
      end

      total = passed + length(failures)
      IO.puts("#{locale} conformance: #{passed}/#{total} passed")
      assert failures == []
    end
  end
end
