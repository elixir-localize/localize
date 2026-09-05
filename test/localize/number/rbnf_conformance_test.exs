defmodule Localize.Number.RbnfConformanceTest do
  @moduledoc """
  CLDR 49's RBNF conformance suite (`common/testData/rbnf`).

  One `.ssv` file per locale, around 53,000 cases, exercising every public
  rule set. The header of each file gives the format:

      type;rule name;number;expected result
      type: spell=SpelloutRules, digits=OrdinalRules, number=NumberingSystemRules

  A handful of rows in the upstream data carry a stray leading `;`
  (`ga.ssv` line 53, among 23 others); the leading empty field is dropped
  rather than treated as a malformed row.
  """

  use ExUnit.Case, async: true

  @moduletag :conformance
  @moduletag timeout: 600_000

  @data_dir Path.join([__DIR__, "..", "..", "support", "data", "rbnf_conformance"])

  # All 52,691 cases match ICU exactly. Any mismatch is a regression, so the
  # test asserts zero rather than carrying a ratchet.
  defp locales do
    @data_dir
    |> File.ls!()
    |> Enum.filter(&String.ends_with?(&1, ".ssv"))
    |> Enum.map(&{Path.basename(&1, ".ssv") |> String.replace("_", "-"), &1})
    |> Enum.sort()
  end

  defp cases(file) do
    @data_dir
    |> Path.join(file)
    |> File.stream!()
    |> Stream.map(&String.trim_trailing(&1, "\n"))
    |> Stream.reject(&(&1 == "" or String.starts_with?(&1, "#")))
    |> Stream.map(&(&1 |> String.trim_leading(";") |> String.split(";")))
    |> Enum.filter(&match?([_, _, _, _], &1))
  end

  # `%spellout-cardinal` in the fixture is `spellout_cardinal` here, and an
  # empty rule name means the group's default rule set.
  defp rule_name(""), do: :default

  defp rule_name(rule) do
    rule |> String.trim_leading("%") |> String.replace("-", "_")
  end

  defp number(string) do
    case Integer.parse(string) do
      {integer, ""} ->
        integer

      _ ->
        case Float.parse(string) do
          {float, ""} -> float
          _ -> :skip
        end
    end
  end

  test "every case matches ICU" do
    failures =
      Enum.reduce(locales(), [], fn {locale, file}, acc ->
        Enum.reduce(cases(file), acc, fn [_type, rule, num, expected], failures ->
          case number(num) do
            :skip ->
              failures

            value ->
              case Localize.Number.Rbnf.to_string(value, rule_name(rule), locale: locale) do
                {:ok, ^expected} -> failures
                other -> [{locale, rule, num, expected, other} | failures]
              end
          end
        end)
      end)

    assert failures == [],
           """
           #{length(failures)} of the RBNF conformance cases no longer match ICU:

           #{failures |> Enum.reverse() |> Enum.take(10) |> Enum.map_join("\n", fn {locale, rule, num, expected, got} -> "  #{locale} #{rule} #{num}: expected #{inspect(expected)}, got #{inspect(got)}" end)}
           """
  end
end
