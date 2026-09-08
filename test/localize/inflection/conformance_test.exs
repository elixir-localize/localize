defmodule Localize.Inflection.ConformanceTest do
  use ExUnit.Case, async: false

  alias Localize.Inflection.Conformance

  # Locales whose synthesizer wave has not landed yet; their suites
  # run but are excluded from `mix test` (run with
  # `mix test --include pending` to see progress).
  @pending ~w()

  suites =
    "data/inflection/test/inflection_*.xml"
    |> Path.wildcard()
    |> Enum.map(fn path ->
      locale = path |> Path.basename(".xml") |> String.replace_prefix("inflection_", "")
      {locale, path}
    end)
    |> Enum.filter(fn {locale, _path} ->
      File.exists?("#{Localize.Inflection.DataDir.dir()}/#{locale}.etf")
    end)

  for {locale, path} <- suites do
    if locale in @pending do
      @tag :pending
    end

    test "upstream #{locale} inflection conformance suite" do
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
